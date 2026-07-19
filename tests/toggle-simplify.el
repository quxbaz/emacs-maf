(maf-step
  ;; Normalization — the path algebraic entry takes — evaluates while
  ;; simplification is on and stops dead while it is off. maf-push
  ;; bypasses it, so probe calc-normalize directly.

  ;; Baseline: simplification on.
  (cl-assert (not (eq calc-simplify-mode 'none)))
  (cl-assert (equal (calc-normalize '(+ 2 3)) 5))

  ;; Toggle off: normalization commits structurally.
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq calc-simplify-mode 'none))
  (cl-assert (equal (calc-normalize '(+ 2 3)) '(+ 2 3)))

  ;; Toggle back on: the default algebraic mode returns.
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq calc-simplify-mode 'alg))
  (cl-assert (equal (calc-normalize '(+ 2 3)) 5))

  ;; A non-default mode survives the round trip: off from units mode,
  ;; back to units mode — not to algebraic.
  (calc-change-mode 'calc-simplify-mode 'units)
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq calc-simplify-mode 'none))
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq calc-simplify-mode 'units))
  (calc-change-mode 'calc-simplify-mode 'alg)

  ;; Starting out disabled — none set by hand, no capture pending —
  ;; restores the algebraic default rather than a stale capture.
  (calc-change-mode 'calc-simplify-mode 'none)
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq calc-simplify-mode 'alg))

  ;; Point stays put: toggle with point parked on an entry.
  (maf-push "6 x + 12")
  (progn (goto-char (point-min)) (search-forward "6 x +") (backward-char 1))
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq (char-after) ?+))
  (cl-assert (eq calc-simplify-mode 'none))
  (call-interactively 'maf-toggle-simplify)
  (cl-assert (eq (char-after) ?+))
  (cl-assert (eq calc-simplify-mode 'alg))
  (calc-pop (calc-stack-size)))
