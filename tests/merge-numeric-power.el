;; maf-merge (j M) on an integer factor beside a power of its base.
;; Calc's own MergeRules read only the shape of a power, so 16 2^x is
;; nothing to them, and 2^4 2^x is the same case — calc folds 2^4 to
;; 16 on entry, and the rewriter normalizes its input the same way.
;; maf appends rules that read the number (`maf--merge-rule-additions').

(defun mnp-at (needle &optional back)
  "Put point on NEEDLE in the stack buffer, BACK chars before its end."
  (goto-char (point-min))
  (search-forward needle)
  (backward-char (or back 1)))

(defun mnp-top ()
  (math-format-value (calc-top 1 'full)))

(maf-step
  ;; The two spellings of the report, from home: the folded product,
  ;; and the unsimplified one that folds on the way in.
  (maf-push "16 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (maf--at-home-p))
  (calc-pop (calc-stack-size))

  (maf-push "2^4 2^x")
  (cl-assert (equal (calc-top 1 'full) '(* (^ 2 4) (^ 2 (var x var-x)))))
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (calc-pop (calc-stack-size))

  ;; Either order of the factors.
  (maf-push "2^x 16")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (calc-pop (calc-stack-size))

  ;; On the entry, from either part: the rules are given with the
  ;; marker on the number and on the power, so a selection on either
  ;; fires. Point follows the marked result into the entry.
  (maf-push "16 2^x")
  (mnp-at "16" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (cl-assert (null (calc-top 1 'sel)))
  (cl-assert (not (maf--at-home-p)))
  (calc-pop (calc-stack-size))

  (maf-push "16 2^x")
  (mnp-at "2^x" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (calc-pop (calc-stack-size))

  ;; A selection placed by hand on the number is honored as it stands.
  (maf-push "16 2^x")
  (progn (mnp-at "16" 1) (calc-select-here nil))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (cl-assert (null (calc-top 1 'sel)))
  (calc-pop (calc-stack-size))

  ;; Division, both ways round: the exponent gains or loses the power.
  (maf-push "16 / 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(-x + 4)"))
  (calc-pop (calc-stack-size))

  (maf-push "2^x / 16")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x - 4)"))
  (calc-pop (calc-stack-size))

  (maf-push "2^x / 16")
  (mnp-at "16" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x - 4)"))
  (calc-pop (calc-stack-size))

  ;; Any base, not just 2; the exponent is the integer log.
  (maf-push "16 4^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "4^(x + 2)"))
  (calc-pop (calc-stack-size))

  (maf-push "27 3^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "3^(x + 3)"))
  (calc-pop (calc-stack-size))

  ;; The bare base still goes through calc's own rule, as before.
  (maf-push "2 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(1 + x)"))
  (calc-pop (calc-stack-size))

  ;; Only the site the rule matches changes; the rest of the entry is
  ;; carried over as written.
  (maf-push "16 2^x + y")
  (mnp-at "16" 1)
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "2^(x + 4) + y"))
  (calc-pop (calc-stack-size))

  ;; --- what is not a power of the base is left alone ---------------

  ;; An integer that is not an exact power: ilog rounds down, and the
  ;; last condition is what rejects it. The entry stands, nothing
  ;; pushed or popped.
  (maf-push "12 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "12 2^x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  (maf-push "3 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "3 2^x"))
  (calc-pop (calc-stack-size))

  ;; A symbolic base cannot be read for a power; a float is not an
  ;; integer; a negative operand is outside ilog's domain and is not
  ;; merged rather than signaled about.
  (maf-push "16 x^y")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "16 x^y"))
  (calc-pop (calc-stack-size))

  (maf-push "16. 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "16. 2^x"))
  (calc-pop (calc-stack-size))

  (maf-push "-8 2^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "-8 2^x"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  (maf-push "16 (-2)^x")
  (goto-char (point-max))
  (call-interactively 'maf-merge)
  (cl-assert (string= (mnp-top) "16 (-2)^x"))
  (calc-pop (calc-stack-size))

  ;; --- undo and the key ---------------------------------------------

  (maf-push "16 2^x")
  (mnp-at "16" 1)
  (call-interactively 'maf-merge)
  (call-interactively 'maf-undo)
  (cl-assert (string= (mnp-top) "16 2^x"))
  (calc-pop (calc-stack-size))

  (maf-push "16 2^x")
  (mnp-at "2^x" 1)
  (execute-kbd-macro (kbd "j M"))
  (cl-assert (string= (mnp-top) "2^(x + 4)"))
  (calc-pop (calc-stack-size)))
