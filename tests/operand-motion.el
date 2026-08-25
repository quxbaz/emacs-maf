;; `maf-forward-operand' (M-e) and `maf-backward-operand' (M-a),
;; its reverse over the same stops: every operation of an entry is one
;; stop, the whole entry among them, each at the first glyph it renders
;; itself — the place resolve names it. The nouns are not stops: a
;; number or a variable belongs to `maf-forward-noun' (M-f), so the two
;; motions divide the entry between them. The contract checked here: the
;; stops come in display order, skipping the atoms, and each landing
;; resolves to the sub-formula the motion advertised
;; (`maf-test--part-at-point' reads that back); the walk stays inside
;; the entry it starts in, signalling at either edge rather than
;; crossing the margin, a numeric prefix counts stops (the other way
;; when negative), and an entry offering no stop of its own — a bare
;; atom, a Big-language fraction with no flat rendering — signals
;; wherever point sits in it. A step passes when it raises no error.

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
  ;; binding is exercised and not just the command. The first stop is
  ;; the whole entry at its own operator — the 1 it starts on is a noun,
  ;; not a stop — and the juxtaposed product's stop is the space it
  ;; multiplies with.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "1 \\+ sqrt"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at "\\+ sqrt"))
  (cl-assert (string= (maf-test--part-at-point) "1 + sqrt(x * y)"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at "sqrt(x y)$"))
  (cl-assert (string= (maf-test--part-at-point) "sqrt(x * y)"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at " y)$"))
  (cl-assert (string= (maf-test--part-at-point) "x * y"))

  ;; The entry's last stop is where the walk stops asking: the entry
  ;; below is another line's business, and the motion signals on the
  ;; margin rather than crossing it. Point stays where it was.
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-operand) 'moved)
                   (user-error 'signalled))))
  (cl-assert (looking-at " y)$"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))

  ;; Backward retraces the same stops on its own key, and signals in
  ;; turn at the entry's first stop rather than climbing to the entry
  ;; above.
  (progn (execute-kbd-macro (kbd "M-a")) nil)
  (cl-assert (looking-at "sqrt(x y)$"))
  (let ((current-prefix-arg 1)) (call-interactively 'maf-backward-operand))
  (cl-assert (looking-at "\\+ sqrt"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-backward-operand) 'moved)
                   (user-error 'signalled))))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))

  ;; A negative prefix turns either motion into the other, so the two
  ;; retrace each other from either key — within the one entry, as
  ;; every step here is.
  (let ((current-prefix-arg -1)) (call-interactively 'maf-backward-operand))
  (cl-assert (looking-at "sqrt(x y)$"))
  (let ((current-prefix-arg -1)) (call-interactively 'maf-forward-operand))
  (cl-assert (looking-at "\\+ sqrt"))

  ;; The entry below has its own stops, walked the same way once point
  ;; is in it: the level number is no operand, and the 6 behind the
  ;; margin is the noun motion's.
  (progn (calc-cursor-stack-index 1) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "6 x \\+ 12"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at " x \\+ 12"))
  (cl-assert (looking-back "1:  6" (line-beginning-position)))
  (cl-assert (string= (maf-test--part-at-point) "6 * x"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at "\\+ 12$"))
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (calc-pop (calc-stack-size))

  ;; A delimiter is a compound operand's own first glyph: the
  ;; parenthesized sum is named at its paren, and the whole product —
  ;; whose glyph is the juxtaposition space between the groups — right
  ;; after the first group closes.
  (calc-wrapper (maf-push "(a + b) (2 c - d)"))
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "(a \\+ b)"))
  (cl-assert (string= (maf-test--part-at-point) "a + b"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at " (2 c - d)$"))
  (cl-assert (string= (maf-test--part-at-point) "(a + b) * (2 * c - d)"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at "(2 c - d)$"))
  (cl-assert (string= (maf-test--part-at-point) "2 * c - d"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at " c - d)$"))
  (cl-assert (string= (maf-test--part-at-point) "2 * c"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-operand) 'moved)
                   (user-error 'signalled))))
  (calc-pop (calc-stack-size))

  ;; An entry with no operation of its own has nowhere to step, and
  ;; says so where point stands rather than handing the walk to a
  ;; neighbour: a bare number is all noun, and a Big-language fraction
  ;; has no flat rendering to read stops off.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "42")
                (maf-push "1 / (x^2 - 1)") (maf-push "2 z"))
  (call-interactively 'maf-toggle-big-language)
  (progn (calc-cursor-stack-index 3) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "42$"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-operand) 'moved)
                   (user-error 'signalled))))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-backward-operand) 'moved)
                   (user-error 'signalled))))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))

  ;; The fraction is drawn over several lines, so it offers no stops
  ;; either — and the entries around it are none of its business.
  (progn (calc-cursor-stack-index 2) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-operand) 'moved)
                   (user-error 'signalled))))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))

  ;; An entry that is flat in Big language walks its own stops there
  ;; as it does anywhere else.
  (progn (calc-cursor-stack-index 4) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (looking-at "6 x \\+ 12"))
  (progn (execute-kbd-macro (kbd "M-e")) nil)
  (cl-assert (looking-at " x \\+ 12"))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop (calc-stack-size)))
