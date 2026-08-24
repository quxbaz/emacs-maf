;; `maf-forward-operand' (S-SPC): every sub-formula of an entry is one
;; stop, the whole entry among them, each at the first glyph it renders
;; itself — the place resolve names it. The contract checked here: the
;; stops come in display order and each landing resolves to the
;; sub-formula the motion advertised (`maf-test--part-at-point' reads
;; that back); the walk crosses entries, a numeric prefix counts stops
;; (backward when negative), the ends of the stack signal, and an entry
;; with no flat rendering (a Big-language fraction) offers no stops and
;; is crossed whole. A step passes when it raises no error.

(defun maf-test--flat (expr)
  "EXPR in flat notation, with the selection machinery's encasing gone."
  (math-format-flat-expr (maf--strip-encasing expr) 0))

(defun maf-test--part-at-point ()
  "The sub-formula point names, in flat notation."
  (let ((m (calc-locate-cursor-element (point))))
    (calc-prepare-selection m)
    (maf-test--flat (calc-find-selected-part))))

(maf-step
  ;; Two entries, so the walk has a margin to cross between them.
  (calc-wrapper (maf-push "1 + sqrt(x y)") (maf-push "6 x + 12"))

  ;; The full walk of the top entry, driven by the real key so the
  ;; binding is exercised and not just the command. The second stop is
  ;; the whole entry at its own operator; the juxtaposed product's stop
  ;; is the space it multiplies with.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "1 \\+ sqrt"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "\\+ sqrt"))
  (cl-assert (string= (maf-test--part-at-point) "1 + sqrt(x * y)"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "sqrt(x y)$"))
  (cl-assert (string= (maf-test--part-at-point) "sqrt(x * y)"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "x y)$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " y)$"))
  (cl-assert (string= (maf-test--part-at-point) "x * y"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "y)$"))

  ;; Crossing into the entry below steps over the line-number margin:
  ;; the level number is no operand.
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "6 x \\+ 12"))
  (cl-assert (looking-back "1:  " (line-beginning-position)))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " x \\+ 12"))
  (cl-assert (string= (maf-test--part-at-point) "6 * x"))
  (let ((current-prefix-arg 3)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at "12$"))

  ;; Past the last operand the home line holds nothing, and the motion
  ;; signals rather than moving.
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-operand) 'moved)
                   (user-error 'signalled))))

  ;; Backward retraces the same stops, crosses back up into the entry
  ;; above, and signals in turn before the stack's first stop.
  (let ((current-prefix-arg -1)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at "\\+ 12"))
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (let ((current-prefix-arg -4)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at "y)$"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (let ((current-prefix-arg -5)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at "1 \\+ sqrt"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (let ((current-prefix-arg -1))
                              (call-interactively 'maf-forward-operand))
                            'moved)
                   (user-error 'signalled))))
  (calc-pop (calc-stack-size))

  ;; A delimiter is a compound operand's own first glyph: the
  ;; parenthesized sum is named at its paren, and the whole product —
  ;; whose glyph is the juxtaposition space between the groups — right
  ;; after the first group closes.
  (calc-wrapper (maf-push "(a + b) (2 c - d)"))
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "(a \\+ b)"))
  (cl-assert (string= (maf-test--part-at-point) "a + b"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "a \\+ b)"))
  (let ((current-prefix-arg 2)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at " (2 c - d)$"))
  (cl-assert (string= (maf-test--part-at-point) "(a + b) * (2 * c - d)"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "(2 c - d)$"))
  (cl-assert (string= (maf-test--part-at-point) "2 * c - d"))
  (calc-pop (calc-stack-size))

  ;; An atom entry is one stop — the whole entry is its own operand —
  ;; and a Big-language fraction has no flat rendering, so it offers no
  ;; stops and the walk crosses it whole into the entry below.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "1 / (x^2 - 1)")
                (maf-push "42"))
  (call-interactively 'maf-toggle-big-language)
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "6 x \\+ 12"))
  (let ((current-prefix-arg 5)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at "42$"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (cl-assert (string= (maf-test--part-at-point) "42"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-operand) 'moved)
                   (user-error 'signalled))))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop (calc-stack-size)))
