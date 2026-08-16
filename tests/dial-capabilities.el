;;; Dial's optional capabilities (pkg/dial/dial.el). The contract:
;; what the buffer cannot actually do is left off the controls line,
;; while the commands stay bound and refuse with a message; and "can
;; do" is judged per item against the paths `dial-reset' really has —
;; a default that matches no value entry, or a :reset that is present
;; but nil, advertises nothing. Plus the two behaviors around them: a
;; prompting value is declared with :prompts rather than sniffed out
;; of its setter form, and the controls line reads the buffer's live
;; keymaps rather than `dial-mode-map'.
;;
;; The test logic is calc-independent — probe buffers over a plain
;; variable — but the file runs under this repo's maf-step harness;
;; moving it out with dial would mean converting it to ERT.

(require 'dial)

(defvar dialtest--value nil)

(defun dialtest--open (items &rest config)
  "Open the probe buffer over ITEMS with CONFIG; return the buffer.
`save-window-excursion' so the cockpit's windows stay put; every check
runs with the buffer current rather than shown."
  (setq dialtest--value 'a)
  (save-window-excursion
    (apply #'dial-open "*dial-test*" items
           :raw (lambda (_) dialtest--value)
           config)))

(defun dialtest--controls ()
  "The probe buffer's controls line — the first line — as plain text.
From `point-min', not from point, which the open leaves on a row."
  (with-current-buffer "*dial-test*"
    (save-excursion
      (goto-char (point-min))
      (buffer-substring-no-properties (point) (line-end-position)))))

(defun dialtest--refused (command)
  "Run COMMAND on the probe buffer's first row; return its `user-error', or nil."
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (dial--move-line 1)
    (condition-case err
        (progn (call-interactively command) nil)
      (user-error (cadr err)))))

(maf-step

  ;; --- A bare consumer: no defaults, no save, no keys column ---

  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :values ((a "on"  (setq dialtest--value 'a))
                             (b "off" (setq dialtest--value 'b))))))

  ;; The line advertises only what the buffer can do, and drops the
  ;; changed-highlight legend with the defaults that would earn it.
  (let ((line (dialtest--controls)))
    (cl-assert (string-match-p "select" line))
    (cl-assert (string-match-p "set" line))
    (cl-assert (not (string-match-p "reset" line)) t "reset advertised: %s" line)
    (cl-assert (not (string-match-p "changed" line)))
    (cl-assert (not (string-match-p "keys" line)))
    (cl-assert (not (string-match-p "save" line)))
    (cl-assert (not (string-match-p "default" line))))

  ;; The hidden commands stay bound and say what is missing.
  (cl-assert (equal (dialtest--refused 'dial-reset)
                    "No default to reset to"))
  (cl-assert (equal (dialtest--refused 'dial-save)
                    "Nowhere to save these settings"))
  (cl-assert (equal (dialtest--refused 'dial-toggle-keys)
                    "No key column here"))
  (cl-assert (equal (dialtest--refused 'dial-toggle-changed-only)
                    "No defaults here to filter by"))

  ;; --- Defaults that exist but cannot act advertise nothing ---

  ;; An open-domain item with a :default callback but no :write: there
  ;; is a default value, and no path that resets to it — no :reset, no
  ;; entry to run, no writer. The default is still known, so the row
  ;; can show as changed and the legend stays.
  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :read (ignore)))
   :default (lambda (_) 5))
  (let ((line (dialtest--controls)))
    (cl-assert (not (string-match-p "reset" line)) t "dead reset shown: %s" line)
    (cl-assert (string-match-p "default" line)))
  (cl-assert (equal (dialtest--refused 'dial-reset)
                    "No default to reset to"))

  ;; A :reset that is present but nil counts as absent, the way
  ;; `dial-reset' itself reads it.
  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :reset nil
                    :values ((a "on"  (setq dialtest--value 'a))
                             (b "off" (setq dialtest--value 'b))))))
  (cl-assert (not (string-match-p "reset" (dialtest--controls))))
  (cl-assert (equal (dialtest--refused 'dial-reset)
                    "No default to reset to"))

  ;; A stated :default naming no value entry cannot reset, so reset is
  ;; not advertised — but the row knows it is off that default, and
  ;; the live value says so on a tinted ground.
  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :default z
                    :values ((a "on"  (setq dialtest--value 'a))
                             (b "off" (setq dialtest--value 'b))))))
  (let ((line (dialtest--controls)))
    (cl-assert (not (string-match-p "reset" line)))
    (cl-assert (string-match-p "default" line)))
  (cl-assert (equal (dialtest--refused 'dial-reset)
                    "No default to reset to"))
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (search-forward "on")
    (cl-assert (memq 'dial-changed
                     (ensure-list (get-text-property (match-beginning 0)
                                                     'face)))))

  ;; --- An item whose own :default reaches a value entry ---

  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :default b
                    :values ((a "on"  (setq dialtest--value 'a))
                             (b "off" (setq dialtest--value 'b))))))

  ;; Reset and the legend come back for it; the changed filter cannot —
  ;; it compares raw values through the callback the buffer lacks.
  (let ((line (dialtest--controls)))
    (cl-assert (string-match-p "reset" line))
    (cl-assert (string-match-p "default" line))
    (cl-assert (not (string-match-p "changed" line))))

  ;; The setting is off its stated default, so the live value is tinted
  ;; and the default itself carries no mark of its own,
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (search-forward "on")
    (cl-assert (memq 'dial-changed
                     (ensure-list (get-text-property (match-beginning 0)
                                                     'face))))
    (search-forward "off")
    (cl-assert (equal (ensure-list (get-text-property (match-beginning 0)
                                                      'face))
                      '(shadow))))

  ;; and d puts the setting on it, through the value's own setter —
  ;; after which the live value is back to bare.
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (dial--move-line 1)
    (dial-reset)
    (cl-assert (eq dialtest--value 'b))
    (goto-char (point-min))
    (search-forward "off")
    (cl-assert (memq 'dial-value
                     (ensure-list (get-text-property (match-beginning 0)
                                                     'face)))))

  ;; --- An item with only a :reset form ---

  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :reset (setq dialtest--value 'r)
                    :values ((a "on"  (setq dialtest--value 'a))
                             (b "off" (setq dialtest--value 'b))))))

  ;; Resettable, so d shows; but no default is nameable, so no changed
  ;; highlight and no legend claiming one.
  (let ((line (dialtest--controls)))
    (cl-assert (string-match-p "reset" line))
    (cl-assert (not (string-match-p "default" line))))
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (dial--move-line 1)
    (dial-reset)
    (cl-assert (eq dialtest--value 'r)))

  ;; --- Both callbacks make every row resettable ---

  ;; The write path needs no value entry: :default plus :write resets
  ;; an open-domain row directly.
  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :read (ignore)))
   :default (lambda (_) 'd)
   :write (lambda (_ value) (setq dialtest--value value)))
  (cl-assert (string-match-p "reset" (dialtest--controls)))
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (dial--move-line 1)
    (dial-reset)
    (cl-assert (eq dialtest--value 'd)))

  ;; --- Value keys compare by `equal', end to end ---

  ;; String keys, and a default callback returning a fresh string that
  ;; is `equal' but not `eq'. What the chips highlight, the controls line,
  ;; reset, and the value label all have to agree on — an identity-based
  ;; lookup anywhere splits them.
  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :values (("[]" "square" (setq dialtest--value "[]"))
                             ("{}" "curly"  (setq dialtest--value "{}")))))
   :default (lambda (_) (concat "[" "]")))
  (with-current-buffer "*dial-test*"
    (setq dialtest--value "{}")
    (dial-refresh))

  ;; The fresh-but-equal default still earns reset and the legend,
  (let ((line (dialtest--controls)))
    (cl-assert (string-match-p "reset" line) t "string default lost reset: %s" line)
    (cl-assert (string-match-p "default" line)))

  ;; shows the live value as moved off it,
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (search-forward "curly")
    (cl-assert (memq 'dial-changed
                     (ensure-list (get-text-property (match-beginning 0)
                                                     'face)))))

  ;; labels the live value rather than printing it raw,
  (with-current-buffer "*dial-test*"
    (cl-assert (equal (dial--value-string
                       'dialtest-item (alist-get 'dialtest-item dial-items))
                      "curly")))

  ;; and resets through the entry's own setter.
  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (dial--move-line 1)
    (dial-reset)
    (cl-assert (equal dialtest--value "[]")))

  ;; --- Prompting is metadata, not setter syntax ---

  (dialtest--open
   `((dialtest-item :group "G" :label "Item" :doc "A setting."
                    :values ((a "one" (setq dialtest--value 'a))
                             ;; Mentions the symbol the old sniffing
                             ;; looked for; must set, not pend.
                             (b "two" (progn 'call-interactively
                                             (setq dialtest--value 'b)))
                             ;; Declares itself; must pend, not run.
                             (c "three" (error "ran a prompting setter")
                                :prompts t)))))

  (with-current-buffer "*dial-test*"
    (goto-char (point-min))
    (dial--move-line 1)
    (dial-next-value)
    (cl-assert (eq dialtest--value 'b))
    (cl-assert (null dial--pending))
    (dial-next-value)
    (cl-assert (eq dialtest--value 'b))
    (cl-assert (equal dial--pending '(dialtest-item . 2))))

  ;; --- The controls line follows the live keymaps ---

  ;; Refresh moved from g to x in a buffer-local copy of the map: the
  ;; line must say x, not keep quoting `dial-mode-map'.
  (with-current-buffer "*dial-test*"
    (use-local-map (copy-keymap dial-mode-map))
    (define-key (current-local-map) (kbd "g") nil)
    (define-key (current-local-map) (kbd "x") #'dial-refresh)
    (dial-refresh)
    (cl-assert (string-match-p "x refresh" (dialtest--controls)))
    (cl-assert (not (string-match-p "g refresh" (dialtest--controls)))))

  ;; --- Any motion onto another row echoes its :doc ---

  ;; Not only dial's own n and p: C-n, the arrows, a scroll or a click
  ;; land point on a row too, and the doc follows through
  ;; `post-command-hook'. Only a change of row speaks, so a command
  ;; that stays on the row leaves the echo area to its own message.
  (dialtest--open
   `((dialtest-one :group "G" :label "One" :doc "The first setting."
                   :values ((a "on" (setq dialtest--value 'a))))
     (dialtest-two :group "G" :label "Two" :doc "The second setting."
                   :values ((a "on" (setq dialtest--value 'a))))))
  ;; The harness runs under `inhibit-message', so the echo is read by
  ;; catching what `message' is handed rather than off the echo area.
  (with-current-buffer "*dial-test*"
    (let ((said nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (when fmt (push (apply #'format fmt args) said)))))
        (goto-char (point-min))
        (dial--move-line 1)
        (run-hooks 'post-command-hook)
        (cl-assert (equal said '("The first setting.")))
        ;; Plain `next-line', as C-n runs it — no dial command involved.
        (next-line 1)
        (run-hooks 'post-command-hook)
        (cl-assert (equal (car said) "The second setting."))
        ;; Staying put says nothing new: what the last command said
        ;; stands.
        (setq said nil)
        (forward-char 1)
        (run-hooks 'post-command-hook)
        (cl-assert (null said))
        (previous-line 1)
        (run-hooks 'post-command-hook)
        (cl-assert (equal said '("The first setting."))))))

  ;; Leave nothing behind.
  (progn (kill-buffer "*dial-test*")
         (setq dialtest--value nil)
         :cleaned))
