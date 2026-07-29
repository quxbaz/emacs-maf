;; A selected entry is not displayed in full — calc replaces every
;; unselected character with a dot — so there is no text for maf-edit to
;; hand over. Every entry gesture refuses while a selection is active,
;; and says which key clears it.

(maf-step
  (maf-push "a b + c")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'calc-select-here)
  (cl-assert (maf--sel-any-p))
  ;; What the entry looks like on screen: the mask, not the formula.
  (cl-assert (string-match-p "\\." (buffer-substring-no-properties
                                    (point-min) (line-end-position))))

  ;; Every gesture refuses: the toggle and all three quick-adds, plus
  ;; the mode itself, so `M-x maf-edit-mode' cannot slip past either.
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit) t)))
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit-add-entry) t)))
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit-add-entry-below) t)))
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit-add-vector) t)))
  (cl-assert (not (ignore-errors (maf-edit-mode 1) t)))
  (cl-assert (not maf-edit-mode))

  ;; Nothing moved: the selection stands and the stack is as it was.
  ;; ('full, since a plain `calc-top' hands back the selection rather
  ;; than the entry while one is active.)
  (cl-assert (maf--sel-any-p))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(+ (* (var a var-a) (var b var-b))
                                           (var c var-c))))

  ;; Clear the selection (RET's dispatcher) and editing works as usual,
  ;; on the whole formula rather than the mask.
  (call-interactively 'maf-dup-or-clear-selections)
  (cl-assert (not (maf--sel-any-p)))
  (call-interactively 'maf-edit)
  (cl-assert maf-edit-mode)
  (progn (goto-char (point-min)) (end-of-line) nil)
  (progn (execute-kbd-macro " + 1") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (not maf-edit-mode))
  (cl-assert (equal (calc-top 1 'full) '(+ (+ (* (var a var-a) (var b var-b))
                                              (var c var-c))
                                           1)))

  ;; A selection elsewhere counts too — the gesture that would only add
  ;; a fresh entry is refused as well, deliberately: no editing session
  ;; opens while any entry is drilled into.
  (maf-push "x + y")
  (progn (calc-cursor-stack-index 2) (search-forward "a") (backward-char 1))
  (call-interactively 'calc-select-here)
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit-add-entry) t)))
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 2))

  ;; Turning selections off (`calc-enable-selections') stops commands
  ;; from honoring them, but calc still masks the entry — and drops the
  ;; * marker that hinted at it — so the guard keys on the display
  ;; rather than on whether the selection has any effect.
  (progn (setq calc-use-selections nil) (calc-refresh) nil)
  (cl-assert (not (maf--sel-any-p)))
  (cl-assert (maf--sel-any-shown-p))
  (cl-assert (not (ignore-errors (call-interactively 'maf-edit) t)))
  (cl-assert (not maf-edit-mode))
  (progn (setq calc-use-selections t) (calc-refresh) nil)

  (call-interactively 'maf-clear-selections)

  (calc-pop (calc-stack-size)))
