;; -*- lexical-binding: t; -*-
;;
;; web/calc-web.el
;;
;; Serve Emacs Calc to a browser over WebSocket. The browser is a dumb
;; terminal: it sends raw key input as {"key": "Q"} messages and renders
;; the LaTeX stack pushed back at it (see web/calc-web.js). All state
;; lives in Emacs — calc-mode runs normally, and the calc buffer stays
;; usable in parallel: a `post-command-hook' pushes after native
;; keystrokes too, so both views show the same stack.
;;
;; Phase 2 (docs/plans/web-client.org): the router accumulates chords
;; (`a x', `v p', ...) until the sequence resolves in `calc-mode-map',
;; routes the H/I/O modifier keys into their calc flags around the next
;; command, and the serializer carries the calc trail's tail. ESC
;; abandons everything pending.
;;
;; One wrinkle the plan's lookup-key sketch runs into: calc binds digits
;; to `calcDigit-start', which reads the rest of the number itself in a
;; recursive minibuffer edit — inside a process filter that read would
;; block the connection. The router accumulates digits here instead and
;; pushes the finished number when a non-digit key arrives.

(require 'calc)
(require 'calc-ext)
(require 'cl-lib)
(require 'websocket)

(defgroup calc-web nil
  "Browser rendering layer for Emacs Calc."
  :group 'calc)

(defcustom calc-web-port 7070
  "TCP port the WebSocket server listens on, on localhost only."
  :type 'integer
  :group 'calc-web)

(defvar calc-web--server nil
  "The live websocket server, or nil.")

(defvar calc-web--clients nil
  "Open client connections; every state change is pushed to each.")

(defvar calc-web--entry nil
  "The number the browser is mid-typing, as a string, or nil.
See the commentary: digits accumulate here rather than dispatching
into `calcDigit-start'.")

(defvar calc-web--prefix nil
  "Key descriptions of the chord typed so far, oldest first, or nil.
Grows while `lookup-key' answers a keymap; a command or a dead end
clears it either way.")

(defvar calc-web--flags nil
  "Pending modifier flags, as a plist of :hyp :inv :opt booleans.
Toggled by the H, I and O keys; bound into calc's flag variables
around the next command and cleared, so a modifier arms exactly one
keystroke, as it does in calc itself.")

(defcustom calc-web-trail-lines 30
  "How many trailing calc-trail lines are sent to clients."
  :type 'integer
  :group 'calc-web)

(defvar calc-web--error nil
  "Error text for the client from the last dispatch, or nil.
Sent in the next push and cleared: an error belongs to the keystroke
that caused it, not to every render after.")

(defun calc-web--buffer ()
  "The calc buffer, created without display if it does not exist."
  (or (get-buffer "*Calculator*")
      (save-window-excursion (calc) (get-buffer "*Calculator*"))))

;;; Stack serializer

(defun calc-web--latex (value)
  "Format VALUE as a single line of LaTeX.
`calc-set-language' loads calc's latex tables on first use; the
buffer's own language is restored afterwards, so the Emacs-side
display never changes."
  (let ((lang calc-language)
        (opt calc-language-option))
    (unwind-protect
        (progn (calc-set-language 'latex nil t)
               (math-format-value value))
      (calc-set-language lang opt t))))

(defun calc-web--mark (value sel)
  "Copy VALUE with SEL, an eq subtree of it, wrapped in the marker.
The marker is an unknown function, which calc's latex language prints
by name — `calcwebsel(...)' — giving `calc-web--marked-latex' a
scannable handle on where the selection landed in the string."
  (cond ((eq value sel) (list 'calcFunc-calcwebsel sel))
        ((Math-primp value) value)
        (t (cons (car value)
                 (mapcar (lambda (x) (calc-web--mark x sel)) (cdr value))))))

(defconst calc-web--sel-open "\\bbox[2px, border: 1.5px solid #89b4fa]{"
  "LaTeX opening the selection highlight; MathJax's \\bbox.")

(defun calc-web--marked-latex (value sel)
  "Format VALUE as LaTeX with SEL boxed, via the calcwebsel marker.
The marker's own parentheses are traded for the \\bbox braces — the
box already draws the selection's boundary, the way maf's highlight
does in the buffer."
  (let* ((str (calc-web--latex (calc-web--mark value sel)))
         (start (string-search "calcwebsel(" str)))
    (if (null start)
        str
      (let* ((open (+ start (length "calcwebsel(")))
             (depth 1)
             (i open))
        (while (and (> depth 0) (< i (length str)))
          (pcase (aref str i)
            (?\( (setq depth (1+ depth)))
            (?\) (setq depth (1- depth))))
          (setq i (1+ i)))
        (concat (substring str 0 start)
                calc-web--sel-open
                (substring str open (1- i))
                "}"
                (substring str i))))))

(defun calc-web--entry-latex (entry)
  "Format stack ENTRY as LaTeX, selection highlighted when it has one."
  (let ((value (car entry))
        (sel (nth 2 entry)))
    (if sel
        (calc-web--marked-latex value sel)
      (calc-web--latex value))))

(defun calc-web--cursor ()
  "The stack level point is on: 1 is the top, 0 is home."
  (let ((idx (calc-locate-cursor-element (point))))
    (if (> idx 0) (min idx (calc-stack-size)) 0)))

(defun calc-web--trail ()
  "The last `calc-web-trail-lines' lines of the calc trail."
  (with-current-buffer (calc-trail-buffer)
    (save-excursion
      (goto-char (point-max))
      (let ((end (point)))
        (forward-line (- calc-web-trail-lines))
        (split-string (buffer-substring-no-properties (point) end)
                      "\n" t)))))

(defun calc-web--payload ()
  "The current calc state as a JSON string.
Stack entries are LaTeX, ordered top of stack first. `:entry' is the
number being typed, `:pending' the chord so far, `:flags' the armed
modifiers, `:trail' the trail's tail, `:error' the last dispatch
error — null (or all-false, for flags) when there is nothing to say."
  (with-current-buffer (calc-web--buffer)
    (json-serialize
     `( :stack ,(vconcat
                 (cl-loop for entry in calc-stack
                          unless (eq (car entry) 'top-of-stack)
                          collect (calc-web--entry-latex entry)))
        :cursor ,(calc-web--cursor)
        :entry ,(or calc-web--entry :null)
        :pending ,(if calc-web--prefix
                      (string-join calc-web--prefix " ")
                    :null)
        :flags ( :hyp ,(if (plist-get calc-web--flags :hyp) t :false)
                 :inv ,(if (plist-get calc-web--flags :inv) t :false)
                 :opt ,(if (plist-get calc-web--flags :opt) t :false))
        :trail ,(vconcat (calc-web--trail))
        :error ,(or calc-web--error :null)))))

(defun calc-web--push ()
  "Send the current state to every connected client.
A client whose send fails is dropped rather than allowed to wedge the
loop; the serializer's own errors go to the clients as an error
payload, so a formula LaTeX cannot write still reports itself."
  (when calc-web--clients
    (let ((payload (condition-case err
                       (calc-web--payload)
                     (error (json-serialize
                             `(:error ,(format "serialize: %s"
                                               (error-message-string err))))))))
      (setq calc-web--error nil)
      (dolist (ws calc-web--clients)
        (condition-case nil
            (websocket-send-text ws payload)
          (error (setq calc-web--clients (delq ws calc-web--clients))))))))

(defun calc-web--on-command ()
  "Push after any command in the calc buffer; on `post-command-hook'.
This is what keeps a browser current while calc is driven natively in
Emacs — keys routed from the browser push explicitly in
`calc-web--dispatch', which never passes through the command loop."
  (when (derived-mode-p 'calc-mode)
    (calc-web--push)))

;;; Key router

(defun calc-web--commit-entry ()
  "Push the accumulated number, if any, onto the stack."
  (when calc-web--entry
    (let ((str calc-web--entry))
      (setq calc-web--entry nil)
      (let ((n (math-read-number str)))
        (if n
            (calc-push n)
          (setq calc-web--error (format "bad number: %s" str)))))))

(defun calc-web--toggle-flag (key)
  "Toggle the pending modifier KEY stands for: H, I or O."
  (let ((flag (pcase key ("H" :hyp) ("I" :inv) ("O" :opt))))
    (setq calc-web--flags
          (plist-put calc-web--flags flag
                     (not (plist-get calc-web--flags flag))))))

(defun calc-web--key (key)
  "Resolve the chord so far plus KEY against `calc-mode-map'.
A keymap answer keeps the chord growing; a command runs under the
armed modifier flags, which are bound around the call and cleared
after it, so a modifier covers exactly one command; anything else is
a dead end, reported whole (`unbound: a X')."
  (let* ((keys (append calc-web--prefix (list key)))
         (desc (string-join keys " "))
         (seq (condition-case nil (kbd desc) (error nil)))
         (cmd (and seq (lookup-key calc-mode-map seq))))
    (cond
     ((keymapp cmd)
      (setq calc-web--prefix keys))
     ((commandp cmd)
      (setq calc-web--prefix nil)
      ;; Many calc commands read the key they were invoked by —
      ;; `calc-minus' and friends — so the event has to be the
      ;; browser's key, not whatever Emacs saw last.
      (let ((last-command-event (aref seq (1- (length seq))))
            (calc-hyperbolic-flag (plist-get calc-web--flags :hyp))
            (calc-inverse-flag (plist-get calc-web--flags :inv))
            (calc-option-flag (plist-get calc-web--flags :opt)))
        (unwind-protect
            (call-interactively cmd)
          (setq calc-web--flags nil))))
     (t
      (setq calc-web--prefix nil)
      (setq calc-web--error (format "unbound: %s" desc))))))

(defun calc-web--dispatch (key)
  "Route KEY, a key description string from the browser, into calc.
Digits and the decimal point accumulate in `calc-web--entry' (along
with `:'/`;', `e' and `#' once one is underway); DEL edits it and
RET commits it, calc-style. H, I and O arm their modifier flags for
the next command. <up> and <down> move point across stack levels.
ESC abandons whatever is pending — entry, chord, and flags. Any
other key commits the pending number first, then goes to the chord
resolver (`calc-web--key'). Errors are trapped into
`calc-web--error'; every path ends in one push. Digit and modifier
keys mid-chord go to the resolver instead of their usual meaning:
`a 0' is a chord, not the start of a number."
  (with-current-buffer (calc-web--buffer)
    (condition-case err
        (cond
         ((equal key "ESC")
          (setq calc-web--entry nil
                calc-web--prefix nil
                calc-web--flags nil))
         ;; Digits and the point start an entry; the fraction,
         ;; exponent and radix characters only extend one, keeping
         ;; their command meanings otherwise. `;' is `:' here, as in
         ;; maf — the fraction key without the shift.
         ((and (null calc-web--prefix)
               (or (and (= (length key) 1)
                        (cl-find (aref key 0) "0123456789."))
                   (and calc-web--entry
                        (member key '(":" ";" "e" "#")))))
          (setq calc-web--entry (concat (or calc-web--entry "")
                                        (if (equal key ";") ":" key))))
         ((member key '("<up>" "<down>"))
          (calc-web--commit-entry)
          (calc-cursor-stack-index
           (max 0 (min (calc-stack-size)
                       (+ (calc-web--cursor)
                          (if (equal key "<up>") 1 -1))))))
         ((and calc-web--entry (equal key "DEL"))
          (setq calc-web--entry (and (> (length calc-web--entry) 1)
                                     (substring calc-web--entry 0 -1))))
         ((and calc-web--entry (equal key "RET"))
          (calc-web--commit-entry))
         ((and (null calc-web--prefix) (member key '("H" "I" "O")))
          (calc-web--toggle-flag key))
         (t
          (calc-web--commit-entry)
          (calc-web--key key)))
      (error (setq calc-web--error (error-message-string err))))
    ;; Point moved here is buffer point; a calc window that is not
    ;; selected displays — and, on reselection, snaps back to — its own
    ;; window point. Sync it, so browser-driven motion shows in the
    ;; parallel Emacs window and survives the user clicking back in.
    (let ((win (get-buffer-window (current-buffer) t)))
      (when (and win (not (eq win (selected-window))))
        (set-window-point win (point))))
    (calc-web--push)))

;;; Server

(defun calc-web--on-open (ws)
  "Register WS and bring it current with an immediate push."
  (push ws calc-web--clients)
  (websocket-send-text ws (calc-web--payload)))

(defun calc-web--on-message (ws frame)
  "Route FRAME's {\"key\": ...} payload; anything else is answered with an error."
  (let* ((msg (ignore-errors
                (json-parse-string (websocket-frame-text frame)
                                   :object-type 'plist)))
         (key (plist-get msg :key)))
    (if (stringp key)
        (calc-web--dispatch key)
      (websocket-send-text
       ws (json-serialize '(:error "expected {\"key\": \"...\"}"))))))

(defun calc-web--on-close (ws)
  "Forget WS."
  (setq calc-web--clients (delq ws calc-web--clients)))

(defun calc-web--start ()
  "Start the server on `calc-web-port' and hook the push."
  (when calc-web--server
    (calc-web--stop))
  (setq calc-web--server
        (websocket-server calc-web-port
                          :host 'local
                          :on-open #'calc-web--on-open
                          :on-message #'calc-web--on-message
                          :on-close #'calc-web--on-close))
  (add-hook 'post-command-hook #'calc-web--on-command))

(defun calc-web--stop ()
  "Close every client, stop the server, and unhook the push."
  (remove-hook 'post-command-hook #'calc-web--on-command)
  (dolist (ws calc-web--clients)
    (ignore-errors (websocket-close ws)))
  (setq calc-web--clients nil)
  (when calc-web--server
    (websocket-server-close calc-web--server)
    (setq calc-web--server nil)))

;;;###autoload
(define-minor-mode calc-web-mode
  "Serve the calc stack to browser clients over WebSocket.

Clients (web/calc-web.html) send raw keys and render the LaTeX stack
pushed back; all computation and state stay in Emacs. The calc buffer
remains fully usable in parallel — native keystrokes push to the
browser through `post-command-hook'."
  :global t
  :lighter " CWeb"
  :group 'calc-web
  (if calc-web-mode
      (calc-web--start)
    (calc-web--stop)))

(provide 'calc-web)
