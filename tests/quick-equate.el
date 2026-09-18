;; Step test for maf-quick-equate: read one character and equate the
;; entry at point with it, the character as the right side. Run in a
;; live Emacs (see tests/README.md).
(maf-step
  ;; = reaches the command in the ergo layout; e keeps `mafcmd-equal-to'.
  (cl-assert (eq (key-binding (kbd "=")) 'maf-quick-equate))
  (cl-assert (eq (key-binding (kbd "e")) 'mafcmd-equal-to))

  ;; --- The example: a letter, point mid-entry ---

  ;; The whole entry is the left side, not the sub-formula under point;
  ;; the letter is the right; point lands at the end of the equation.
  (maf-push "a + b")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "c"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b = c"))
  (cl-assert (eolp))
  (cl-assert (= (line-number-at-pos) 1))
  (calc-pop (calc-stack-size))

  ;; --- A digit is the number it names ---

  (maf-push "x + 1")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "0"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (equal (calc-top 1 'full) '(calcFunc-eq (+ (var x var-x) 1) 0)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1 = 0"))
  (calc-pop (calc-stack-size))

  ;; --- At home the top entry is the subject; point stays home ---

  (maf-push "u")
  (maf-push "v")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "w"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "v = w"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "u"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; --- A deeper stack: the entry at point, nothing consumed ---

  (maf-push "p")
  (maf-push "q")
  (progn (calc-cursor-stack-index 2) (end-of-line))
  (execute-kbd-macro (kbd "= r"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "p = r"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "q"))
  (cl-assert (= (line-number-at-pos) 1))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; --- Sides are never reordered: the typed side is the right side ---

  ;; Where `mafcmd-equal-to' would lead with the variable (x = 5), the
  ;; user typed x as the right side and gets it there.
  (maf-push "5")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "x"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = x"))
  (calc-pop (calc-stack-size))

  ;; --- Structural: nothing simplifies or evaluates ---

  (maf-push "3")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "3"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (equal (calc-top 1 'full) '(calcFunc-eq 3 3)))
  (calc-pop (calc-stack-size))

  ;; An unsimplified subject survives intact.
  (let ((calc-simplify-mode 'none))
    (calc-push '(+ (+ (var x var-x) 1) 1)))
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "y"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (equal (calc-top 1 'full)
                    '(calcFunc-eq (+ (+ (var x var-x) 1) 1) (var y var-y))))
  (calc-pop (calc-stack-size))

  ;; --- Whole-entry scope: a relation subject stays whole, and a
  ;; selection does not narrow it ---

  (maf-push "x = y")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "z"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (equal (calc-top 1 'full)
                    '(calcFunc-eq (calcFunc-eq (var x var-x) (var y var-y))
                                  (var z var-z))))
  (calc-pop (calc-stack-size))

  (maf-push "a + b")
  (progn (goto-char (point-min)) (search-forward "a") (backward-char 1))
  (call-interactively 'calc-select-here)
  (progn (setq unread-command-events (listify-key-sequence "c"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b = c"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; --- Inverse flag builds != and is consumed ---

  (maf-push "a + b")
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "c"))
         (let ((calc-inverse-flag t)) (call-interactively 'maf-quick-equate)))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + b != c"))
  (cl-assert (eolp))
  (calc-pop (calc-stack-size))

  ;; --- Anything but a letter or digit aborts, stack untouched ---

  (maf-push "y")
  (progn (goto-char (point-min)) (end-of-line))
  (cl-assert (condition-case nil
                 (progn (setq unread-command-events (listify-key-sequence "+"))
                        (call-interactively 'maf-quick-equate)
                        nil)
               (user-error t)))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (equal (calc-top 1 'full) '(var y var-y)))
  (calc-pop (calc-stack-size))

  ;; --- Typed after a number, the number is the subject ---

  ;; The digit entry ends on = and its push is what gets equated,
  ;; wherever point was: 5 = y on x's line leaves x alone. Point lands
  ;; at the end of the equation; one undo reverts the push too.
  (maf-push "x")
  (progn (goto-char (point-min)) (end-of-line))
  (execute-kbd-macro (kbd "5 = y"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = y"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x"))
  (cl-assert (= (line-number-at-pos) 2))
  (cl-assert (eolp))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x"))
  (calc-pop (calc-stack-size))

  ;; At home the same, and point stays home.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "5 = y"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "5 = y"))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  ;; --- One undo reverts the equation ---

  (maf-push "m")
  (progn (goto-char (point-min)) (end-of-line))
  (progn (setq unread-command-events (listify-key-sequence "n"))
         (call-interactively 'maf-quick-equate))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "m = n"))
  (maf-undo 1)
  (cl-assert (equal (calc-top 1 'full) '(var m var-m)))
  (calc-pop (calc-stack-size)))
