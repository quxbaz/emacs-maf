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
;; Phase 1 (docs/plans/web-client.org): single-key routing only. One
;; wrinkle the plan's lookup-key sketch runs into: calc binds digits to
;; `calcDigit-start', which reads the rest of the number itself in a
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

(defun calc-web--payload ()
  "The current calc state as a JSON string.
Stack entries are LaTeX, ordered top of stack first. `:entry' is the
number being typed, `:flags' the pending modifier flags, `:error' the
last dispatch error — each null when there is nothing to say."
  (with-current-buffer (calc-web--buffer)
    (json-serialize
     `( :stack ,(vconcat
                 (cl-loop for entry in calc-stack
                          unless (eq (car entry) 'top-of-stack)
                          collect (calc-web--latex (car entry))))
        :entry ,(or calc-web--entry :null)
        :flags ( :hyp ,(if calc-hyperbolic-flag t :false)
                 :inv ,(if calc-inverse-flag t :false)
                 :opt ,(if (bound-and-true-p calc-option-flag) t :false))
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

(defun calc-web--dispatch (key)
  "Route KEY, a key description string from the browser, into calc.
Digits and the decimal point accumulate in `calc-web--entry'; DEL
edits it and RET commits it, calc-style. Any other key commits the
pending number first, then dispatches through `calc-mode-map' —
single keys only in this phase, so a prefix key answers with an
error instead of waiting for a sequel that would arrive as its own
message. Errors are trapped into `calc-web--error'; every path ends
in one push."
  (with-current-buffer (calc-web--buffer)
    (condition-case err
        (cond
         ((and (= (length key) 1)
               (cl-find (aref key 0) "0123456789."))
          (setq calc-web--entry (concat (or calc-web--entry "") key)))
         ((and calc-web--entry (equal key "DEL"))
          (setq calc-web--entry (and (> (length calc-web--entry) 1)
                                     (substring calc-web--entry 0 -1))))
         ((and calc-web--entry (equal key "RET"))
          (calc-web--commit-entry))
         (t
          (calc-web--commit-entry)
          (let* ((seq (condition-case nil (kbd key) (error nil)))
                 (cmd (and seq (lookup-key calc-mode-map seq))))
            (cond
             ((commandp cmd)
              ;; Many calc commands read the key they were invoked by
              ;; — `calc-minus' and friends — so the event has to be
              ;; the browser's key, not whatever Emacs saw last.
              (let ((last-command-event (aref seq (1- (length seq)))))
                (call-interactively cmd)))
             ((keymapp cmd)
              (setq calc-web--error (format "prefix keys not yet supported: %s" key)))
             (t
              (setq calc-web--error (format "unbound: %s" key)))))))
      (error (setq calc-web--error (error-message-string err))))
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
