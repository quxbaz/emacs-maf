;; What the shipped formulas say, checked as arithmetic. Every entry in
;; `maf-formulas-builtin' is substituted with numbers and evaluated:
;; an equation must balance to within rounding, and one that states a
;; condition (`zero-product-property', the absolute-value splits, the
;; triangle inequalities) must come out true. A typo in an internal
;; form — a sign, a swapped operand, the wrong `calcFunc-' — survives
;; formulas-builtin.el, which only asks that the entries are well
;; formed and reach the menu. It does not survive this.
;;
;; Most formulas are identities in free variables, so one set of values
;; does for them; the run is repeated with a second, unrelated set so a
;; coincidence at the first has to hold twice. The rest relate named
;; quantities to each other — a quadratic's roots to its coefficients —
;; and get values of their own, since arbitrary ones make them false
;; and rightly so.
;;
;; Touches no calc state: nothing is pushed, and the modes the
;; evaluation needs are let-bound around it.

(require 'calc-ext)

(maf-step
  ;; Values for the free variables. Positive where a formula wants a
  ;; positive (logs, roots), nonzero everywhere, and no base of 1.
  (setq blv--values
        '((x . "2.3") (y . "1.7") (a . "1.3") (b . "0.7") (c . "2.9")
          (d . "1.9") (m . "1.4") (n . "2.6") (p . "0.8")
          (r1 . "1.1") (r2 . "0.5")))

  ;; A second set, chosen to share nothing with the first: negatives
  ;; and a fractional exponent where the domains allow them.
  (setq blv--values-2
        '((x . "0.37") (y . "3.1") (a . "2.2") (b . "1.05") (c . "-0.6")
          (d . "4.3") (m . "-1.7") (n . "1.9") (p . "2.4")
          (r1 . "-0.8") (r2 . "1.6")))

  ;; The formulas that are relations rather than identities: they hold
  ;; only for values that already stand in the relation, so each names
  ;; its own. These lead the list, and the free-variable values fill in
  ;; whatever they leave.
  (setq blv--special
        '(("zero-product-property" (a . "0"))
          ;; The equality properties hold only where a = b already, so
          ;; the two are pinned equal; c stays free, and varies with the
          ;; run, since they hold for every c (a nonzero one to divide
          ;; by, which both sets give).
          ("addition-property-of-equality"       (a . "3.4") (b . "3.4"))
          ("subtraction-property-of-equality"    (a . "3.4") (b . "3.4"))
          ("multiplication-property-of-equality" (a . "3.4") (b . "3.4"))
          ("division-property-of-equality"       (a . "3.4") (b . "3.4"))
          ("quadratic-formula-first-root"  (a . "1") (b . "-5") (c . "6")
                                           (x . "3"))
          ("quadratic-formula-second-root" (a . "1") (b . "-5") (c . "6")
                                           (x . "2"))
          ("discriminant"          (a . "1") (b . "-5") (c . "6") (d . "1"))
          ("sum-of-the-roots"      (a . "1") (b . "-5") (r1 . "3") (r2 . "2"))
          ("product-of-the-roots"  (a . "1") (c . "6")  (r1 . "3") (r2 . "2"))
          ("factored-form-of-a-quadratic"
           (a . "1") (b . "-5") (c . "6") (r1 . "3") (r2 . "2") (x . "2.3"))
          ("vertex-of-a-parabola"  (a . "1") (b . "-5") (x . "2.5"))
          ("cross-multiplication"  (a . "1") (b . "3") (c . "4") (d . "12"))
          ("absolute-value-equation"       (x . "5") (a . "5"))
          ("absolute-value-less-than"      (x . "3") (a . "5"))
          ("absolute-value-greater-than"   (x . "7") (a . "5"))
          ("absolute-value-is-nonnegative" (x . "-3"))
          ;; The solids relate measurements to each other, so each
          ;; names a consistent box: the 3-4-12 one, whose diagonal is
          ;; the integer 13, and the edge-2 cube.
          ("volume-of-rectangular-solid"
           (V . "144") (l . "3") (w . "4") (h . "12"))
          ("surface-area-of-rectangular-solid"
           (S . "192") (l . "3") (w . "4") (h . "12"))
          ("lateral-surface-area-of-rectangular-solid"
           (SL . "168") (l . "3") (w . "4") (h . "12"))
          ("diagonal-of-rectangular-solid"
           (d . "13") (l . "3") (w . "4") (h . "12"))
          ("volume-of-cube"       (V . "8") (s . "2"))
          ("surface-area-of-cube" (S . "24") (s . "2"))
          ("diagonal-of-cube"     (d . "2 sqrt(3)") (s . "2"))
          ;; The 3-4-5 triangle laid on the plane.
          ("distance-formula"
           (d . "5") (x1 . "1") (y1 . "2") (x2 . "4") (y2 . "6"))))

  (defun blv--subst (expr vals)
    "EXPR with each variable in VALS replaced by its number.
VALS is walked in order and a name already substituted is gone, so a
special value shadows the free-variable one that follows it."
    (dolist (v vals expr)
      (setq expr (math-expr-subst
                  expr
                  (list 'var (car v)
                        (intern (concat "var-" (symbol-name (car v)))))
                  (math-read-expr (cdr v))))))

  (defun blv--number (expr)
    "EXPR evaluated to a Lisp float, or nil if it did not go numeric.
The nil matters: an expression left partly symbolic would otherwise
read as zero and pass."
    (let ((v (math-evaluate-expr expr)))
      (and (math-realp v)
           (string-to-number (math-format-value (math-float v))))))

  (defun blv--check (f vals)
    "nil when formula F holds at VALS, else a string saying how it failed."
    (let* ((name (plist-get f :name))
           (vals (append (cdr (assoc name blv--special)) vals))
           (expr (blv--subst (copy-tree (plist-get f :expr)) vals)))
      (cond
       ((math-expr-contains-vars expr)
        (format "%s: a variable has no value here" name))
       ((eq (car-safe expr) 'calcFunc-eq)
        (let ((diff (blv--number (math-sub (nth 1 expr) (nth 2 expr)))))
          (cond ((null diff) (format "%s: did not evaluate to a number" name))
                ((> (abs diff) 1e-8) (format "%s: sides differ by %g"
                                             name diff)))))
       (t (unless (eq (math-evaluate-expr expr) 1)
            (format "%s: does not come out true" name))))))

  (defun blv--run (vals)
    "Every shipped formula checked at VALS; the failures, or nil."
    (let ((calc-angle-mode 'rad)         ; the trig identities hold in
                                         ; either mode; radians read
                                         ; better in a failure message
          (calc-internal-prec 20)        ; room under the 1e-8 tolerance
          (calc-symbolic-mode nil)       ; sqrt(2) must go numeric
          (calc-prefer-frac nil)
          (calc-infinite-mode nil))
      (delq nil (mapcar (lambda (f) (blv--check f vals)) maf-formulas-builtin))))

  ;; Something is being checked — an empty set would pass silently.
  (cl-assert (> (length maf-formulas-builtin) 90))

  ;; Every formula holds, at both sets of values.
  (cl-assert (null (blv--run blv--values)))
  (cl-assert (null (blv--run blv--values-2)))

  ;; And the check has teeth: a sign flipped in a shipped formula is
  ;; caught, and a formula left symbolic is not mistaken for a pass.
  (cl-assert (blv--check '(:name "bent" :expr (calcFunc-eq (+ (var a var-a)
                                                              (var b var-b))
                                                           (- (var a var-a)
                                                              (var b var-b))))
                         blv--values))
  (cl-assert (blv--check '(:name "free" :expr (calcFunc-eq (var zz var-zz) 1))
                         blv--values))
  :checked)
