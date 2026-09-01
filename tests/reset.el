;; `maf-reset' and `maf-reset-settings' (src/stack.el). The contract:
;; reset empties the session — stack, undo/redo, trail — and re-reads
;; `calc-settings-file'; reset-settings restores the modes from that
;; file and leaves the session standing. The history survives both:
;; it is a log of what happened, not part of the session, and only
;; `maf-history-clear' empties it. A prefix argument
;; means "calc's factory defaults" for both, and then the settings file
;; is deliberately not read, since loading it would put the saved modes
;; straight back.
;;
;; The settings file is a temporary one the test writes, so the
;; assertions never depend on what is in the user's own ~/.emacs.d/calc.el.
;; Steps run in the calc buffer, so the `setq' below is buffer-local for
;; the mode variables and global for `calc-settings-file' — restored at
;; the end.

(defvar maf-test--settings-file nil)
(defvar maf-test--settings-orig 'unset
  "The real `calc-settings-file', saved while the throwaway is in use.
The `unset' sentinel rather than nil, since nil is a value
`calc-settings-file' can legitimately hold and so cannot also mean
nothing captured yet. See the restoring step below.")

(maf-step
  ;; A settings file in calc's own shape: the marker block `calc-reset'
  ;; re-evaluates, plus a stored variable outside it that only a full
  ;; `load' picks up.
  (progn
    (setq maf-test--settings-orig calc-settings-file
          maf-test--settings-file (make-temp-file "maf-reset-test" nil ".el"))
    (with-temp-file maf-test--settings-file
      (insert ";;; Mode settings stored by Calc\n"
              "(setq calc-symbolic-mode t)\n"
              "(setq calc-prefer-frac t)\n"
              ";;; End of mode settings\n"
              "(setq var-maf-test-canary 99)\n"))
    (setq calc-settings-file maf-test--settings-file)
    (makunbound 'var-maf-test-canary)
    maf-test--settings-file)

  ;; --- maf-reset: everything in the session goes ---

  ;; Build a session worth losing: two entries, a selection, an undo
  ;; record, a trail line, and modes knocked off their saved values.
  (maf-push "6 x + 12")
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 2) (search-forward "x"))
  (call-interactively 'calc-select-here)
  (progn (calc-record 42 "test") (calc-cursor-stack-index 1) nil)
  (progn (setq calc-symbolic-mode nil calc-prefer-frac nil) nil)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (maf--sel-any-p))
  (cl-assert calc-undo-list)
  (cl-assert (> (buffer-size (get-buffer "*Calc Trail*")) 0))

  ;; Give the history a state to keep across the reset, when the
  ;; module is loaded. A direct capture is what the post-command hook
  ;; would have done; it records only if the stack changed, so this is
  ;; harmless when hooks already captured the pushes above.
  (when (fboundp 'maf-history--capture)
    (maf-history--capture)
    (cl-assert maf-history--states))

  ;; One command clears the lot.
  (call-interactively 'maf-reset)
  (cl-assert (= (calc-stack-size) 0))
  (cl-assert (null calc-undo-list))
  (cl-assert (null calc-redo-list))
  (cl-assert (= (buffer-size (get-buffer "*Calc Trail*")) 0))

  ;; The saved modes are back — from the marker block, which
  ;; `calc-reset' handles — and so is the stored variable outside it,
  ;; which only the full re-read of the file reaches.
  (cl-assert (eq calc-symbolic-mode t))
  (cl-assert (eq calc-prefer-frac t))
  (cl-assert (equal (bound-and-true-p var-maf-test-canary) 99))

  ;; maf-mode survives its own command: `calc-reset' re-runs `calc-mode',
  ;; which kills the buffer-local that keeps maf's keymap alive.
  (cl-assert (bound-and-true-p maf-mode))
  (cl-assert (eq (key-binding (kbd "C-M-k")) 'maf-reset))
  (cl-assert (eq (key-binding (kbd "C-M-l")) 'maf-reset-settings))

  ;; The history survives — it is a log of what happened, not part of
  ;; the session, and stays browsable after the wipe.
  (cl-assert (or (not (fboundp 'maf-history--capture))
                 maf-history--states))

  ;; --- maf-reset with a prefix: factory defaults ---

  ;; C-u picks calc's defaults over the saved settings, and then leaves
  ;; the file unread — the legacy version loaded it either way, which
  ;; put the saved modes straight back and made the prefix a no-op.
  (maf-push "1")
  (let ((current-prefix-arg '(4)))
    (call-interactively 'maf-reset))
  (cl-assert (= (calc-stack-size) 0))
  (cl-assert (null calc-symbolic-mode))
  (cl-assert (null calc-prefer-frac))

  ;; --- maf-reset-settings: modes only, session kept ---

  ;; Back to the saved modes, then knock them off again with a stack,
  ;; a selection, and undo history in place.
  (call-interactively 'maf-reset)
  (maf-push "6 x + 12")
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 2) (search-forward "x"))
  (call-interactively 'calc-select-here)
  (progn (setq calc-symbolic-mode nil calc-prefer-frac nil) nil)
  (progn (calc-cursor-stack-index 2) (search-forward "+") (backward-char 1))

  ;; The modes come back; the stack, the selection, undo/redo, and point
  ;; all stay. Undo is the one `calc-reset' clears regardless of its
  ;; argument — with the stack kept, the list still describes it, so the
  ;; command puts it back.
  (let ((undo calc-undo-list) (line (line-number-at-pos)) (col (current-column)))
    (call-interactively 'maf-reset-settings)
    (cl-assert (eq calc-undo-list undo))
    (cl-assert (= (line-number-at-pos) line))
    (cl-assert (= (current-column) col)))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "6 x + 12"))
  (cl-assert (maf--sel-any-p))
  (cl-assert (eq calc-symbolic-mode t))
  (cl-assert (eq calc-prefer-frac t))
  (cl-assert (bound-and-true-p maf-mode))

  ;; Its own prefix form: defaults, stack still kept.
  (let ((current-prefix-arg '(4)))
    (call-interactively 'maf-reset-settings))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (null calc-symbolic-mode))
  (cl-assert (null calc-prefer-frac))

  ;; --- The trail helper on its own ---

  ;; No trail buffer at all is a no-op, not an error.
  (progn
    (let ((kill-buffer-query-functions nil))
      (when (get-buffer "*Calc Trail*") (kill-buffer "*Calc Trail*")))
    (maf--reset-clear-trail)
    (cl-assert (null (get-buffer "*Calc Trail*")))
    :no-trail-ok)

  ;; A missing settings file is a no-op too: `load' would signal, so the
  ;; helper checks first and reports that it read nothing.
  (let ((calc-settings-file "/nonexistent/maf/calc.el"))
    (cl-assert (null (maf--reset-load-settings)))
    :missing-file-ok)

  ;; Restore the real settings file and put calc back on its saved modes.
  ;; `calc-settings-file' is global: a wrong value written here outlives
  ;; the test and every later reset in the instance inherits it. An
  ;; `unset' slot means the capturing step never ran in this Emacs, and
  ;; restoring from it is how the instance loses its settings file
  ;; entirely — fail before the write instead.
  (progn
    (cl-assert (not (eq maf-test--settings-orig 'unset)))
    (setq calc-settings-file maf-test--settings-orig)
    (delete-file maf-test--settings-file)
    (makunbound 'var-maf-test-canary)
    (call-interactively 'maf-reset)
    ;; `equal' against the slot cannot carry this alone: with an empty
    ;; slot it compares nil to nil and passes, certifying the damage.
    ;; The assertion above, that the slot was captured at all, is what
    ;; makes this one mean something. Existence is deliberately not
    ;; checked: the file may legitimately not be written yet.
    (cl-assert (equal calc-settings-file maf-test--settings-orig))
    :restored)

  ;; --- a settings file that signals costs the settings, not the session ---

  ;; `calc-reset' nils every buffer-local in `calc-local-var-list', then
  ;; evaluates the settings file's mode block, and only then re-runs
  ;; `calc-mode' to rebuild them. A form that signals in between skips
  ;; the rebuild and leaves the buffer with no stack top and no display
  ;; precision — unable to render its own stack, let alone take the next
  ;; command. The error still reaches the user; what must not happen is
  ;; losing the session with it.
  (maf-push "a + b")
  (progn
    (setq maf--test-bad-settings (make-temp-file "maf-bad-settings" nil ".el"))
    (with-temp-file maf--test-bad-settings
      (insert ";;; Mode settings stored by Calc\n"
              "(setq calc-float-format '(float 0))\n"
              "(car 'not-a-cons)\n"
              ";;; End of mode settings\n")))
  (cl-assert (eq :signaled
                 (let ((calc-settings-file maf--test-bad-settings))
                   (condition-case nil
                       (progn (maf--reset-calc 1) :no-error)
                     (error :signaled)))))
  ;; The buffer is coherent again: locals rebuilt, maf-mode back on.
  (cl-assert calc-stack-top)
  (cl-assert (bound-and-true-p maf-mode))
  ;; And the stack rode it out — `calc-reset' shields it behind a let, so
  ;; the abort never reached it — and still renders.
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b"))
  (progn (delete-file maf--test-bad-settings)
         (setq maf--test-bad-settings nil))
  (calc-pop (calc-stack-size)))
