;; maf-reset-settings: modes and stored variables go back to what the
;; settings file holds; the stack, the undo history, point, and maf-mode
;; come through untouched.
;;
;; The test writes a settings file of its own and points
;; `calc-settings-file' at it, so nothing here depends on the user's
;; ~/.emacs.d/calc.el. The last forms put the real one back.
;;
;; Each run gets a fresh temp file, and the run kills the buffer calc
;; leaves visiting it: `calc-mode-var-list-restore-saved-values' reads
;; the settings file with `find-file-noselect', so a buffer on a path
;; whose contents a later run rewrites would make calc prompt
;; ("changed on disk, read from disk?") in the middle of the reset.

(defvar maf-test--settings-file nil
  "Throwaway `calc-settings-file' for this run, or nil before it is made.")

(defvar maf-test--settings-real nil
  "The real `calc-settings-file', saved while the throwaway is in use.")

(defun maf-test--forget-settings-file ()
  "Delete the throwaway settings file and any buffer visiting it."
  (when maf-test--settings-file
    (when-let ((buf (find-buffer-visiting maf-test--settings-file)))
      (let ((kill-buffer-query-functions nil))
        (kill-buffer buf)))
    (delete-file maf-test--settings-file)
    (setq maf-test--settings-file nil)))

(defun maf-test--settings (&rest lines)
  "Make a throwaway `calc-settings-file' holding LINES; return its name."
  (maf-test--forget-settings-file)
  (setq maf-test--settings-file (make-temp-file "maf-reset-settings-" nil ".el"))
  (with-temp-file maf-test--settings-file
    (apply #'insert lines))
  (setq calc-settings-file maf-test--settings-file))

(maf-step
  ;; A settings file with both halves that matter: the mode block
  ;; calc-reset itself restores, and a stored variable outside it that
  ;; only the file reload can bring back.
  (progn (setq maf-test--settings-real calc-settings-file)
         (maf-test--settings ";;; Mode settings stored by Calc\n"
                             "(setq calc-prefer-frac t)\n"
                             ";;; End of mode settings\n"
                             "(setq var-maftest '(var q var-q))\n"))

  ;; A stack to preserve, its bottom entry wide enough to put point
  ;; inside.
  (maf-push "6 x + 12")
  (maf-push "2")
  (cl-assert (= (calc-stack-size) 2))

  ;; Drift the session away from the saved state in four ways: a mode
  ;; the file stores, a mode it says nothing about, the display
  ;; language, and the stored variable.
  (calc-wrapper (calc-change-mode 'calc-prefer-frac nil t))
  (calc-wrapper (calc-change-mode 'calc-angle-mode 'rad t))
  (calc-set-language 'tex)
  (setq var-maftest '(var bogus var-bogus))
  (cl-assert (eq calc-language 'tex))

  ;; One more push, after the mode changes: those record undo entries
  ;; of their own, so this has to be the last undoable action for the
  ;; undo check at the end to be about the stack. Through `calc-wrapper'
  ;; rather than `maf-push', which does not wrap — its `calc-push' lands
  ;; in whatever undo group is open, so the pushes above are all one
  ;; group and undoing it would take the whole stack.
  (calc-wrapper (calc-push 99))
  (cl-assert (= (calc-stack-size) 3))

  ;; Point inside the bottom entry, away from home.
  (progn (calc-cursor-stack-index 3) (forward-char 3) nil)
  (cl-assert (= (calc-locate-cursor-element (point)) 3))

  (call-interactively 'maf-reset-settings)

  ;; The file's mode block wins over the session change.
  (cl-assert (eq calc-prefer-frac t))
  ;; A mode the file is silent about returns to its default.
  (cl-assert (eq calc-angle-mode 'deg))
  ;; The display language goes back to normal.
  (cl-assert (null calc-language))
  ;; The rest of the file runs too, so the stored variable is back —
  ;; this is the part plain `calc-reset' does not do.
  (cl-assert (equal var-maftest '(var q var-q)))

  ;; The stack came through unchanged...
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "99"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "6 x + 12"))
  ;; ...and so did point, still on the bottom entry rather than home.
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  ;; maf-mode survives calc re-running calc-mode underneath.
  (cl-assert maf-mode)

  ;; The undo history survives too: one undo drops the entry pushed
  ;; before the reset, which plain `calc-reset' would have made
  ;; impossible.
  (call-interactively 'maf-undo)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "2"))
  (call-interactively 'maf-redo)
  (cl-assert (= (calc-stack-size) 3))

  ;; A settings file that does not exist is not an error: the modes
  ;; still go back to their defaults, there is simply nothing further
  ;; to reload.
  (setq calc-settings-file (expand-file-name "maf-no-such-settings-file.el"
                                             temporary-file-directory))
  (calc-wrapper (calc-change-mode 'calc-angle-mode 'rad t))
  (call-interactively 'maf-reset-settings)
  (cl-assert (eq calc-angle-mode 'deg))
  (cl-assert (= (calc-stack-size) 3))

  ;; A settings file that blows up part way through does reach the
  ;; user as an error — but not by wrecking the buffer. calc-reset
  ;; empties calc's buffer-local state before refilling it, so an abort
  ;; in the middle would otherwise leave a calc buffer with no state at
  ;; all; `maf-reset-settings' rebuilds it.
  (maf-test--settings ";;; Mode settings stored by Calc\n"
                      "(setq calc-angle-mode 'rad)\n"
                      "(error \"maf test: deliberately broken settings file\")\n"
                      ";;; End of mode settings\n")
  (cl-assert (eq 'signaled
                 (condition-case nil
                     (call-interactively 'maf-reset-settings)
                   (error 'signaled))))
  (cl-assert (integerp calc-stack-top))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "99"))
  (cl-assert maf-mode)

  ;; Put the real settings file back and restore the session from it,
  ;; so the test leaves calc as it found it.
  (progn (maf-test--forget-settings-file)
         (setq calc-settings-file maf-test--settings-real)
         (call-interactively 'maf-reset-settings)
         nil)
  (cl-assert (equal calc-settings-file maf-test--settings-real)))
