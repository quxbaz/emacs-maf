;; mafcmd-map-flag (M): a fancy prefix like calc's K or I — the next
;; contextual command, unary or binary, maps over its subject: one run
;; per vector element or equation side. Where $ maps a formula you type
;; and # maps one from the stack, M maps a command. The prefix is
;; driven with real keys where the flow through calc's fancy-prefix
;; machinery is itself the thing under test.

(maf-step
  ;; M N at home: negate runs once per element. Balanced negation of a
  ;; bare slot doubles the sign (x => --x, see `mafcmd-negate'), so the
  ;; doubled signs are the proof each element took its own run.
  (maf-push "[x, y]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M N"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[--x, --y]"))
  (cl-assert (null maf-map-flag))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A binary command shares its argument across the runs. | consumes a
  ;; vector whole by design (:map -1: a vector is one operand to
  ;; concatenation) — the flag is the explicit request to spread it.
  (maf-push "[a, b]")
  (maf-push "[1, 2]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M |"))
  ;; Compared structurally: a matrix's own rendering is multi-line.
  (cl-assert (equal (maf--strip-encasing (calc-top 1 'full))
                    '(vec (vec (var a var-a) 1 2)
                          (vec (var b var-b) 1 2))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; A relation subject maps side by side even for a command that
  ;; normally consumes it whole, and a relation argument pairs its
  ;; sides with the subject's rather than riding along whole.
  (maf-push "a = b")
  (maf-push "c = d")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M |"))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[a, c] = [b, d]"))
  (calc-pop (calc-stack-size))

  ;; A matrix maps over its individual elements, not its rows — the
  ;; same reading M gives one. The flag is set directly here, as
  ;; map.el sets calc-inverse-flag: the prefix flow is already covered.
  (maf-push "[[(x + 1)^2, (x - 1)^2], [(a + b)^2, 4]]")
  (goto-char (point-max))
  (progn (setq maf-map-flag t)
         (call-interactively 'mafcmd-expand))
  (cl-assert (equal (math-format-value
                     (maf--strip-encasing (calc-top 1 'full)))
                    (math-format-value
                     (math-read-expr
                      "[[x^2 + 2 x + 1, x^2 - 2 x + 1], [a^2 + 2 b a + b^2, 4]]"))))
  (calc-pop (calc-stack-size))

  ;; A vector sub-formula at point maps in place, the entry around it
  ;; untouched.
  (maf-push "f([(x + 1)^2, (y - 1)^2]) + z")
  (progn (goto-char (point-min)) (search-forward "[") (backward-char 1))
  (progn (setq maf-map-flag t)
         (call-interactively 'mafcmd-expand))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "f([x^2 + 2 x + 1, y^2 - 2 y + 1]) + z"))
  (calc-pop (calc-stack-size))

  ;; An explicitly selected relation converts too: a selection holds
  ;; its node whole as a deliberate gesture, but the flag is just as
  ;; deliberate a request to map it per side.
  (maf-push "(x + 1)^2 = (y - 1)^2")
  (progn (calc-cursor-stack-index 1)
         (search-forward " = ") (backward-char 2)
         (execute-kbd-macro (kbd "j s"))
         (setq maf-map-flag t)
         (call-interactively 'mafcmd-expand))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x^2 + 2 x + 1 = y^2 - 2 y + 1"))
  (calc-pop (calc-stack-size))

  ;; The flag survives a command's own prompt: the keystrokes typed in
  ;; the minibuffer are not the command it waits for. M i solves each
  ;; relation of the vector separately — without the flag calc reads
  ;; the vector as a system and returns a single solution.
  (maf-push "[x + a = 2, x - b = 3]")
  (progn (goto-char (point-max))
         (execute-kbd-macro (kbd "M i x RET")))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[x = -a + 2, x = b + 3]"))
  (cl-assert (null maf-map-flag))
  (calc-pop (calc-stack-size))

  ;; A command the flag forces past :map -1 splits only an =: an
  ;; ordered relation refuses — a command, unlike $'s formula, cannot
  ;; say which way it bends the direction — and the stack stands.
  (maf-push "a < b")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "only over ="
              (condition-case err
                  (progn (setq maf-map-flag t)
                         (call-interactively 'mafcmd-simplify)
                         "")
                (user-error (error-message-string err)))))
  (cl-assert (null maf-map-flag))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "a < b"))
  (calc-pop (calc-stack-size))

  ;; A != refuses with its own message: $ and # are no way out for it —
  ;; they refuse a != too, I or not, for the same one-to-one reason.
  ;; Commands without :map -1 are untouched either way — they map
  ;; relations with or without the flag, as they always have.
  (maf-push "a != b")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "one-to-one"
              (condition-case err
                  (progn (setq maf-map-flag t)
                         (call-interactively 'mafcmd-simplify)
                         "")
                (user-error (error-message-string err)))))
  (calc-pop (calc-stack-size))

  ;; C-g at the prompt abandons the gesture: the flag dies with the
  ;; command it was set for rather than lying in wait, and the stack
  ;; stands.
  (maf-push "[x + a = 2, x - b = 3]")
  (progn (goto-char (point-max))
         (condition-case nil (execute-kbd-macro (kbd "M i C-g")) (quit nil))
         (cl-assert (null maf-map-flag))
         (cl-assert (null (memq #'maf--map-flag-expire post-command-hook))))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "[x + a = 2, x - b = 3]"))
  (calc-pop (calc-stack-size))

  ;; A subject with no elements refuses; the flag is still consumed and
  ;; the stack stands.
  (maf-push "x + 1")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "Nothing to map over"
              (condition-case err
                  (progn (setq maf-map-flag t)
                         (call-interactively 'mafcmd-expand)
                         "")
                (user-error (error-message-string err)))))
  (cl-assert (null maf-map-flag))
  (cl-assert (string= (math-format-value
                       (maf--strip-encasing (calc-top 1 'full)))
                      "x + 1"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The flag-mechanics gestures each live in a single form: stepping
  ;; through the cockpit presses keys of its own between forms, and a
  ;; pending prefix must not be left exposed to them.

  ;; The flag lasts for exactly one command: one that has no reading of
  ;; it drops it rather than leaving it lying in wait.
  (progn (execute-kbd-macro (kbd "M C-f"))
         (cl-assert (null maf-map-flag))
         (cl-assert (null (memq #'maf--map-flag-expire post-command-hook))))

  ;; A second M cancels the first.
  (progn (execute-kbd-macro (kbd "M M"))
         (cl-assert (null maf-map-flag)))

  ;; It chains with calc's own prefixes: after M I both are pending,
  ;; and a command that reads neither clears both.
  (progn (execute-kbd-macro (kbd "M I"))
         (cl-assert (and maf-map-flag calc-inverse-flag))
         (execute-kbd-macro (kbd "C-f"))
         (cl-assert (null maf-map-flag))
         (cl-assert (null calc-inverse-flag))))
