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

;; Loaded on demand through calc's autoload machinery.
(declare-function calc-prepare-selection "calc-sel")
(declare-function calc-find-selected-part "calc-sel")

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

(defvar calc-web--dispatching nil
  "Non-nil while a browser key's command is running.
`calc-web--on-command' sits on `post-command-hook', which the
dispatcher now runs too; this keeps that from pushing a half-done
state — the dispatcher pushes once itself when the key is finished.")

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

(defconst calc-web--point-open "\\bbox[2px, border: 1.5px dashed #b4befe]{"
  "LaTeX opening the at-point highlight: dashed, an eye lighter than a
selection's solid box — point rests somewhere all the time, and the
always-on box should read as where you are, not as something held.")

(defun calc-web--marked-latex (value sel open)
  "Format VALUE as LaTeX with SEL boxed, via the calcwebsel marker.
OPEN is the highlight's opening LaTeX. The marker's own parentheses
are traded for the \\bbox braces — the box already draws the
selection's boundary, the way maf's highlight does in the buffer."
  (let* ((str (calc-web--latex (calc-web--mark value sel)))
         (start (string-search "calcwebsel" str))
         (oparen (and start (string-search "(" str start))))
    (if (null oparen)
        str
      ;; The argument's parentheses may be plain or \left( \right) —
      ;; calc picks per argument. Scan to the balanced close, then
      ;; drop the \right the \left( form leaves inside the span.
      (let ((depth 1)
            (i (1+ oparen)))
        (while (and (> depth 0) (< i (length str)))
          (pcase (aref str i)
            (?\( (setq depth (1+ depth)))
            (?\) (setq depth (1- depth))))
          (setq i (1+ i)))
        (concat (substring str 0 start)
                open
                (replace-regexp-in-string
                 " *\\\\right *\\'" ""
                 (substring str (1+ oparen) (1- i)))
                "}"
                (substring str i))))))

(defun calc-web--entry-latex (entry part)
  "Format stack ENTRY as LaTeX, its highlight baked in if it has one.
An explicit selection gets the solid box. PART, non-nil only for the
entry point stands on, is the sub-formula at point; without a
selection it gets the dashed box — the always-on highlight that
follows point through the formula."
  (let ((value (car entry))
        (sel (nth 2 entry)))
    (cond (sel (calc-web--marked-latex value sel calc-web--sel-open))
          (part (calc-web--marked-latex value part calc-web--point-open))
          (t (calc-web--latex value)))))

(defun calc-web--part-at-point ()
  "The sub-formula point is on, or nil off the stack or between parts.
`calc-select-here's own resolver: `calc-prepare-selection' rebuilds
the entry's composition with position tags and
`calc-find-selected-part' reads the node under point's column out of
it. Errors — a home line, a mid-redraw call — just mean no highlight."
  (when (and (> (calc-web--cursor) 0)
             ;; Mid-edit the buffer is plain text: the composition the
             ;; resolver would read no longer matches it.
             (not (bound-and-true-p maf-edit-mode)))
    (ignore-errors
      (save-excursion
        (calc-prepare-selection)
        (calc-find-selected-part)))))

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
    (let ((cursor (calc-web--cursor))
          (part (calc-web--part-at-point))
          (level 0))
      (json-serialize
       `( :stack ,(vconcat
                   (cl-loop for entry in calc-stack
                            unless (eq (car entry) 'top-of-stack)
                            collect (calc-web--entry-latex
                                     entry
                                     (and (= (cl-incf level) cursor) part))))
          :cursor ,cursor
        :entry ,(or calc-web--entry :null)
        ;; An active maf-edit session: the stack is plain editable
        ;; text, and the browser shows the line being edited with the
        ;; caret at its column, since the serialized stack still holds
        ;; the values from before the edit.
        :edit ,(if (bound-and-true-p maf-edit-mode)
                   (buffer-substring-no-properties (line-beginning-position)
                                                   (line-end-position))
                 :null)
        :editCol ,(if (bound-and-true-p maf-edit-mode)
                      (- (point) (line-beginning-position))
                    0)
        ;; A live minibuffer, mirrored: the prompt a blocked command
        ;; put up and whatever has been typed at it so far. This is
        ;; how ", x"'s \"Variable:\" or an algebraic entry shows in
        ;; the browser while the keys stream through the event queue.
        :prompt ,(if-let ((w (active-minibuffer-window)))
                     (with-current-buffer (window-buffer w)
                       (minibuffer-prompt))
                   :null)
        :minibuf ,(if-let ((w (active-minibuffer-window)))
                      (with-current-buffer (window-buffer w)
                        (minibuffer-contents-no-properties))
                    :null)
        :pending ,(if calc-web--prefix
                      (string-join calc-web--prefix " ")
                    :null)
        :flags ( :hyp ,(if (plist-get calc-web--flags :hyp) t :false)
                 :inv ,(if (plist-get calc-web--flags :inv) t :false)
                 :opt ,(if (plist-get calc-web--flags :opt) t :false))
        :trail ,(vconcat (calc-web--trail))
        :error ,(or calc-web--error :null))))))

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
  (when (and (or (derived-mode-p 'calc-mode)
                 ;; Typing at a mirrored minibuffer: each key is a
                 ;; command in the minibuffer's own buffer, and the
                 ;; browser echo has to follow it.
                 (minibufferp))
             (not calc-web--dispatching))
    (calc-web--push)))

(defun calc-web--on-minibuffer (&rest _)
  "Push when a minibuffer opens or closes; on its setup/exit hooks.
A blocked read's prompt reaches the browser through this: the read
sits between commands, so no command hook fires until it is answered
— setup is the one moment the prompt can be announced. Bound checks
aside, the push itself is cheap and clientless pushes are no-ops."
  (calc-web--push))

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

(defconst calc-web--digit-starters '(calcDigit-start maf-digit-start)
  "Commands whose whole job is a minibuffer number read.
Both read the rest of the number themselves, recursively — a wait no
process filter can satisfy — so a key resolving to one goes to the
`calc-web--entry' accumulator instead.")

(defconst calc-web--modifier-commands
  '((calc-hyperbolic . :hyp) (calc-inverse . :inv) (calc-option . :opt))
  "Modifier commands and the pending flag each arms.
They work through `calc-fancy-prefix', which needs the command loop;
here the resolved command toggles its flag in `calc-web--flags' and
the next dispatched command runs under it.")

(defun calc-web--key (key)
  "Resolve the chord so far plus KEY against the buffer's active maps.
`key-binding' rather than `calc-mode-map': the browser is a thin
terminal onto this buffer, so a key means exactly what it would mean
typed there — maf's bindings when maf-mode is on, an active maf-edit
session's editing keys, the global map's motion commands.

A keymap answer keeps the chord growing. A digit-starter or modifier
command is intercepted (see `calc-web--digit-starters' and
`calc-web--modifier-commands'). Any other command commits a pending
number entry first, then runs under the armed modifier flags, bound
around the call and cleared after, so a modifier covers exactly one
command. A dead end is reported whole (`unbound: a X')."
  (let* ((keys (append calc-web--prefix (list key)))
         (desc (string-join keys " "))
         (seq (condition-case nil (kbd desc) (error nil)))
         (cmd (and seq (key-binding seq))))
    (cond
     ((keymapp cmd)
      (setq calc-web--prefix keys))
     ((memq cmd calc-web--digit-starters)
      (setq calc-web--entry (concat (or calc-web--entry "") key)))
     ((assq cmd calc-web--modifier-commands)
      (let ((flag (cdr (assq cmd calc-web--modifier-commands))))
        (setq calc-web--flags
              (plist-put calc-web--flags flag
                         (not (plist-get calc-web--flags flag))))))
     ((commandp cmd)
      (setq calc-web--prefix nil)
      (calc-web--commit-entry)
      ;; A slice of the command loop, not a bare funcall: the event
      ;; has to be the browser's key — `calc-minus' and friends read
      ;; it — and the command hooks have to run, because that is where
      ;; modes keep their between-keys discipline (maf-edit's
      ;; machine-owned prefixes, the preview's redraw). Without them a
      ;; dispatched key behaves almost, but not exactly, like a typed
      ;; one.
      (let ((last-command-event (aref seq (1- (length seq))))
            (this-command cmd)
            (calc-web--dispatching t)
            (calc-hyperbolic-flag (plist-get calc-web--flags :hyp))
            (calc-inverse-flag (plist-get calc-web--flags :inv))
            (calc-option-flag (plist-get calc-web--flags :opt)))
        (unwind-protect
            (progn
              (run-hooks 'pre-command-hook)
              (call-interactively cmd)
              (run-hooks 'post-command-hook))
          (setq calc-web--flags nil)
          (setq last-command cmd))))
     (t
      (setq calc-web--prefix nil)
      (setq calc-web--error (format "unbound: %s" desc))))))

(defun calc-web--dispatch (key)
  "Route KEY, a key description string from the browser, into calc.
Nearly everything resolves through the buffer's own keymaps in
`calc-web--key'; what is handled here is the state no keymap knows:
ESC abandons whatever is pending — entry, chord, flags — and while a
number entry is underway DEL edits it, RET and SPC commit it, and
`;' appends the fraction colon, as it does in maf's entry map.
Errors are trapped into `calc-web--error'; every path ends in one
push."
  (with-current-buffer (calc-web--buffer)
    (condition-case err
        (cond
         ((equal key "ESC")
          (setq calc-web--entry nil
                calc-web--prefix nil
                calc-web--flags nil))
         ((and calc-web--entry (equal key "DEL"))
          (setq calc-web--entry (and (> (length calc-web--entry) 1)
                                     (substring calc-web--entry 0 -1))))
         ((and calc-web--entry (member key '("RET" "SPC")))
          (calc-web--commit-entry))
         ((and calc-web--entry (equal key ";"))
          (setq calc-web--entry (concat calc-web--entry ":")))
         (t
          (calc-web--key key)))
      (error (setq calc-web--error (error-message-string err))))
    ;; The cursor-intangible bounce lives in redisplay and adjusts the
    ;; selected window's point; a dispatched key never goes through
    ;; it. Without this, maf-edit's machine-owned prefixes could hold
    ;; point — and silently take the next self-insert.
    (when (get-text-property (point) 'cursor-intangible)
      (goto-char (or (next-single-property-change (point) 'cursor-intangible)
                     (point-max))))
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
    (cond
     ((not (stringp key))
      (websocket-send-text
       ws (json-serialize '(:error "expected {\"key\": \"...\"}"))))
     ;; A dispatched command is mid-flight, blocked in an input read of
     ;; its own — `maf-quick-variable's letter, an algebraic entry's
     ;; minibuffer, a y-or-n-p. Filters run inside such waits, which is
     ;; how this message got here at all; the key is the input the
     ;; command is waiting for, so it goes to the event queue rather
     ;; than to a second dispatch.
     (calc-web--dispatching
      (when-let ((seq (condition-case nil (kbd key) (error nil))))
        (setq unread-command-events
              (nconc unread-command-events
                     (listify-key-sequence seq)))))
     (t
      (calc-web--dispatch key)))))

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
  (add-hook 'post-command-hook #'calc-web--on-command)
  (add-hook 'minibuffer-setup-hook #'calc-web--on-minibuffer)
  (add-hook 'minibuffer-exit-hook #'calc-web--on-minibuffer))

(defun calc-web--stop ()
  "Close every client, stop the server, and unhook the push."
  (remove-hook 'post-command-hook #'calc-web--on-command)
  (remove-hook 'minibuffer-setup-hook #'calc-web--on-minibuffer)
  (remove-hook 'minibuffer-exit-hook #'calc-web--on-minibuffer)
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
