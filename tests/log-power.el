;; maf-log-power module: general-base log identities under
;; simplification. Calc only collapses b^log(a,b) for base 10 and e;
;; the module adds the rule for any base, plus the guarded reverse
;; log(b^y, b) -> y. Exercised through the real commands: a s is
;; mafcmd-esimplify (extended simplification) and a e mafcmd-simplify
;; (basic), which is what makes the reverse rule's realp guard
;; observable.

(maf-step
  (cl-assert maf-use-log-power-mode)

  ;; The motivating case: an equation with a matching-base power of a
  ;; log collapses on a s.
  (maf-push "3^log((x+2) (x-4), 3) = 27")
  (goto-char (point-max))
  (call-interactively 'mafcmd-esimplify)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "(x + 2) (x - 4) = 27"))
  (calc-pop (calc-stack-size))

  ;; The bare identity, and a symbolic base.
  (maf-push "3^log(x, 3)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-esimplify)
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop (calc-stack-size))
  (maf-push "b^log(x, b)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-esimplify)
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop (calc-stack-size))

  ;; A mismatched base stays put.
  (maf-push "2^log(x, 3)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-esimplify)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "2^log(x, 3)"))
  (calc-pop (calc-stack-size))

  ;; The reverse direction collapses under a s, whose extended
  ;; simplification waives the realp guard...
  (maf-push "log(3^x, 3)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-esimplify)
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop (calc-stack-size))

  ;; ...but holds under a e, where x is not known real — mirroring
  ;; upstream's guard on ln(e^x) and log10(10^x).
  (maf-push "log(3^x, 3)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-simplify)
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "log(3^x, 3)"))
  (calc-pop (calc-stack-size))

  ;; Upstream's own base-10 rule still runs: the module appends its
  ;; handler after calc's rather than displacing it.
  (maf-push "10^log10(x)")
  (goto-char (point-max))
  (call-interactively 'mafcmd-esimplify)
  (cl-assert (equal (calc-top 1 'full) '(var x var-x)))
  (calc-pop (calc-stack-size))

  ;; Module off, vanilla calc behavior returns.
  (unwind-protect
      (progn
        (maf-use-log-power-mode -1)
        (maf-push "3^log(x, 3)")
        (goto-char (point-max))
        (call-interactively 'mafcmd-esimplify)
        (cl-assert (string= (math-format-value (calc-top 1 'full))
                            "3^log(x, 3)")))
    (maf-use-log-power-mode 1))
  (calc-pop (calc-stack-size)))
