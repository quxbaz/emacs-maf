;; `v :' reads an ordering relation as the interval it bounds its
;; subject to, beside the set reading it has always had
;; (`mafcmd-vspan'). A step passes when it raises no error.
;;
;; The contract: one relation spans to the ray beyond its bound, the
;; infinite end spelled open the way maf spells one everywhere else;
;; the bound may lead, and may be a name rather than a number, the
;; subject being the side that carries a variable; two relations joined
;; by && span to the interval between them, on the subject they share.
;; A set still spans as calc spans it, and anything bounding nothing —
;; an =, two subjects, one side bounded twice — is left as it stands.

(maf-step
  ;; The key, no longer a mafcmd table row's but declared beside the
  ;; negation's in src/bindings.el, for the same reason.
  (cl-assert (eq (key-binding (kbd "v :")) 'mafcmd-vspan))
  (cl-assert (null (assq 'mafcmd-vspan maf-cmds--table)))

  ;; The set reading, unchanged: the smallest interval covering it.
  (maf-push "[1, 5, 3]")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1 .. 5]"))
  (calc-pop (calc-stack-size))

  ;; The motivating case, and its three siblings: a closed bound stays
  ;; closed, an open one open, and the infinity is spelled open — no
  ;; set closes at an infinity.
  (maf-push "x >= -1")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1 .. inf)"))
  (calc-pop (calc-stack-size))

  (maf-push "x > -1")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-1 .. inf)"))
  (calc-pop (calc-stack-size))

  (maf-push "x <= 3")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-inf .. 3]"))
  (calc-pop (calc-stack-size))

  (maf-push "x < 3")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-inf .. 3)"))
  (calc-pop (calc-stack-size))

  ;; The bound may lead: the same range, written the other way round.
  (maf-push "-1 <= x")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1 .. inf)"))
  (calc-pop (calc-stack-size))

  ;; A bound need not be a number. Calc's own constants are not
  ;; variables, so -pi leads as the bound it looks like rather than
  ;; being taken for the subject.
  (maf-push "-pi <= x")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-pi .. inf)"))
  (calc-pop (calc-stack-size))

  (maf-push "sqrt(2) < x")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(sqrt(2) .. inf)"))
  (calc-pop (calc-stack-size))

  ;; A variable on both sides: the relation is taken as written, x
  ;; bounded above by y.
  (maf-push "x <= y")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-inf .. y]"))
  (calc-pop (calc-stack-size))

  ;; Two relations joined by && span the interval between them.
  (maf-push "-5 < x && x < 5")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-5 .. 5)"))
  (calc-pop (calc-stack-size))

  ;; Each end keeps the openness its own half gave it.
  (maf-push "x > -1 && x <= 3")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-1 .. 3]"))
  (calc-pop (calc-stack-size))

  ;; Either half may be written backwards.
  (maf-push "-1 <= x && 3 >= x")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1 .. 3]"))
  (calc-pop (calc-stack-size))

  ;; A band whose bounds are names: no half can tell subject from bound
  ;; alone, and the x they share is what settles it.
  (maf-push "a <= x && x <= b")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[a .. b]"))
  (calc-pop (calc-stack-size))

  ;; The inverse of splitting an absolute value: what `a k' produces,
  ;; `v :' reads back as the interval it came from.
  (maf-push "abs(x) < 5")
  (call-interactively 'mafcmd-abs-ineq)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "-5 < x && x < 5"))
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(-5 .. 5)"))
  (calc-pop (calc-stack-size))

  ;; Bounding nothing: an = says which value, not which range, and a
  ;; conjunction naming two subjects or one side twice spans neither.
  ;; All three commit as calc leaves them — an inert vspan call.
  (maf-push "x = 3")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "vspan(x = 3)"))
  (calc-pop (calc-stack-size))

  (maf-push "x > 1 && y < 5")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "vspan(x > 1 && y < 5)"))
  (calc-pop (calc-stack-size))

  (maf-push "x > 1 && x > 5")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "vspan(x > 1 && x > 5)"))
  (calc-pop (calc-stack-size))

  ;; Two facts about unrelated names share only their constants, and a
  ;; constant is not what the pair was written to bound.
  (maf-push "x > 0 && y < 0")
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "vspan(x > 0 && y < 0)"))
  (calc-pop (calc-stack-size))

  ;; The relation is the subject, not a pair of sides to run over: with
  ;; :map -1 the whole entry spans once, rather than each side alone.
  (maf-push "x >= -1")
  (progn (goto-char (point-min)) (search-forward ">=") (backward-char 2))
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[-1 .. inf)"))
  (calc-pop (calc-stack-size))

  ;; And it reads a relation standing inside an entry, not only one
  ;; that is the whole of it.
  (maf-push "[x >= -1, 2]")
  (progn (goto-char (point-min)) (search-forward ">=") (backward-char 2))
  (call-interactively 'mafcmd-vspan)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[[-1 .. inf), 2]"))
  (calc-pop (calc-stack-size))

  (cl-assert (= (calc-stack-size) 0)))
