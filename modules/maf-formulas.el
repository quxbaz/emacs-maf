;; -*- lexical-binding: t; -*-
;;
;; modules/maf-formulas.el
;;
;; Saved-formula library. `maf-formulas' opens a menu of formulas
;; grouped by category, each shown beside its form, with a detail pane
;; following point — the formula in Big display, a description, and
;; what each variable means — re-rendering for each formula reached.
;; `O' toggles that following pane off and on, and the choice holds
;; for the rest of the session, so the menu reopens the way it was
;; left; the legend's "O follows" shows gold while it is on. `o' (or
;; `?') toggles the pane's visibility, deferring to that flag: with
;; `O' on, closing is only a peek at calc, the pane returning as soon
;; as point reaches another formula; with `O' off, `o' shows the
;; formula at point and moving off its line dismisses the pane again.
;; `C-g' closes the pane and turns follow off. RET pushes the formula
;; at point onto the calc stack, and RET on a group header narrows the
;; menu to that group, whole — any filter in force is lifted for it,
;; and comes back when RET on that header widens the list again.
;; The key legend stays in the header line while the menu is narrowed,
;; the narrowing shown at its head rather than in place of it.
;;
;; A formula is a plist. Only :expr is required; the rest are optional
;; and the detail pane renders just what is present:
;;
;;   (:name "area-of-triangle"          ; id for the calc var-eq-<name>
;;    :title "Area of triangle"         ; menu label (derived if absent)
;;    :category "Geometry — 2D"         ; grouping (a default if absent)
;;    :expr (calcFunc-eq ...)           ; REQUIRED — the equation/expr
;;    :display-expr (calcFunc-eq ...)   ; optional render-only variant
;;    :doc "..."                        ; optional one-line description
;;    :examples ("..." ...)             ; optional worked examples
;;    :vars ((A . "area") ...))         ; optional variable meanings
;;
;; Formulas you insert are remembered in a "Recent" group at the top of
;; the menu for the rest of the session; it is not written anywhere.
;; `D' drops the entry at point from the group (the formula itself
;; stays, under its own category).
;;
;; The menu draws on two sources. `maf-formulas-builtin' is the set maf
;; ships with — the identities of school algebra and trigonometry — and
;; yours follow it: they live in `maf-formulas-file' (a file in your
;; Emacs config by default), which is loaded on first use and sets
;; `maf-formulas-user'.
;; Set that variable directly in your init to skip the file, or set
;; `maf-formulas-builtin' to nil to keep only your own. Enabling the
;; module (see `maf-modules') registers every formula as a calc
;; `var-eq-<name>' variable, so calc's own recall and rewrite see them
;; too — the two variables are the single source, calc's variables
;; generated from them.

(require 'calc)
(require 'maf-lib)
(require 'cl-lib)
(require 'maf-conf "conf")  ; the `maf' customize group
(require 'dial)             ; `dial-controls', the legend's chrome

;; The module installs its `s o' binding into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

;; Defined in lazily-loaded calc modules; declared for the byte compiler.
(declare-function math-format-value "calc-ext")
(declare-function calc-pop-push-record-list "calc-ext")
(declare-function maf-register-module "maf-module")
(declare-function maf-bindings-module-keys "maf-bindings")
(declare-function maf-bindings--refresh "maf-bindings")

(defface maf-formulas-category
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for category headers and the detail title in the formula menu."
  :group 'maf)

(defface maf-formulas-recent
  '((t :inherit warning :weight bold))
  "Face for the \"Recent\" header in the formula menu.
Gold rather than the category color the other headers take: the group
is not a category at all, but what this session reached for last, and
it leads the buffer where the eye starts. The gold is `warning's,
which is where maf-edit's header badge takes its own from — one gold
across maf's buffers, and it follows the theme rather than pinning a
color that only suits some."
  :group 'maf)

(defface maf-formulas-var
  '((t :inherit font-lock-variable-name-face))
  "Face for variable names in the formula detail."
  :group 'maf)

(defface maf-formulas-leader
  '((t :inherit shadow))
  "Face for the dotted leader between a formula's name and its form."
  :group 'maf)

(defface maf-formulas-title
  '((((background dark))  :foreground "grey70")
    (((background light)) :foreground "grey35")
    (t :foreground "grey70"))
  "Face for the formula name (title) in the menu list."
  :group 'maf)

(defface maf-formulas-form
  '((((background dark))  :foreground "white")
    (((background light)) :foreground "black")
    (t :foreground "white"))
  "Face for the formula shown beside each title in the menu list."
  :group 'maf)

(defcustom maf-formulas-file (locate-user-emacs-file "maf-formulas.el")
  "File of saved formulas, loaded on first use when it exists.
The file sets `maf-formulas-user' to a list of formula plists (see the
commentary above for the shape). nil disables file loading; populate
`maf-formulas-user' from your init instead."
  :type '(choice (const :tag "None" nil) file)
  :group 'maf)

(defcustom maf-formulas-user nil
  "Your saved formulas, in the plist shape described in the commentary.
Loaded from `maf-formulas-file' when that file exists; set it directly
in your init to add formulas without a file. Only :expr is required."
  :type '(repeat plist)
  :group 'maf)

(defcustom maf-formulas-recent-max 10
  "How many recently-inserted formulas the \"Recent\" group holds.
Zero drops the group entirely. The list is per-session; nothing is
written to disk."
  :type 'integer
  :group 'maf)

(defcustom maf-formulas-detail-min-width 64
  "Narrowest pane, in columns, the detail is worth showing beside the list.
The pane splits the menu's window, so a side split halves its width
while a split below halves its height — the two leave the same number
of cells either way. What differs is the shape: the Big rendering and
the filled prose need a floor on width but can be scrolled for height,
so the side split is only taken when both halves clear this width."
  :type 'integer
  :group 'maf)

(defconst maf-formulas--detail-buffer " *maf-formulas-detail*"
  "Name of the buffer showing detail for the formula at point.")

(defconst maf-formulas--recent-category "Recent"
  "Category header for the recently-inserted group, shown first when unfiltered.")

(defvar maf-formulas--loaded nil
  "Non-nil once `maf-formulas-file' has been consulted this session.")

(defvar maf-formulas-builtin
  '((:name "commutative-property-of-addition"
     :title "Commutative property of addition"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (+ (var a var-a) (var b var-b))
                        (+ (var b var-b) (var a var-a)))
     :doc "Addition gives the same sum in either order."
     :vars ((a . "any number") (b . "any number")))
    (:name "commutative-property-of-multiplication"
     :title "Commutative property of multiplication"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) (var b var-b))
                        (* (var b var-b) (var a var-a)))
     :doc "Multiplication gives the same product in either order."
     :vars ((a . "any number") (b . "any number")))
    (:name "associative-property-of-addition"
     :title "Associative property of addition"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (+ (+ (var a var-a) (var b var-b)) (var c var-c))
                        (+ (var a var-a) (+ (var b var-b) (var c var-c))))
     :doc "Grouping does not change a sum."
     :vars ((a . "any number") (b . "any number") (c . "any number")))
    (:name "associative-property-of-multiplication"
     :title "Associative property of multiplication"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (* (var a var-a) (var b var-b)) (var c var-c))
                        (* (var a var-a) (* (var b var-b) (var c var-c))))
     :doc "Grouping does not change a product."
     :vars ((a . "any number") (b . "any number") (c . "any number")))
    (:name "distributive-property"
     :title "Distributive property"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) (+ (var b var-b) (var c var-c)))
                        (+ (* (var a var-a) (var b var-b))
                           (* (var a var-a) (var c var-c))))
     :doc "Multiplication distributes over addition."
     :vars ((a . "multiplier") (b . "first term") (c . "second term")))
    (:name "distributive-property-over-subtraction"
     :title "Distributive property over subtraction"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) (- (var b var-b) (var c var-c)))
                        (- (* (var a var-a) (var b var-b))
                           (* (var a var-a) (var c var-c))))
     :doc "Multiplication distributes over subtraction."
     :vars ((a . "multiplier") (b . "first term") (c . "second term")))
    (:name "additive-identity"
     :title "Additive identity"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (+ (var a var-a) 0) (var a var-a))
     :doc "Zero added to a number leaves it unchanged."
     :vars ((a . "any number")))
    (:name "multiplicative-identity"
     :title "Multiplicative identity"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) 1) (var a var-a))
     :doc "One times a number leaves it unchanged."
     :vars ((a . "any number")))
    (:name "additive-inverse"
     :title "Additive inverse"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (+ (var a var-a) (neg (var a var-a))) 0)
     :doc "A number plus its opposite is zero."
     :vars ((a . "any number")))
    (:name "multiplicative-inverse"
     :title "Multiplicative inverse"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) (/ 1 (var a var-a))) 1)
     :doc "A nonzero number times its reciprocal is one."
     :vars ((a . "any nonzero number")))
    (:name "multiplication-by-zero"
     :title "Multiplication by zero"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) 0) 0)
     :doc "Anything times zero is zero."
     :vars ((a . "any number")))
    (:name "zero-product-property"
     :title "Zero product property"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-lor (calcFunc-eq (var a var-a) 0)
                         (calcFunc-eq (var b var-b) 0))
     :doc "When a b = 0, at least one factor is zero."
     :vars ((a . "first factor") (b . "second factor"))
     :examples ("(x - 2) (x - 3) = 0 gives x = 2 or x = 3."))
    (:name "double-negation"
     :title "Double negation"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (neg (neg (var a var-a))) (var a var-a))
     :doc "Negating twice returns the original number."
     :vars ((a . "any number")))
    (:name "subtraction-as-addition"
     :title "Subtraction as addition"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (- (var a var-a) (var b var-b))
                        (+ (var a var-a) (neg (var b var-b))))
     :doc "Subtracting is adding the opposite."
     :vars ((a . "minuend") (b . "subtrahend")))
    (:name "division-as-multiplication"
     :title "Division as multiplication"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (/ (var a var-a) (var b var-b))
                        (* (var a var-a) (/ 1 (var b var-b))))
     :doc "Dividing is multiplying by the reciprocal."
     :vars ((a . "numerator") (b . "nonzero denominator")))
    (:name "sign-rule-for-a-product"
     :title "Sign rule for a product"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (neg (var a var-a)) (var b var-b))
                        (* (var a var-a) (neg (var b var-b))))
     :doc "Negating a factor negates the product: (-a) b = a (-b) = -(a b)."
     :vars ((a . "first factor") (b . "second factor")))
    (:name "product-of-two-negatives"
     :title "Product of two negatives"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (neg (var a var-a)) (neg (var b var-b)))
                        (* (var a var-a) (var b var-b)))
     :doc "A product of two negatives is positive."
     :vars ((a . "first factor") (b . "second factor")))
    (:name "logarithm-of-a-product"
     :title "Logarithm of a product"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (* (var x var-x) (var y var-y))
                                      (var b var-b))
                        (+ (calcFunc-log (var x var-x) (var b var-b))
                           (calcFunc-log (var y var-y) (var b var-b))))
     :doc "The log of a product is the sum of the logs."
     :vars ((x . "positive number")
            (y . "positive number")
            (b . "base, positive and not 1")))
    (:name "logarithm-of-a-quotient"
     :title "Logarithm of a quotient"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (/ (var x var-x) (var y var-y))
                                      (var b var-b))
                        (- (calcFunc-log (var x var-x) (var b var-b))
                           (calcFunc-log (var y var-y) (var b var-b))))
     :doc "The log of a quotient is the difference of the logs."
     :vars ((x . "positive number")
            (y . "positive number")
            (b . "base, positive and not 1")))
    (:name "logarithm-of-a-power"
     :title "Logarithm of a power"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (^ (var x var-x) (var p var-p))
                                      (var b var-b))
                        (* (var p var-p)
                           (calcFunc-log (var x var-x) (var b var-b))))
     :doc "An exponent inside a log comes out as a factor."
     :vars ((x . "positive number")
            (p . "any exponent")
            (b . "base, positive and not 1")))
    (:name "logarithm-of-a-root"
     :title "Logarithm of a root"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (^ (var x var-x) (/ 1 (var n var-n)))
                                      (var b var-b))
                        (/ (calcFunc-log (var x var-x) (var b var-b))
                           (var n var-n)))
     :doc "A root inside a log comes out as a divisor."
     :vars ((x . "positive number")
            (n . "nonzero root index")
            (b . "base, positive and not 1")))
    (:name "logarithm-of-a-reciprocal"
     :title "Logarithm of a reciprocal"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (/ 1 (var x var-x)) (var b var-b))
                        (neg (calcFunc-log (var x var-x) (var b var-b))))
     :doc "Inverting the argument negates the log."
     :vars ((x . "positive number") (b . "base, positive and not 1")))
    (:name "base-to-a-logarithm"
     :title "Base raised to a logarithm"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (^ (var b var-b)
                           (calcFunc-log (var x var-x) (var b var-b)))
                        (var x var-x))
     :doc "Exponentiation undoes the logarithm of the same base."
     :vars ((x . "positive number") (b . "base, positive and not 1")))
    (:name "logarithm-of-a-power-of-the-base"
     :title "Logarithm of a power of the base"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (^ (var b var-b) (var x var-x))
                                      (var b var-b))
                        (var x var-x))
     :doc "The logarithm undoes exponentiation of the same base."
     :vars ((x . "any number") (b . "base, positive and not 1")))
    (:name "change-of-base"
     :title "Change of base"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (var x var-x) (var b var-b))
                        (/ (calcFunc-ln (var x var-x))
                           (calcFunc-ln (var b var-b))))
     :doc "Any log is a ratio of logs in another base."
     :vars ((x . "positive number") (b . "base, positive and not 1"))
     :examples ("log(8, 2) = ln(8) / ln(2) = 3."))
    (:name "logarithm-of-one"
     :title "Logarithm of one"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log 1 (var b var-b)) 0)
     :doc "One is what any base raised to zero gives."
     :vars ((b . "base, positive and not 1")))
    (:name "logarithm-of-the-base"
     :title "Logarithm of the base"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-log (var b var-b) (var b var-b)) 1)
     :doc "A base raised to one gives itself."
     :vars ((b . "base, positive and not 1")))
    (:name "exponential-of-a-natural-logarithm"
     :title "Exponential of a natural logarithm"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-exp (calcFunc-ln (var x var-x)))
                        (var x var-x))
     :doc "e to the natural log of a positive number returns it."
     :vars ((x . "positive number")))
    (:name "natural-logarithm-of-an-exponential"
     :title "Natural logarithm of an exponential"
     :category "Algebra — Logarithms"
     :expr (calcFunc-eq (calcFunc-ln (calcFunc-exp (var x var-x)))
                        (var x var-x))
     :doc "The natural log undoes e to a power."
     :vars ((x . "any number")))
    (:name "quadratic-formula-first-root"
     :title "Quadratic formula, first root"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (var x var-x)
                        (/ (+ (neg (var b var-b))
                              (calcFunc-sqrt
                               (- (^ (var b var-b) 2)
                                  (* 4 (* (var a var-a) (var c var-c))))))
                           (* 2 (var a var-a))))
     :doc "The larger root of a x^2 + b x + c = 0 when a > 0."
     :vars ((a . "coefficient of x^2, nonzero")
            (b . "coefficient of x")
            (c . "constant term"))
     :examples ("x^2 - 5 x + 6 = 0 gives 3 here and 2 from the other root."))
    (:name "quadratic-formula-second-root"
     :title "Quadratic formula, second root"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (var x var-x)
                        (/ (- (neg (var b var-b))
                              (calcFunc-sqrt
                               (- (^ (var b var-b) 2)
                                  (* 4 (* (var a var-a) (var c var-c))))))
                           (* 2 (var a var-a))))
     :doc "The other root: the same formula with the root subtracted."
     :vars ((a . "coefficient of x^2, nonzero")
            (b . "coefficient of x")
            (c . "constant term")))
    (:name "discriminant"
     :title "Discriminant"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (var d var-d)
                        (- (^ (var b var-b) 2)
                           (* 4 (* (var a var-a) (var c var-c)))))
     :doc "Positive gives two real roots, zero gives one, negative none."
     :vars ((a . "coefficient of x^2, nonzero")
            (b . "coefficient of x")
            (c . "constant term")
            (d . "the discriminant")))
    (:name "sum-of-the-roots"
     :title "Sum of the roots (Vieta)"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (+ (var r1 var-r1) (var r2 var-r2))
                        (/ (neg (var b var-b)) (var a var-a)))
     :doc "The roots of a x^2 + b x + c = 0 add to -b/a."
     :vars ((a . "coefficient of x^2, nonzero")
            (b . "coefficient of x")
            (r1 . "first root")
            (r2 . "second root")))
    (:name "product-of-the-roots"
     :title "Product of the roots (Vieta)"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (* (var r1 var-r1) (var r2 var-r2))
                        (/ (var c var-c) (var a var-a)))
     :doc "The roots of a x^2 + b x + c = 0 multiply to c/a."
     :vars ((a . "coefficient of x^2, nonzero")
            (c . "constant term")
            (r1 . "first root")
            (r2 . "second root")))
    (:name "factored-form-of-a-quadratic"
     :title "Factored form of a quadratic"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (+ (+ (* (var a var-a) (^ (var x var-x) 2))
                              (* (var b var-b) (var x var-x)))
                           (var c var-c))
                        (* (var a var-a)
                           (* (- (var x var-x) (var r1 var-r1))
                              (- (var x var-x) (var r2 var-r2)))))
     :doc "A quadratic written from its roots."
     :vars ((a . "coefficient of x^2, nonzero")
            (b . "coefficient of x")
            (c . "constant term")
            (x . "the variable")
            (r1 . "first root")
            (r2 . "second root")))
    (:name "completing-the-square"
     :title "Completing the square"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (+ (+ (* (var a var-a) (^ (var x var-x) 2))
                              (* (var b var-b) (var x var-x)))
                           (var c var-c))
                        (+ (* (var a var-a)
                              (^ (+ (var x var-x)
                                    (/ (var b var-b) (* 2 (var a var-a))))
                                 2))
                           (- (var c var-c)
                              (/ (^ (var b var-b) 2) (* 4 (var a var-a))))))
     :doc "A quadratic as a shifted square, which is where the formula comes from."
     :vars ((a . "coefficient of x^2, nonzero")
            (b . "coefficient of x")
            (c . "constant term")
            (x . "the variable")))
    (:name "vertex-of-a-parabola"
     :title "Vertex of a parabola"
     :category "Algebra — Quadratic equations"
     :expr (calcFunc-eq (var x var-x)
                        (/ (neg (var b var-b)) (* 2 (var a var-a))))
     :doc "The turning point sits halfway between the roots."
     :vars ((a . "coefficient of x^2, nonzero") (b . "coefficient of x")))
    (:name "zero-exponent"
     :title "Zero exponent"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (var x var-x) 0) 1)
     :doc "Anything nonzero to the zeroth power is one."
     :vars ((x . "any nonzero number")))
    (:name "first-power"
     :title "First power"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (var x var-x) 1) (var x var-x))
     :doc "A number to the first power is itself."
     :vars ((x . "any number")))
    (:name "negative-exponent"
     :title "Negative exponent"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (var x var-x) (neg (var n var-n)))
                        (/ 1 (^ (var x var-x) (var n var-n))))
     :doc "A negative exponent inverts the power."
     :vars ((x . "any nonzero number") (n . "any exponent")))
    (:name "product-of-powers"
     :title "Product of powers"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (* (^ (var x var-x) (var m var-m))
                           (^ (var x var-x) (var n var-n)))
                        (^ (var x var-x) (+ (var m var-m) (var n var-n))))
     :doc "Multiplying like bases adds the exponents."
     :vars ((x . "the base") (m . "first exponent") (n . "second exponent")))
    (:name "quotient-of-powers"
     :title "Quotient of powers"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (/ (^ (var x var-x) (var m var-m))
                           (^ (var x var-x) (var n var-n)))
                        (^ (var x var-x) (- (var m var-m) (var n var-n))))
     :doc "Dividing like bases subtracts the exponents."
     :vars ((x . "nonzero base")
            (m . "first exponent")
            (n . "second exponent")))
    (:name "power-of-a-power"
     :title "Power of a power"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (^ (var x var-x) (var m var-m)) (var n var-n))
                        (^ (var x var-x) (* (var m var-m) (var n var-n))))
     :doc "Raising a power to a power multiplies the exponents."
     :vars ((x . "the base") (m . "inner exponent") (n . "outer exponent")))
    (:name "power-of-a-product"
     :title "Power of a product"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (* (var x var-x) (var y var-y)) (var n var-n))
                        (* (^ (var x var-x) (var n var-n))
                           (^ (var y var-y) (var n var-n))))
     :doc "An exponent distributes over a product."
     :vars ((x . "first factor") (y . "second factor") (n . "any exponent")))
    (:name "power-of-a-quotient"
     :title "Power of a quotient"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (/ (var x var-x) (var y var-y)) (var n var-n))
                        (/ (^ (var x var-x) (var n var-n))
                           (^ (var y var-y) (var n var-n))))
     :doc "An exponent distributes over a quotient."
     :vars ((x . "numerator")
            (y . "nonzero denominator")
            (n . "any exponent")))
    (:name "rational-exponent"
     :title "Rational exponent"
     :category "Algebra — Exponents"
     :expr (calcFunc-eq (^ (var x var-x) (/ (var m var-m) (var n var-n)))
                        (^ (^ (var x var-x) (/ 1 (var n var-n)))
                           (var m var-m)))
     :doc "A fractional exponent is a root raised to a power."
     :vars ((x . "nonnegative for even n")
            (m . "numerator of the exponent")
            (n . "nonzero root index")))
    (:name "square-root-as-an-exponent"
     :title "Square root as an exponent"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (calcFunc-sqrt (var x var-x))
                        (^ (var x var-x) (/ 1 2)))
     :doc "A square root is the one-half power."
     :vars ((x . "nonnegative number")))
    (:name "nth-root-as-an-exponent"
     :title "Nth root as an exponent"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (calcFunc-nroot (var x var-x) (var n var-n))
                        (^ (var x var-x) (/ 1 (var n var-n))))
     :doc "An nth root is the 1/n power."
     :vars ((x . "nonnegative for even n") (n . "nonzero root index")))
    (:name "product-of-radicals"
     :title "Product of radicals"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (calcFunc-sqrt (* (var x var-x) (var y var-y)))
                        (* (calcFunc-sqrt (var x var-x))
                           (calcFunc-sqrt (var y var-y))))
     :doc "A root of a product splits into a product of roots."
     :vars ((x . "nonnegative number") (y . "nonnegative number")))
    (:name "quotient-of-radicals"
     :title "Quotient of radicals"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (calcFunc-sqrt (/ (var x var-x) (var y var-y)))
                        (/ (calcFunc-sqrt (var x var-x))
                           (calcFunc-sqrt (var y var-y))))
     :doc "A root of a quotient splits into a quotient of roots."
     :vars ((x . "nonnegative number") (y . "positive number")))
    (:name "root-of-a-square"
     :title "Root of a square"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (calcFunc-sqrt (^ (var x var-x) 2))
                        (calcFunc-abs (var x var-x)))
     :doc "The square root of a square is the absolute value, not the number."
     :vars ((x . "any real number"))
     :examples ("sqrt((-3)^2) = 3, not -3."))
    (:name "rationalize-a-root-denominator"
     :title "Rationalize a root denominator"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (/ 1 (calcFunc-sqrt (var x var-x)))
                        (/ (calcFunc-sqrt (var x var-x)) (var x var-x)))
     :doc "Multiplying above and below by the root clears it from the denominator."
     :vars ((x . "positive number")))
    (:name "rationalize-by-the-conjugate"
     :title "Rationalize by the conjugate"
     :category "Algebra — Radicals"
     :expr (calcFunc-eq (/ 1
                           (+ (var a var-a) (calcFunc-sqrt (var b var-b))))
                        (/ (- (var a var-a) (calcFunc-sqrt (var b var-b)))
                           (- (^ (var a var-a) 2) (var b var-b))))
     :doc "The conjugate clears a root from a two-term denominator."
     :vars ((a . "rational part") (b . "nonnegative, with a^2 not b")))
    (:name "addition-of-fractions"
     :title "Addition of fractions"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (+ (/ (var a var-a) (var b var-b))
                           (/ (var c var-c) (var d var-d)))
                        (/ (+ (* (var a var-a) (var d var-d))
                              (* (var b var-b) (var c var-c)))
                           (* (var b var-b) (var d var-d))))
     :doc "Cross-multiply over the common denominator b d."
     :vars ((a . "first numerator")
            (b . "nonzero denominator")
            (c . "second numerator")
            (d . "nonzero denominator")))
    (:name "subtraction-of-fractions"
     :title "Subtraction of fractions"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (- (/ (var a var-a) (var b var-b))
                           (/ (var c var-c) (var d var-d)))
                        (/ (- (* (var a var-a) (var d var-d))
                              (* (var b var-b) (var c var-c)))
                           (* (var b var-b) (var d var-d))))
     :doc "The same common denominator, with the numerators subtracted."
     :vars ((a . "first numerator")
            (b . "nonzero denominator")
            (c . "second numerator")
            (d . "nonzero denominator")))
    (:name "common-denominator"
     :title "Common denominator"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (+ (/ (var a var-a) (var c var-c))
                           (/ (var b var-b) (var c var-c)))
                        (/ (+ (var a var-a) (var b var-b)) (var c var-c)))
     :doc "Fractions over one denominator add across the top."
     :vars ((a . "first numerator")
            (b . "second numerator")
            (c . "nonzero denominator")))
    (:name "multiplication-of-fractions"
     :title "Multiplication of fractions"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (* (/ (var a var-a) (var b var-b))
                           (/ (var c var-c) (var d var-d)))
                        (/ (* (var a var-a) (var c var-c))
                           (* (var b var-b) (var d var-d))))
     :doc "Multiply the numerators and the denominators."
     :vars ((a . "first numerator")
            (b . "nonzero denominator")
            (c . "second numerator")
            (d . "nonzero denominator")))
    (:name "division-of-fractions"
     :title "Division of fractions"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (/ (/ (var a var-a) (var b var-b))
                           (/ (var c var-c) (var d var-d)))
                        (/ (* (var a var-a) (var d var-d))
                           (* (var b var-b) (var c var-c))))
     :doc "Dividing by a fraction multiplies by its reciprocal."
     :vars ((a . "first numerator")
            (b . "nonzero denominator")
            (c . "nonzero numerator")
            (d . "nonzero denominator")))
    (:name "cancel-a-common-factor"
     :title "Cancel a common factor"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (/ (* (var a var-a) (var c var-c))
                           (* (var b var-b) (var c var-c)))
                        (/ (var a var-a) (var b var-b)))
     :doc "A factor shared above and below cancels."
     :vars ((a . "numerator")
            (b . "nonzero denominator")
            (c . "nonzero common factor")))
    (:name "cross-multiplication"
     :title "Cross multiplication"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (* (var a var-a) (var d var-d))
                        (* (var b var-b) (var c var-c)))
     :doc "What a/b = c/d becomes with the denominators cleared."
     :vars ((a . "first numerator")
            (b . "nonzero denominator")
            (c . "second numerator")
            (d . "nonzero denominator"))
     :examples ("x/3 = 4/6 gives 6 x = 12, so x = 2."))
    (:name "reciprocal-of-a-fraction"
     :title "Reciprocal of a fraction"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (/ 1 (/ (var a var-a) (var b var-b)))
                        (/ (var b var-b) (var a var-a)))
     :doc "Inverting a fraction swaps its parts."
     :vars ((a . "nonzero numerator") (b . "nonzero denominator")))
    (:name "sign-of-a-fraction"
     :title "Sign of a fraction"
     :category "Algebra — Fractions"
     :expr (calcFunc-eq (neg (/ (var a var-a) (var b var-b)))
                        (/ (neg (var a var-a)) (var b var-b)))
     :doc "A minus sign can sit out front, on top, or below: it is also a/(-b)."
     :vars ((a . "numerator") (b . "nonzero denominator")))
    (:name "absolute-value-as-a-root"
     :title "Absolute value as a root"
     :category "Algebra — Absolute value"
     :expr (calcFunc-eq (calcFunc-abs (var x var-x))
                        (calcFunc-sqrt (^ (var x var-x) 2)))
     :doc "Squaring then taking the root drops the sign."
     :vars ((x . "any real number")))
    (:name "absolute-value-is-nonnegative"
     :title "Absolute value is nonnegative"
     :category "Algebra — Absolute value"
     :expr (calcFunc-geq (calcFunc-abs (var x var-x)) 0)
     :doc "A magnitude is never negative."
     :vars ((x . "any real number")))
    (:name "absolute-value-of-a-negative"
     :title "Absolute value of a negative"
     :category "Algebra — Absolute value"
     :expr (calcFunc-eq (calcFunc-abs (neg (var x var-x)))
                        (calcFunc-abs (var x var-x)))
     :doc "A number and its opposite have the same magnitude."
     :vars ((x . "any real number")))
    (:name "absolute-value-of-a-product"
     :title "Absolute value of a product"
     :category "Algebra — Absolute value"
     :expr (calcFunc-eq (calcFunc-abs (* (var a var-a) (var b var-b)))
                        (* (calcFunc-abs (var a var-a))
                           (calcFunc-abs (var b var-b))))
     :doc "The magnitude of a product is the product of the magnitudes."
     :vars ((a . "first factor") (b . "second factor")))
    (:name "absolute-value-of-a-quotient"
     :title "Absolute value of a quotient"
     :category "Algebra — Absolute value"
     :expr (calcFunc-eq (calcFunc-abs (/ (var a var-a) (var b var-b)))
                        (/ (calcFunc-abs (var a var-a))
                           (calcFunc-abs (var b var-b))))
     :doc "The magnitude of a quotient is the quotient of the magnitudes."
     :vars ((a . "numerator") (b . "nonzero denominator")))
    (:name "triangle-inequality"
     :title "Triangle inequality"
     :category "Algebra — Absolute value"
     :expr (calcFunc-leq (calcFunc-abs (+ (var a var-a) (var b var-b)))
                         (+ (calcFunc-abs (var a var-a))
                            (calcFunc-abs (var b var-b))))
     :doc "A sum is never longer than its parts laid end to end."
     :vars ((a . "first term") (b . "second term")))
    (:name "reverse-triangle-inequality"
     :title "Reverse triangle inequality"
     :category "Algebra — Absolute value"
     :expr (calcFunc-leq (calcFunc-abs (- (calcFunc-abs (var a var-a))
                                          (calcFunc-abs (var b var-b))))
                         (calcFunc-abs (- (var a var-a) (var b var-b))))
     :doc "Magnitudes differ by no more than the distance between the numbers."
     :vars ((a . "first term") (b . "second term")))
    (:name "absolute-value-equation"
     :title "Absolute value equation"
     :category "Algebra — Absolute value"
     :expr (calcFunc-lor (calcFunc-eq (var x var-x) (var a var-a))
                         (calcFunc-eq (var x var-x) (neg (var a var-a))))
     :doc "What abs(x) = a splits into, for a nonnegative."
     :vars ((x . "the unknown") (a . "nonnegative number"))
     :examples ("abs(x - 1) = 5 gives x = 6 or x = -4."))
    (:name "absolute-value-less-than"
     :title "Absolute value less than"
     :category "Algebra — Absolute value"
     :expr (calcFunc-land (calcFunc-lt (neg (var a var-a)) (var x var-x))
                          (calcFunc-lt (var x var-x) (var a var-a)))
     :doc "What abs(x) < a splits into: a band around zero."
     :vars ((x . "the unknown") (a . "positive number")))
    (:name "absolute-value-greater-than"
     :title "Absolute value greater than"
     :category "Algebra — Absolute value"
     :expr (calcFunc-lor (calcFunc-lt (var x var-x) (neg (var a var-a)))
                         (calcFunc-gt (var x var-x) (var a var-a)))
     :doc "What abs(x) > a splits into: everything outside the band."
     :vars ((x . "the unknown") (a . "positive number")))
    (:name "distance-between-two-numbers"
     :title "Distance between two numbers"
     :category "Algebra — Absolute value"
     :expr (calcFunc-eq (calcFunc-abs (- (var x var-x) (var y var-y)))
                        (calcFunc-abs (- (var y var-y) (var x var-x))))
     :doc "Distance on the line, measured from either end."
     :vars ((x . "first number") (y . "second number")))
    (:name "cosecant-as-a-reciprocal"
     :title "Cosecant as a reciprocal"
     :category "Trigonometry — Reciprocal and quotient"
     :expr (calcFunc-eq (calcFunc-csc (var x var-x))
                        (/ 1 (calcFunc-sin (var x var-x))))
     :doc "Cosecant is the reciprocal of sine."
     :vars ((x . "any angle with sin(x) not 0")))
    (:name "secant-as-a-reciprocal"
     :title "Secant as a reciprocal"
     :category "Trigonometry — Reciprocal and quotient"
     :expr (calcFunc-eq (calcFunc-sec (var x var-x))
                        (/ 1 (calcFunc-cos (var x var-x))))
     :doc "Secant is the reciprocal of cosine."
     :vars ((x . "any angle with cos(x) not 0")))
    (:name "cotangent-as-a-reciprocal"
     :title "Cotangent as a reciprocal"
     :category "Trigonometry — Reciprocal and quotient"
     :expr (calcFunc-eq (calcFunc-cot (var x var-x))
                        (/ 1 (calcFunc-tan (var x var-x))))
     :doc "Cotangent is the reciprocal of tangent."
     :vars ((x . "any angle with tan(x) not 0")))
    (:name "tangent-as-a-quotient"
     :title "Tangent as a quotient"
     :category "Trigonometry — Reciprocal and quotient"
     :expr (calcFunc-eq (calcFunc-tan (var x var-x))
                        (/ (calcFunc-sin (var x var-x))
                           (calcFunc-cos (var x var-x))))
     :doc "Tangent is sine over cosine."
     :vars ((x . "any angle with cos(x) not 0")))
    (:name "cotangent-as-a-quotient"
     :title "Cotangent as a quotient"
     :category "Trigonometry — Reciprocal and quotient"
     :expr (calcFunc-eq (calcFunc-cot (var x var-x))
                        (/ (calcFunc-cos (var x var-x))
                           (calcFunc-sin (var x var-x))))
     :doc "Cotangent is cosine over sine."
     :vars ((x . "any angle with sin(x) not 0")))
    (:name "pythagorean-identity"
     :title "Pythagorean identity"
     :category "Trigonometry — Pythagorean identities"
     :expr (calcFunc-eq (+ (^ (calcFunc-sin (var x var-x)) 2)
                           (^ (calcFunc-cos (var x var-x)) 2))
                        1)
     :doc "Pythagoras on the unit circle, where the two legs are sine and cosine."
     :vars ((x . "any angle")))
    (:name "pythagorean-identity-for-tangent"
     :title "Pythagorean identity for tangent"
     :category "Trigonometry — Pythagorean identities"
     :expr (calcFunc-eq (+ 1 (^ (calcFunc-tan (var x var-x)) 2))
                        (^ (calcFunc-sec (var x var-x)) 2))
     :doc "The identity divided through by cos(x)^2."
     :vars ((x . "any angle with cos(x) not 0")))
    (:name "pythagorean-identity-for-cotangent"
     :title "Pythagorean identity for cotangent"
     :category "Trigonometry — Pythagorean identities"
     :expr (calcFunc-eq (+ 1 (^ (calcFunc-cot (var x var-x)) 2))
                        (^ (calcFunc-csc (var x var-x)) 2))
     :doc "The identity divided through by sin(x)^2."
     :vars ((x . "any angle with sin(x) not 0")))
    (:name "sine-of-a-sum"
     :title "Sine of a sum"
     :category "Trigonometry — Angle sum and difference"
     :expr (calcFunc-eq (calcFunc-sin (+ (var a var-a) (var b var-b)))
                        (+ (* (calcFunc-sin (var a var-a))
                              (calcFunc-cos (var b var-b)))
                           (* (calcFunc-cos (var a var-a))
                              (calcFunc-sin (var b var-b)))))
     :doc "Sine of a sum, in the sines and cosines of the parts."
     :vars ((a . "first angle") (b . "second angle")))
    (:name "sine-of-a-difference"
     :title "Sine of a difference"
     :category "Trigonometry — Angle sum and difference"
     :expr (calcFunc-eq (calcFunc-sin (- (var a var-a) (var b var-b)))
                        (- (* (calcFunc-sin (var a var-a))
                              (calcFunc-cos (var b var-b)))
                           (* (calcFunc-cos (var a var-a))
                              (calcFunc-sin (var b var-b)))))
     :doc "The sum formula with the second angle negated."
     :vars ((a . "first angle") (b . "second angle")))
    (:name "cosine-of-a-sum"
     :title "Cosine of a sum"
     :category "Trigonometry — Angle sum and difference"
     :expr (calcFunc-eq (calcFunc-cos (+ (var a var-a) (var b var-b)))
                        (- (* (calcFunc-cos (var a var-a))
                              (calcFunc-cos (var b var-b)))
                           (* (calcFunc-sin (var a var-a))
                              (calcFunc-sin (var b var-b)))))
     :doc "Cosine of a sum, where the sign flips against the angle."
     :vars ((a . "first angle") (b . "second angle")))
    (:name "cosine-of-a-difference"
     :title "Cosine of a difference"
     :category "Trigonometry — Angle sum and difference"
     :expr (calcFunc-eq (calcFunc-cos (- (var a var-a) (var b var-b)))
                        (+ (* (calcFunc-cos (var a var-a))
                              (calcFunc-cos (var b var-b)))
                           (* (calcFunc-sin (var a var-a))
                              (calcFunc-sin (var b var-b)))))
     :doc "The sum formula with the second angle negated."
     :vars ((a . "first angle") (b . "second angle")))
    (:name "tangent-of-a-sum"
     :title "Tangent of a sum"
     :category "Trigonometry — Angle sum and difference"
     :expr (calcFunc-eq (calcFunc-tan (+ (var a var-a) (var b var-b)))
                        (/ (+ (calcFunc-tan (var a var-a))
                              (calcFunc-tan (var b var-b)))
                           (- 1
                              (* (calcFunc-tan (var a var-a))
                                 (calcFunc-tan (var b var-b))))))
     :doc "Tangent of a sum, in the tangents of the parts."
     :vars ((a . "first angle") (b . "second angle")))
    (:name "tangent-of-a-difference"
     :title "Tangent of a difference"
     :category "Trigonometry — Angle sum and difference"
     :expr (calcFunc-eq (calcFunc-tan (- (var a var-a) (var b var-b)))
                        (/ (- (calcFunc-tan (var a var-a))
                              (calcFunc-tan (var b var-b)))
                           (+ 1
                              (* (calcFunc-tan (var a var-a))
                                 (calcFunc-tan (var b var-b))))))
     :doc "The sum formula with the second angle negated."
     :vars ((a . "first angle") (b . "second angle")))
    (:name "sine-of-a-double-angle"
     :title "Sine of a double angle"
     :category "Trigonometry — Double angle"
     :expr (calcFunc-eq (calcFunc-sin (* 2 (var x var-x)))
                        (* 2
                           (* (calcFunc-sin (var x var-x))
                              (calcFunc-cos (var x var-x)))))
     :doc "The sum formula with both angles the same."
     :vars ((x . "any angle")))
    (:name "cosine-of-a-double-angle"
     :title "Cosine of a double angle"
     :category "Trigonometry — Double angle"
     :expr (calcFunc-eq (calcFunc-cos (* 2 (var x var-x)))
                        (- (^ (calcFunc-cos (var x var-x)) 2)
                           (^ (calcFunc-sin (var x var-x)) 2)))
     :doc "The sum formula with both angles the same."
     :vars ((x . "any angle")))
    (:name "cosine-of-a-double-angle-in-sine"
     :title "Cosine of a double angle, in sine"
     :category "Trigonometry — Double angle"
     :expr (calcFunc-eq (calcFunc-cos (* 2 (var x var-x)))
                        (- 1 (* 2 (^ (calcFunc-sin (var x var-x)) 2))))
     :doc "The same, with the cosine traded away by the Pythagorean identity."
     :vars ((x . "any angle")))
    (:name "cosine-of-a-double-angle-in-cosine"
     :title "Cosine of a double angle, in cosine"
     :category "Trigonometry — Double angle"
     :expr (calcFunc-eq (calcFunc-cos (* 2 (var x var-x)))
                        (- (* 2 (^ (calcFunc-cos (var x var-x)) 2)) 1))
     :doc "The same, with the sine traded away instead."
     :vars ((x . "any angle")))
    (:name "tangent-of-a-double-angle"
     :title "Tangent of a double angle"
     :category "Trigonometry — Double angle"
     :expr (calcFunc-eq (calcFunc-tan (* 2 (var x var-x)))
                        (/ (* 2 (calcFunc-tan (var x var-x)))
                           (- 1 (^ (calcFunc-tan (var x var-x)) 2))))
     :doc "The sum formula for tangent with both angles the same."
     :vars ((x . "any angle with tan(x)^2 not 1")))
    (:name "sine-of-a-half-angle-squared"
     :title "Sine of a half angle, squared"
     :category "Trigonometry — Half angle"
     :expr (calcFunc-eq (^ (calcFunc-sin (/ (var x var-x) 2)) 2)
                        (/ (- 1 (calcFunc-cos (var x var-x))) 2))
     :doc "Squared, so no sign to choose; the root takes the quadrant's sign."
     :vars ((x . "any angle")))
    (:name "cosine-of-a-half-angle-squared"
     :title "Cosine of a half angle, squared"
     :category "Trigonometry — Half angle"
     :expr (calcFunc-eq (^ (calcFunc-cos (/ (var x var-x) 2)) 2)
                        (/ (+ 1 (calcFunc-cos (var x var-x))) 2))
     :doc "Squared, so no sign to choose; the root takes the quadrant's sign."
     :vars ((x . "any angle")))
    (:name "tangent-of-a-half-angle"
     :title "Tangent of a half angle"
     :category "Trigonometry — Half angle"
     :expr (calcFunc-eq (calcFunc-tan (/ (var x var-x) 2))
                        (/ (- 1 (calcFunc-cos (var x var-x)))
                           (calcFunc-sin (var x var-x))))
     :doc "No sign to choose here: the quotient carries it."
     :vars ((x . "any angle with sin(x) not 0")))
    (:name "tangent-of-a-half-angle-by-sine"
     :title "Tangent of a half angle, by sine"
     :category "Trigonometry — Half angle"
     :expr (calcFunc-eq (calcFunc-tan (/ (var x var-x) 2))
                        (/ (calcFunc-sin (var x var-x))
                           (+ 1 (calcFunc-cos (var x var-x)))))
     :doc "The same value, useful when cos(x) is not near -1."
     :vars ((x . "any angle with cos(x) not -1")))
    (:name "sine-is-odd"
     :title "Sine is odd"
     :category "Trigonometry — Even and odd"
     :expr (calcFunc-eq (calcFunc-sin (neg (var x var-x)))
                        (neg (calcFunc-sin (var x var-x))))
     :doc "Negating the angle negates the sine."
     :vars ((x . "any angle")))
    (:name "cosine-is-even"
     :title "Cosine is even"
     :category "Trigonometry — Even and odd"
     :expr (calcFunc-eq (calcFunc-cos (neg (var x var-x)))
                        (calcFunc-cos (var x var-x)))
     :doc "Negating the angle leaves the cosine alone."
     :vars ((x . "any angle")))
    (:name "tangent-is-odd"
     :title "Tangent is odd"
     :category "Trigonometry — Even and odd"
     :expr (calcFunc-eq (calcFunc-tan (neg (var x var-x)))
                        (neg (calcFunc-tan (var x var-x))))
     :doc "Negating the angle negates the tangent."
     :vars ((x . "any angle with cos(x) not 0"))))
  "The formulas maf ships with, in the plist shape of `maf-formulas-user'.
The identities school algebra and trigonometry rest on, and the ones a
rewrite is most often reaching for. They come in categories the menu
sorts by name and narrows to one at a time: the properties of real
numbers, absolute value, exponents, fractions, logarithms, quadratic
equations and radicals, then the trig identities in six groups of their
own. The properties of real numbers calc applies in its own default
simplifications, so those earn their place by being readable and by
naming what a rewrite is doing rather than by teaching calc anything;
the rest calc will not supply on its own.

An equation cannot carry its own conditions — that x is positive, that
a base is not 1, that a denominator is nonzero — so each is named in
:vars and, where it matters, in :doc. Rewriting with one of these does
not check them; that is the reader\'s job, as it is on paper.

Two formulas that would want a ± are split in two instead, one entry
per sign — the quadratic formula\'s roots — or given squared, leaving
the sign to the quadrant, as the half-angle sine and cosine are.

Package data rather than a preference, so it is a `defvar' and not a
`defcustom'; set it to nil in your init to keep only your own.")

(defun maf-formulas--all ()
  "Every formula: the set maf ships with, then your own.
`maf-formulas-file' is consulted the first time; the file, when present,
populates `maf-formulas-user', and after that the variable is the single
source for yours, so runtime additions to it persist.
`maf-formulas-builtin' leads because yours follow: a formula of yours
sharing a :name registers its `var-eq-' variable last, and so wins."
  (unless maf-formulas--loaded
    (setq maf-formulas--loaded t)
    (when (and maf-formulas-file (file-exists-p maf-formulas-file))
      (load (expand-file-name maf-formulas-file) nil t)))
  (append maf-formulas-builtin maf-formulas-user))

(defun maf-formulas--title (f)
  "Menu title for formula F, derived from its name when :title is absent."
  (or (plist-get f :title)
      (let ((s (replace-regexp-in-string "-" " " (or (plist-get f :name) "formula"))))
        (concat (upcase (substring s 0 1)) (substring s 1)))))

(defun maf-formulas--category (f)
  "Category for formula F, a default when :category is absent."
  (or (plist-get f :category) "Uncategorized"))

;;; The calc var-eq-<name> registration (single source of truth)

(defun maf-formulas--register-vars ()
  "Register each formula as a calc `var-eq-<name>' variable."
  (dolist (f (maf-formulas--all))
    (when-let ((name (plist-get f :name)))
      (set (intern (concat "var-eq-" name)) (plist-get f :expr)))))

(defun maf-formulas--unregister-vars ()
  "Unbind the `var-eq-<name>' variables this module registered."
  (dolist (f (maf-formulas--all))
    (when-let ((name (plist-get f :name)))
      (makunbound (intern (concat "var-eq-" name))))))

;;; Rendering

(defvar-local maf-formulas--query ""
  "Current filter string narrowing the formula menu, or empty.")

(defvar-local maf-formulas--group nil
  "Category the menu is narrowed to, or nil for every group.
Set by RET on a group header (`maf-formulas-filter-group'), and cleared
by RET on that header again, by `maf-formulas-clear-filter', or by a
filter — which searches the whole list, so it lifts this. It sits
beside `maf-formulas--query' rather than folding into it: the query is
words matched across titles, categories and variables, where this
picks one group out by name — including \"Recent\", which no query can
name, that group being a shortcut rather than a category.")

(defvar-local maf-formulas--group-query nil
  "Filter string set aside while a group narrowing is in effect, or nil.
Narrowing to a group shows the group whole, so the filter that was in
force is lifted rather than compounded — asking for a group is asking
for the group, not for the part of it that survived what was typed.
It is kept here so RET on the header again puts back the filtered list
it was pressed from. The two narrowings are never in force together:
filtering from inside a group leaves the group, taking this with it.")

(defvar-local maf-formulas--collapsed nil
  "Categories folded away to their headers, or nil for none.
A third narrowing, and the only one that is not a narrowing of what
the list holds: the folded groups are still in it, still counted in
their headers, and a fold is undone where it was made rather than
from a key that clears the lot. What it buys is the whole list read
as its group names, which is how a list this long is navigated —
glance down the headers, unfold the one wanted.

Held by category name, the same string `maf-formulas--groups' keys a
group by, so a fold survives the re-renders a filter and a group
narrowing cause. A name no longer in the list simply never matches.")

(defvar-local maf-formulas--searching nil
  "Non-nil when the last render ran under a filter.
Lets `maf-formulas--sync-collapse' tell entering a search from being
in one, which is the difference between unfolding for the results and
overruling a fold the user has just made among them.")

(defun maf-formulas--sync-collapse ()
  "Unfold every group on entering a search, before a render reads the folds.
A search that left its groups folded would hide the very rows it
found — there would be no way to see the results — so starting one
flips the toggle to shown.

Once. Not on every render a filter causes, which would leave the fold
keys dead for as long as a filter was in force: a filtered list is
still a list of groups, still worth reading as its headers when the
search casts wide, and folding one away is the user saying so about
the results in front of them. Inside a search the folds are theirs.

And the toggle stays flipped afterwards. The folds are dropped rather
than set aside: what a search leaves behind is the list it found, open
and readable, and a list that re-folded itself the moment the filter
lifted would take the results away again from a user still reading
them. Folding is one key away when it is wanted.

Called from `maf-formulas--render', so every path that sets a query —
filtering, clearing, abandoning a filter, stepping into a group — is
covered by the one rule, none of them having to know it."
  (let ((searching (not (string-empty-p maf-formulas--query))))
    (when (and searching (not maf-formulas--searching))
      (setq maf-formulas--collapsed nil))
    (setq maf-formulas--searching searching)))

(defun maf-formulas--collapsed-p (group)
  "Non-nil when GROUP is folded away to its header."
  (and (member group maf-formulas--collapsed) t))

(defvar maf-formulas--recent nil
  "Formulas inserted this session, most recent first.
A plain variable, so the list dies with the session — recency is a
convenience for the sitting, not something to carry between them.")

(defun maf-formulas--record-recent (f)
  "Remember F as the most recently inserted formula."
  (when (> maf-formulas-recent-max 0)
    (setq maf-formulas--recent
          (cons f (seq-take (delq f maf-formulas--recent)
                            (1- maf-formulas-recent-max))))))

(defun maf-formulas--matches-p (f query)
  "Non-nil if formula F matches QUERY (title, category, or a variable).
QUERY is read as words, not as one string: each whitespace-separated
word has to turn up somewhere in the formula — its title, its category
or one of its variables — but they need not turn up together, in one
field, or in the order typed. \"power rule\" reaches a rule titled
\"Rule for powers\" as readily as one titled \"Power rule\", and each
further word narrows what the ones before it left."
  (let ((fields (append (list (downcase (maf-formulas--title f))
                              (downcase (maf-formulas--category f)))
                        (mapcar (lambda (v)
                                  (downcase (format "%s %s" (car v) (cdr v))))
                                (plist-get f :vars)))))
    (cl-every (lambda (word)
                (cl-some (lambda (field) (string-search word field)) fields))
              (split-string (downcase query) nil t))))

(defun maf-formulas--groups ()
  "The menu's groups, an alist of (CATEGORY . FORMULAS).
Categories come alphabetically, each holding the formulas matching the
current query. With no query, the recently-inserted group leads when it
has any, so what you reached for last is where the cursor already is.
Filtering omits that shortcut group; matching recent formulas remain
listed under their own categories.

`maf-formulas--group' narrows to the one group it names — \"Recent\"
included, which a query cannot reach on its own. The two narrowings
are never in force at once: narrowing to a group sets the query aside
so the group comes up whole, and filtering lifts the group so the
search runs over every formula."
  (let* ((all (maf-formulas--all))
         (match (lambda (f) (maf-formulas--matches-p f maf-formulas--query)))
         (group maf-formulas--group)
         (recent-only (equal group maf-formulas--recent-category))
         ;; Recents are held by identity, so formulas dropped from
         ;; `maf-formulas-user' since (a reloaded file, say) fall out.
         (recent (and (or recent-only
                          (and (null group) (string-empty-p maf-formulas--query)))
                      (seq-filter (lambda (f) (and (memq f all) (funcall match f)))
                                  maf-formulas--recent)))
         (groups nil))
    (dolist (f (seq-filter match all))
      (let* ((cat (maf-formulas--category f))
             (cell (assoc cat groups)))
        (if cell
            (setcdr cell (cons f (cdr cell)))
          (push (list cat f) groups))))
    (setq groups (sort (mapcar (lambda (g) (cons (car g) (nreverse (cdr g)))) groups)
                       (lambda (a b) (string< (car a) (car b)))))
    (when group
      (setq groups (if recent-only
                       nil
                     (seq-filter (lambda (g) (equal (car g) group)) groups))))
    (if recent
        (cons (cons maf-formulas--recent-category recent) groups)
      groups)))

(defun maf-formulas--oneline (expr)
  "Render EXPR as a single normal-language line, for the list column."
  (let ((s (ignore-errors (let ((calc-language nil)) (math-format-value expr)))))
    (if s (replace-regexp-in-string "\n" " " s) "")))

;; Two of the detail pane's variables live up here with the renderer,
;; which consults them, rather than with the pane: forward references
;; from `maf-formulas--render' would otherwise be to free variables.

(defvar-local maf-formulas--detail-line nil
  "Beginning of the line the detail pane is currently rendered for, or nil.
`maf-formulas--detail-on-move' compares point against it, so the pane
re-renders when point reaches another formula and not on every command
that leaves it where it was.")

;; Not `--detail-state', its name when it was `defvar-local': the
;; buffer-local marking survives a reload, so going global took a new
;; name for live sessions to actually get a global.
(defvar maf-formulas--pane-state 'follow
  "How the detail pane is open: `frozen', `follow', or nil for closed.
`follow' is `maf-formulas-toggle-detail' (\\`O'): the pane re-renders
for each formula point reaches — the default, so the menu opens with
the pane already following. `frozen' is `maf-formulas-show-detail'
(\\`o') with follow off: the pane shows the one formula it was opened
on, and moving off that line dismisses it. Global where the pane's
other bookkeeping is buffer-local: the state is the session's choice,
not the buffer's, so quitting the menu and opening it again brings
the pane back the way it was left.")

(defun maf-formulas--header-line ()
  "The menu's header line: the key legend, led by the narrowing in effect.
The legend reads like dial's controls line in *maf-options*: keys wear
`help-key-binding', entries set apart by spaces alone, and the band
itself takes `dial-controls' (the mode remaps `header-line' to it).
The \"O follows\" entry renders in gold — `warning's, the one gold
across maf's buffers — while the pane is following, so the legend
doubles as the toggle's indicator.

A narrowing takes the place of the buffer's name at the head of the
band, and adds the key that lifts it; the keys themselves stay put.
The legend is what a narrowed list is read with — `o', `a' and `D' all
still apply to the rows on show — so trading it for a line that only
named the filter took the legend away exactly when it was in use."
  (let* ((entry (lambda (key verb)
                  (concat (propertize key 'face 'help-key-binding) " " verb)))
         (state (delq nil
                      (list (when maf-formulas--group
                              (concat "group: "
                                      (propertize maf-formulas--group 'face 'warning)))
                            (unless (string-empty-p maf-formulas--query)
                              (concat "filter: "
                                      (propertize maf-formulas--query 'face 'warning)))))))
    (mapconcat #'identity
               (delq nil
                     (list (if state (mapconcat #'identity state "  ") "maf-formulas")
                           (funcall entry "RET" "inserts")
                           (funcall entry "/" "filters")
                           (funcall entry "TAB" "folds")
                           ;; Only while something is narrowed: the key is
                           ;; noise until there is something for it to clear.
                           (when state (funcall entry "c" "clears"))
                           (funcall entry "o" "details")
                           (if (eq maf-formulas--pane-state 'follow)
                               (propertize "O follows" 'face 'warning)
                             (funcall entry "O" "follows"))
                           (funcall entry "a/i" "adds recent")
                           (funcall entry "D" "deletes recent")
                           (funcall entry "q" "quits")))
               "   ")))

(defun maf-formulas--refresh-header ()
  "Recompute the header line, for a state change without a re-render."
  (setq header-line-format (maf-formulas--header-line))
  (force-mode-line-update))

(defun maf-formulas--render ()
  "Render the categorized list: each formula beside its one-line form.
Groups are separated by a blank line. A folded group renders as its
header alone, wearing the count of what it holds so the list still
says how much is down there; consecutive folded groups drop the blank
between them, the fold view being worth reading in one glance.

The header carries its category in a `maf-formula-group' text
property rather than being read back off the line, the count having
made the line and the name two different strings."
  (maf-formulas--sync-collapse)
  (let* ((inhibit-read-only t) (first t) (prev-folded nil)
         (groups (maf-formulas--groups))
         ;; Folded rows are not drawn, so they are no reason to widen
         ;; the column the drawn ones align on.
         (fs (apply #'append (mapcar (lambda (g)
                                       (unless (maf-formulas--collapsed-p (car g))
                                         (cdr g)))
                                     groups))))
    (erase-buffer)
    (setq header-line-format (maf-formulas--header-line))
    (let ((w (apply #'max 0 (mapcar (lambda (f) (length (maf-formulas--title f))) fs))))
      (dolist (g groups)
        (let ((folded (maf-formulas--collapsed-p (car g)))
              hstart)
          (unless (or first (and folded prev-folded))
            (insert "\n"))             ; blank line above each group
          (setq first nil prev-folded folded hstart (point))
          (insert (propertize (car g) 'face
                              (if (equal (car g) maf-formulas--recent-category)
                                  'maf-formulas-recent
                                'maf-formulas-category)))
          (when folded
            (insert " " (propertize (format "(%d)" (length (cdr g)))
                                    'face 'maf-formulas-leader)))
          (insert "\n")
          (put-text-property hstart (point) 'maf-formula-group (car g)))
        (dolist (f (unless (maf-formulas--collapsed-p (car g)) (cdr g)))
          (let* ((start (point))
                 (title (maf-formulas--title f))
                 ;; A dotted leader bridges the gap to the aligned formula
                 ;; column so the eye can track a short title across.
                 (leader (make-string (+ 1 (- w (length title))) ?.)))
            (insert "  " (propertize title 'face 'maf-formulas-title) " "
                    (propertize leader 'face 'maf-formulas-leader) " "
                    (propertize (maf-formulas--oneline (plist-get f :expr)) 'face 'maf-formulas-form)
                    "\n")
            (put-text-property start (point) 'maf-formula f)))))
    (goto-char (point-min))
    (while (and (not (eobp)) (not (get-text-property (point) 'maf-formula)))
      (forward-line 1))
    (maf-formulas--item-start)
    ;; A re-render changes what every line means, so a following pane
    ;; re-renders with it, for whatever point landed on. A frozen one
    ;; holds its formula: the filter it was narrowed by is no reason to
    ;; drop what the user put up to read.
    (when (eq maf-formulas--pane-state 'follow)
      (setq maf-formulas--detail-line (line-beginning-position))
      (maf-formulas--update-detail))))

;;; The detail pane

(defvar-local maf-formulas--detail-dir nil
  "Direction the detail pane was last split off in, `right' or `below'.
Chosen by `maf-formulas--detail-direction' when the pane opens; the
renderer consults it to know whether the pane's height is its own to
shrink.")

(defvar-local maf-formulas--detail-height nil
  "Height the detail pane has grown to while open, or nil when closed.
A floor for `maf-formulas--fit-detail', so the pane never shrinks
under a following pane's point.")

(defun maf-formulas--fill (text width)
  "TEXT filled to WIDTH and indented two spaces, for the description.
Only the description wraps: the Big rendering and the variable lines
keep their exact layout, but prose should bend to the pane."
  (with-temp-buffer
    (insert text)
    ;; Two columns for the indent, and one more spare: on a tty the
    ;; window's last column holds the truncation glyph, so a line of
    ;; exactly the pane's width still shows as `$'-truncated.
    (let ((fill-column (max 20 (- width 3))))
      (fill-region (point-min) (point-max)))
    (mapconcat (lambda (l) (concat "  " l))
               (split-string (buffer-string) "\n") "\n")))

(defun maf-formulas--color-vars (big vars)
  "BIG, the Big rendering, with VARS' names in `maf-formulas-var'.
The same face the variable wears in the list of meanings below, so
the eye can carry a symbol in the formula down to what it stands for.
Big display hands back a laid-out string rather than a tree, so the
names are found by matching text: a name counts only where it is not
part of a longer word, leaving the `r' in `sqrt' the formula's own
color."
  (let ((s (copy-sequence big)))
    (dolist (v vars s)
      (let ((re (concat "\\(?:^\\|[^[:alnum:]_]\\)\\("
                        (regexp-quote (format "%s" (car v)))
                        "\\)\\(?:$\\|[^[:alnum:]_]\\)"))
            (from 0))
        ;; Resume from the end of the name, not of the whole match: the
        ;; character after it may be the one that bounds the next
        ;; occurrence, as the `+' does between the two `a's in "a+a".
        (while (string-match re s from)
          (put-text-property (match-beginning 1) (match-end 1)
                             'face 'maf-formulas-var s)
          (setq from (match-end 1)))))))

(defun maf-formulas--detail-string (f width)
  "Detail text for F: title, rendered formula, description, variable meanings.
WIDTH is the pane's width in columns; the description fills to it.
The formula is typeset while the pretty module is on — the same ask
the preview panel makes, through `maf-preview-render-function' — and
drawn in Big otherwise, or whenever the renderer answers nil (no
graphics, or a formula LaTeX cannot write). A formula carrying
:display-expr renders that form instead, both typeset and Big — a
place for notation the working :expr should not carry, the degree
unit on an angle sum the common case — while RET still pushes :expr."
  (let* ((expr (or (plist-get f :display-expr) (plist-get f :expr)))
         (doc (plist-get f :doc))
         (examples (plist-get f :examples))
         (vars (plist-get f :vars))
         (pretty (and (display-graphic-p)
                      (bound-and-true-p maf-preview-render-function)
                      (ignore-errors (funcall maf-preview-render-function expr))))
         (big (unless pretty
                (ignore-errors (let ((calc-language 'big)) (math-format-value expr))))))
    (concat
     "\n  " (propertize (maf-formulas--title f) 'face 'maf-formulas-category) "\n\n"
     (if pretty
         ;; A thin box frames the typeset formula, with a margin added
         ;; to this copy of the image so the ink sits well clear of the
         ;; frame — the panel's own rendering is left as it came.
         (concat "  " (propertize
                       " "
                       'display (append (get-text-property 0 'display pretty)
                                        '(:margin 8))
                       'face '(:box (:line-width 1 :color "gray40"))))
       (maf-formulas--color-vars
        (propertize
         (mapconcat (lambda (l) (concat "  " l)) (split-string (or big "") "\n") "\n")
         'face 'maf-formulas-form)
        vars))
     "\n"
     (when doc
       (concat "\n"
               (propertize (maf-formulas--fill doc width) 'face 'maf-formulas-title)
               "\n"))
     (when vars
       (concat "\n"
               (mapconcat (lambda (v)
                            (concat "  "
                                    (propertize (format "%s" (car v)) 'face 'maf-formulas-var)
                                    (propertize (format " = %s" (cdr v)) 'face 'maf-formulas-title)))
                          vars "\n")
               "\n"))
     (when examples
       (concat "\n"
               (mapconcat (lambda (e) (concat "  " (propertize (concat "e.g. " e) 'face 'shadow)))
                          examples "\n")
               "\n")))))

(defun maf-formulas--detail-direction ()
  "Where to split the detail pane off when no window can be borrowed.
`right' when there is width to spare, else `below'. The menu's own
window is what gets split, so the test is on its width, not the
frame's: a menu already sharing the frame with calc has less to give
away than the frame size suggests."
  (if (>= (window-body-width) (* 2 maf-formulas-detail-min-width))
      'right
    'below))

;; The detail pane's window-borrowing action now lives in core
;; (`maf--display-borrowing-window'): the saved-stacks preview wants
;; the same behavior, so the two share one implementation.

(defun maf-formulas--split-p (win)
  "Non-nil when WIN was made for the detail pane rather than borrowed.
`display-buffer' records that in the window's `quit-restore' parameter:
a leading `window' means it created the window."
  (eq (car-safe (window-parameter win 'quit-restore)) 'window))

(defun maf-formulas--fit-detail (win)
  "Fit the detail pane WIN to the height its text needs.
Only for a pane split off below: there the height is room taken from
the list, so the pane asks for no more than it uses — a borrowed
window keeps whatever size its own buffer had. Capped at half the
frame so a long description cannot swallow the menu. Once open the
pane only ever grows: a following pane re-renders formula by formula,
and shrinking back on the short ones would leave the list jumping
under the cursor on every move."
  (when (and (eq maf-formulas--detail-dir 'below)
             (maf-formulas--split-p win))
    (let ((max-h (max 6 (/ (frame-height) 2))))
      (fit-window-to-buffer win max-h
                            (min max-h (or maf-formulas--detail-height 4)))
      (setq maf-formulas--detail-height (window-height win)))))

(defun maf-formulas--update-detail ()
  "Render the formula at point into the detail buffer.
The detail lives in its own buffer, so showing it never shifts the
list's own layout."
  (let ((f (or (get-text-property (line-beginning-position) 'maf-formula)
               ;; On a category header, preview that group's first formula.
               (save-excursion
                 (forward-line 1)
                 (while (and (not (eobp))
                             (not (get-text-property (line-beginning-position)
                                                     'maf-formula)))
                   (forward-line 1))
                 (get-text-property (line-beginning-position) 'maf-formula))))
        (dbuf (get-buffer maf-formulas--detail-buffer)))
    (when dbuf
      ;; The pane's real width when it is showing, else a stock fill.
      ;; `window-body-width' counts the columns line numbers occupy, so
      ;; subtract those or the fill overshoots by their width.
      (let ((width (let ((win (get-buffer-window dbuf)))
                     (if win
                         (- (window-body-width win)
                            (with-selected-window win
                              (ceiling (line-number-display-width 'columns))))
                       fill-column))))
        (with-current-buffer dbuf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (when f (insert (maf-formulas--detail-string f width)))
            (goto-char (point-min))))
        (when-let ((win (get-buffer-window dbuf)))
          (maf-formulas--fit-detail win))))))

(defun maf-formulas-refresh-detail ()
  "Re-render the detail pane, if one is on screen.
For a caller that changed what the pane draws with rather than which
formula it shows: the pretty module's toggle swaps the renderer from
the module menu, and the pane otherwise repaints only when point in
the list reaches another formula."
  (when (get-buffer-window maf-formulas--detail-buffer)
    (when-let ((buf (get-buffer "*maf-formulas*")))
      (with-current-buffer buf
        (maf-formulas--update-detail)))))

(defun maf-formulas--close-detail ()
  "Put the detail pane's window back the way it was, when one is showing.
`quit-restore-window' undoes exactly what `display-buffer' did: the
window goes away if the pane made one, and the buffer it borrowed —
calc, normally — comes back if it did not."
  (let ((win (get-buffer-window maf-formulas--detail-buffer)))
    (setq maf-formulas--detail-height nil)
    (when (and win (not (eq win (selected-window))))
      (quit-restore-window win 'bury))))

(defun maf-formulas--detail-on-move ()
  "React to point's moves with the detail pane; on `post-command-hook'.
The pane reacts only to a line other than the one rendered, so the
commands that leave point where it was cost nothing. What it does
there is the `O' flag's call. Following, it re-renders — or comes
back, when \\<maf-formulas-mode-map>\\[maf-formulas-show-detail] hid it for a peek at what its window held. Frozen
\(follow off), the pane is dismissed instead, the window handed back:
the details were for the formula it was opened on, and point has
moved on."
  (unless (eq (line-beginning-position) maf-formulas--detail-line)
    (pcase maf-formulas--pane-state
      ('follow
       (if (get-buffer-window maf-formulas--detail-buffer)
           (progn (setq maf-formulas--detail-line (line-beginning-position))
                  (maf-formulas--update-detail))
         (maf-formulas--open-detail)))
      ('frozen
       (setq maf-formulas--pane-state nil
             maf-formulas--detail-line nil)
       (maf-formulas--close-detail)))))

(defun maf-formulas-keyboard-quit ()
  "Close the detail pane, then quit as \\[keyboard-quit] does.
On the menu's \\`C-g': the usual dismiss gesture shuts the pane whichever
way it was opened, so it takes neither a matching key nor leaving the menu."
  (interactive)
  (setq maf-formulas--detail-line nil
        maf-formulas--pane-state nil)
  (maf-formulas--close-detail)
  (maf-formulas--refresh-header)
  (keyboard-quit))

(defun maf-formulas--open-detail ()
  "Display the detail pane and render the formula at point into it."
  (let ((dbuf (get-buffer-create maf-formulas--detail-buffer)))
    (with-current-buffer dbuf
      (unless (derived-mode-p 'special-mode) (special-mode))
      (setq buffer-read-only t))
    ;; Borrow a window if the frame has one to lend (calc's, usually),
    ;; keeping it where it already is on a re-show; failing that, split
    ;; whichever way leaves the detail the better shape. Displayed
    ;; before rendering, so the description fills to the pane's real
    ;; width.
    (setq maf-formulas--detail-dir (maf-formulas--detail-direction))
    (display-buffer dbuf `((display-buffer-reuse-window
                            maf--display-borrowing-window
                            display-buffer-in-direction)
                           (direction . ,maf-formulas--detail-dir)
                           (inhibit-same-window . t)))
    (maf-formulas--update-detail)
    (setq maf-formulas--detail-line (line-beginning-position))))

(defun maf-formulas-show-detail ()
  "Show the detail pane, or close a pane that is up — a visibility toggle.
Either way the `O' flag (\\<maf-formulas-mode-map>\\[maf-formulas-toggle-detail]) keeps the say over what happens next.
With follow on, closing is a peek at what the window held — calc's
stack normally — the legend's gold untouched, and the pane returns on
its own the moment point reaches another formula. With follow off,
the pane shows the formula at point and moving off that line
dismisses it again: details on request, where follow makes them a
running commentary. On a category header it shows the group's first
formula."
  (interactive)
  (if (get-buffer-window maf-formulas--detail-buffer)
      (maf-formulas--close-detail)
    (unless maf-formulas--pane-state
      (setq maf-formulas--pane-state 'frozen))
    (maf-formulas--open-detail))
  (maf-formulas--refresh-header))

(defun maf-formulas-toggle-detail ()
  "Open a detail pane that follows point, or close a following one.
Where \\<maf-formulas-mode-map>\\[maf-formulas-show-detail] holds one formula, this re-renders for each formula
point reaches — for reading down a group. Pressed while such a pane is
up it closes it; pressed while \\[maf-formulas-show-detail] holds one, it takes the pane over
and starts following. The choice holds for the session: the menu
reopens with the pane the way this left it."
  (interactive)
  (if (eq maf-formulas--pane-state 'follow)
      (progn (setq maf-formulas--pane-state nil
                   maf-formulas--detail-line nil)
             (maf-formulas--close-detail))
    (setq maf-formulas--pane-state 'follow)
    (maf-formulas--open-detail))
  (maf-formulas--refresh-header))

;;; Commands

(defun maf-formulas-select ()
  "Act on the line at point: insert the formula, or narrow to the group.
RET does the obvious thing for whatever the line holds — pushing the
formula onto the stack (`maf-formulas-insert'), or narrowing the menu
to the group whose header it is (`maf-formulas-filter-group'). The
headers are on the way through the list, and the key already under
the finger is the one that means \"this one\"."
  (interactive)
  (if (maf-formulas--group-at-point)
      (maf-formulas-filter-group)
    (maf-formulas-insert)))

(defun maf-formulas-insert ()
  "Push the formula at point onto the calc stack, and quit the menu."
  (interactive)
  (let ((f (get-text-property (line-beginning-position) 'maf-formula)))
    (unless f (user-error "No formula on this line"))
    (let ((buf (or (maf--find-calc-buffer) (get-buffer "*Calculator*"))))
      (unless buf (user-error "No calc buffer found"))
      (with-current-buffer buf
        (calc-wrapper
         (calc-pop-push-record-list 0 "frml" (list (copy-tree (plist-get f :expr)))
                                    1 (list nil))))
      (maf-formulas--record-recent f)
      (message "Inserted: %s" (maf-formulas--title f))
      (maf-formulas-quit))))

(defun maf-formulas--recent-line-p ()
  "Non-nil when the line at point lies in the \"Recent\" group.
A recent formula is listed twice — here and under its own category —
so what matters is which copy point is on: the nearest header above
decides."
  (let* ((p (line-beginning-position))
         (header (car (last (seq-filter (lambda (s) (<= s p))
                                        (maf-formulas--group-starts))))))
    (and header
         (equal (save-excursion
                  (goto-char header)
                  (maf-formulas--group-at-point))
                maf-formulas--recent-category))))

(defun maf-formulas--goto-formula (f recent)
  "Put point on the row for formula F, RECENT choosing which copy.
A formula in the \"Recent\" group is listed twice — there and under
its own category — so a re-render leaves two rows to land on. With
RECENT non-nil the group's copy is taken, otherwise the category's.
When the wanted copy is not on screen the other serves, and when
neither is, point stays where the render left it."
  (let (wanted other)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (eq (get-text-property (line-beginning-position) 'maf-formula) f)
          (if (eq (and (maf-formulas--recent-line-p) t) (and recent t))
              (unless wanted (setq wanted (line-beginning-position)))
            (unless other (setq other (line-beginning-position)))))
        (forward-line 1)))
    (when-let ((pos (or wanted other)))
      (goto-char pos)
      (maf-formulas--item-start))))

(defun maf-formulas-add-recent ()
  "Add the formula at point to the \"Recent\" group, without inserting it.
The group is otherwise written only by inserting a formula, which
leaves the menu; this marks one as reached-for and stays put, so a
handful can be gathered in one visit and found at the top of the list
next time. A formula already in the group moves back to its head.

The narrowing is no obstacle: the row under point is what counts, so
a filtered list marks the same way an unfiltered one does. The Recent
group stays hidden until the filter is cleared.

Point keeps its place rather than following the render to the top,
and its copy with it: marking from the group's own line stays there."
  (interactive)
  (let ((f (get-text-property (line-beginning-position) 'maf-formula)))
    (unless f (user-error "No formula on this line"))
    (when (<= maf-formulas-recent-max 0)
      (user-error "The Recent group is turned off (maf-formulas-recent-max)"))
    (let ((recent (maf-formulas--recent-line-p)))
      (maf-formulas--record-recent f)
      (maf-formulas--render)
      (maf-formulas--goto-formula f recent))
    (when (eq maf-formulas--pane-state 'follow)
      (setq maf-formulas--detail-line (line-beginning-position))
      (maf-formulas--update-detail))
    (message "Added to Recent: %s" (maf-formulas--title f))))

(defun maf-formulas-delete-recent ()
  "Drop the entry at point from the \"Recent\" group.
Only a line in that group qualifies: the group is the session's memory
of what was inserted, and this forgets one entry. The formula itself
is untouched, still listed under its own category."
  (interactive)
  (let ((f (get-text-property (line-beginning-position) 'maf-formula)))
    (unless (and f (maf-formulas--recent-line-p))
      (user-error "Not on a Recent entry"))
    (setq maf-formulas--recent (delq f maf-formulas--recent))
    ;; Forgetting the last entry while narrowed to the group leaves the
    ;; narrowing pointing at a group that no longer exists — an empty
    ;; buffer, with the header its only way out. The group is gone, so
    ;; the narrowing to it goes with it.
    (unless maf-formulas--recent
      (when (equal maf-formulas--group maf-formulas--recent-category)
        (setq maf-formulas--group nil)))
    (let ((line (line-number-at-pos)))
      (maf-formulas--render)
      (goto-char (point-min))
      (forward-line (1- line))
      ;; The line may now lie past the shrunken group — or the group may
      ;; be gone entirely — so settle on the nearest formula. A header
      ;; is no landing place here, however the motion keys treat one:
      ;; what was deleted was a row, and a row is what replaces it.
      (unless (get-text-property (line-beginning-position) 'maf-formula)
        (or (maf-formulas--seek-item -1 t)
            (maf-formulas--seek-item 1 t))))
    (message "Removed from Recent: %s" (maf-formulas--title f))))

(defvar maf-formulas--filter-buffer nil
  "Menu buffer being narrowed while the minibuffer reads a filter.
Bound for the dynamic extent of `maf-formulas-filter' only.")

(defvar maf-formulas--filter-touched nil
  "Non-nil once anything has been typed into the filter minibuffer.
The prompt opens empty, but the narrowing in effect holds until the
user actually types: an untouched empty minibuffer means \"nothing
said yet\", not \"show everything\". Bound alongside
`maf-formulas--filter-buffer'.")

(defun maf-formulas--render-visible ()
  "Re-render the current menu buffer with its window selected.
Point and the window's view then move together, as they would had the
user navigated there."
  (let ((win (get-buffer-window (current-buffer))))
    (if win
        (with-selected-window win (maf-formulas--render))
      (maf-formulas--render))))

(defun maf-formulas--lift-group (buf)
  "Widen menu buffer BUF out of any group narrowing, re-rendering if it had one.
What a filter searches is the whole list, so the group a filter meets
is lifted rather than searched inside — and the filter it had set
aside goes with it, there being nothing left to come back to."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when maf-formulas--group
        (setq maf-formulas--group nil
              maf-formulas--group-query nil)
        (maf-formulas--render-visible)))))

(defun maf-formulas--set-query (buf query)
  "Narrow menu buffer BUF to QUERY, re-rendering when it changed.
Any group narrowing is lifted with it: a filter is a search over every
formula, not over the corner of the list last stepped into.
Rendering happens with BUF's window selected so point and the window's
view move together, as they would if the user had navigated there."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (if (equal query maf-formulas--query)
          (maf-formulas--lift-group buf)
        (setq maf-formulas--query query
              maf-formulas--group nil
              maf-formulas--group-query nil)
        (maf-formulas--render-visible)))))

(defun maf-formulas--restore-narrowing (buf query group group-query)
  "Put menu buffer BUF's narrowing back to QUERY, GROUP and GROUP-QUERY.
The way back from a filter that was abandoned: setting a query only
ever widens out of a group, where \\[keyboard-quit] has one to put back."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq maf-formulas--query query
            maf-formulas--group group
            maf-formulas--group-query group-query)
      (maf-formulas--render-visible))))

(defun maf-formulas--filter-update ()
  "Narrow the menu to what is typed so far.
Runs on the minibuffer's own `post-command-hook'. Until the first
edit, the empty prompt leaves the current narrowing alone — a group
included, which the first character typed then lifts, the search being
over the whole list; deleting back to empty after typing does widen to
the full list."
  (let ((s (minibuffer-contents-no-properties)))
    (unless (and (string-empty-p s) (not maf-formulas--filter-touched))
      (setq maf-formulas--filter-touched t)
      (maf-formulas--set-query maf-formulas--filter-buffer s))))

(defun maf-formulas-filter (&optional query)
  "Narrow the formula menu to QUERY (title, category, or variable).
QUERY is matched a word at a time — \"power rule\" finds the formulas
named by both words, in either order and in any of the fields a filter
looks at (see `maf-formulas--matches-p').

A filter searches the whole list, so a group narrowing in force is
lifted rather than searched inside — but not before there is a search:
the prompt opens on the group, and the first character typed widens to
every formula. An abandoned \\`/' leaves the list exactly as it was,
and \\[keyboard-quit] after typing puts the group back with the rest.

Called interactively, the list narrows as each character is typed, so
the match is visible before the filter is committed; RET keeps the
narrowing and \\[keyboard-quit] restores the one in effect before."
  (interactive)
  (if query
      (maf-formulas--set-query (current-buffer) query)
    (let* ((buf (current-buffer))
           (prev maf-formulas--query)
           (prev-group maf-formulas--group)
           (prev-group-query maf-formulas--group-query)
           (maf-formulas--filter-buffer buf)
           (maf-formulas--filter-touched nil))
      (condition-case nil
          ;; The live narrowing has already applied what was typed; the
          ;; returned string settles anything a final command changed.
          ;; RET on an untouched prompt is left alone entirely — the
          ;; list never previewed anything else, and a group it is
          ;; still narrowed to is not something a search never made
          ;; took away.
          (let ((s (minibuffer-with-setup-hook
                       (lambda ()
                         (add-hook 'post-command-hook #'maf-formulas--filter-update nil t))
                     (read-string "Filter formulas: "))))
            (when maf-formulas--filter-touched
              (maf-formulas--set-query buf s)))
        (quit (maf-formulas--restore-narrowing buf prev prev-group prev-group-query)
              (signal 'quit nil))))))

(defun maf-formulas-clear-filter ()
  "Clear the menu's narrowing — the filter string and any group with it.
The list can be narrowed two ways at once, by what was typed and by
the group RET was pressed on; one key puts the whole list back rather
than leaving the other narrowing to be found and undone."
  (interactive)
  (setq maf-formulas--query ""
        maf-formulas--group nil
        maf-formulas--group-query nil)
  (maf-formulas--render))

(defun maf-formulas-filter-group (&optional group)
  "Narrow the menu to GROUP, the category header at point by default.
A group's header is both the way in and the way out: RET on one leaves
that group alone on screen, and RET on the header again — it is still
there, at the top — widens back to every group. Point stays on the
header across both, so the key can be pressed twice for a look and a
return.

The group comes up whole. A filter in force is lifted for it, not
compounded with it: the header names a group of formulas, and reaching
for it from a filtered list asks for that group, not for the part of
it the filter had left standing. The filter is not lost — widening
again puts it back, and the list returns to the one the header was
pressed from. Filtering with \\<maf-formulas-mode-map>\\[maf-formulas-filter] is the other way out: a filter
searches the whole list, so it leaves the group rather than narrowing
inside it. \\[maf-formulas-clear-filter] drops the lot, whichever way the list was narrowed.

The \"Recent\" group narrows like any other, and is the one group a
filter string cannot reach — it is a shortcut rather than a category,
so no title or variable of its formulas names it."
  (interactive)
  (let ((group (or group (maf-formulas--group-at-point))))
    (unless group (user-error "Not on a group header"))
    (if (equal group maf-formulas--group)
        ;; Widening: the filter the narrowing lifted comes back with the
        ;; other groups, so the round trip lands where it started.
        ;; Nothing was typed in the meantime — a filter would have left
        ;; the group rather than narrowed inside it.
        (setq maf-formulas--group nil
              maf-formulas--query (or maf-formulas--group-query "")
              maf-formulas--group-query nil)
      ;; Asking for a group is asking to see it, so a fold on the way
      ;; in is lifted rather than left to hide what was just reached
      ;; for — the same courtesy a filter gets in `maf-formulas--sync-collapse'.
      (setq maf-formulas--collapsed (remove group maf-formulas--collapsed)
            maf-formulas--group group
            maf-formulas--group-query maf-formulas--query
            maf-formulas--query ""))
    (maf-formulas--render)
    (maf-formulas--goto-group group)
    (maf-formulas--item-start)))

(defun maf-formulas--group-at-point ()
  "The category name when point is on a group header, else nil.
A header is a non-blank line carrying no formula, and the renderer
puts the category in its `maf-formula-group' property — the same
string `maf-formulas--groups' keyed the group by, so it can be handed
straight back as a narrowing. The line's own text no longer serves
for that: a folded header wears its count as well as its name. The
text is still read when the property is missing, for a buffer
rendered before the property existed."
  (let ((bol (line-beginning-position)))
    (and (> (line-end-position) bol)
         (not (get-text-property bol 'maf-formula))
         (or (get-text-property bol 'maf-formula-group)
             (buffer-substring-no-properties bol (line-end-position))))))

(defun maf-formulas--group-starts ()
  "Buffer positions of each category header line."
  (let (starts)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (maf-formulas--group-at-point)
          (push (line-beginning-position) starts))
        (forward-line 1)))
    (nreverse starts)))

(defun maf-formulas--goto-group (group)
  "Put point on GROUP's header line, when the current render shows one."
  (when-let ((pos (save-excursion
                    (goto-char (point-min))
                    (catch 'found
                      (while (not (eobp))
                        (when (equal (maf-formulas--group-at-point) group)
                          (throw 'found (line-beginning-position)))
                        (forward-line 1))
                      nil))))
    (goto-char pos)))

(defun maf-formulas--item-start ()
  "Put point on the first character of the line's entry.
The rows are indented, so a line's own beginning is a column of blanks
and a cursor sitting there reads as being beside the entry rather than
on it. Headers start in column zero, and are left where they are."
  (back-to-indentation))

(defun maf-formulas--stop-p (&optional formula-only)
  "Non-nil when the line at point is one the motion commands stop on.
That is a formula row, or — unless FORMULA-ONLY — a group header too:
a header is a place worth reaching now that RET on one narrows the
menu to its group, so the same keys that walk the formulas walk the
headers between them."
  (if formula-only
      (get-text-property (line-beginning-position) 'maf-formula)
    (or (get-text-property (line-beginning-position) 'maf-formula)
        (maf-formulas--group-at-point))))

(defun maf-formulas--seek-item (step &optional formula-only)
  "Step by STEP lines to the nearest stop, returning point, or nil for none.
Point is left where it was when there is nothing to reach.
FORMULA-ONLY passes through to `maf-formulas--stop-p'."
  (let ((p (point))
        (edge (if (> step 0) #'eobp #'bobp)))
    (forward-line step)
    (while (and (not (funcall edge)) (not (maf-formulas--stop-p formula-only)))
      (forward-line step))
    (cond ((maf-formulas--stop-p formula-only)
           (maf-formulas--item-start)
           (point))
          (t (goto-char p) nil))))

(defun maf-formulas-next-item ()
  "Move to the next formula or group header, skipping the blank lines."
  (interactive)
  (unless (maf-formulas--seek-item 1)
    (user-error "No next formula")))

(defun maf-formulas-prev-item ()
  "Move to the previous formula or group header, skipping the blank lines."
  (interactive)
  (unless (maf-formulas--seek-item -1)
    (user-error "No previous formula")))

(defun maf-formulas-next-group ()
  "Move to the next category header, stopping at the last one."
  (interactive)
  (let* ((p (line-beginning-position))
         (starts (maf-formulas--group-starts))
         (next (seq-find (lambda (s) (> s p)) starts)))
    (if next (goto-char next) (user-error "No next group"))))

(defun maf-formulas-prev-group ()
  "Move to this category's header, or the previous one, stopping at the first.
Like paragraph motion: the first press jumps to the current category
header, a second to the header before it."
  (interactive)
  (let* ((p (line-beginning-position))
         (starts (maf-formulas--group-starts))
         (cur (car (last (seq-filter (lambda (s) (<= s p)) starts))))
         (before (car (last (seq-filter (lambda (s) (< s p)) starts)))))
    (cond ((and cur (< cur p)) (goto-char cur))
          (before (goto-char before))
          (t (user-error "No previous group")))))

(defun maf-formulas--group-of-point ()
  "The category the line at point belongs to.
Its own name on a header, and the nearest header above on a formula
row — so a key meaning \"this group\" can be pressed anywhere in it."
  (or (maf-formulas--group-at-point)
      (let* ((p (line-beginning-position))
             (header (car (last (seq-filter (lambda (s) (<= s p))
                                            (maf-formulas--group-starts))))))
        (and header (save-excursion (goto-char header)
                                    (maf-formulas--group-at-point))))))

(defun maf-formulas-toggle-group ()
  "Fold the group at point away to its header, or unfold it again.
A folded group keeps its header and wears the count of what it holds,
so a list too long to read is read as its group names instead — fold
what is not wanted, glance down the headers, unfold the one that is.
Pressed on a formula row it folds the group that row is in, point
coming to rest on the header; pressed on that header it unfolds.

\\<maf-formulas-mode-map>\\[maf-formulas-toggle-all-groups] folds or
unfolds every group at once, and is the key the fold view is reached
by; this one picks a single group out of it.

Folds are not a narrowing: the folded formulas are still in the list,
still counted, and \\[maf-formulas-clear-filter] leaves them folded —
a fold is undone where it was made. Starting a search is the
exception, and unfolds everything so that what it turns up can be
seen; the list stays unfolded once the filter lifts. Inside a search
the keys fold and unfold the matching groups as they always do
\\(`maf-formulas--sync-collapse')."
  (interactive)
  (let ((group (maf-formulas--group-of-point)))
    (unless group (user-error "No group here"))
    (setq maf-formulas--collapsed
          (if (maf-formulas--collapsed-p group)
              (remove group maf-formulas--collapsed)
            (cons group maf-formulas--collapsed)))
    (maf-formulas--render)
    (maf-formulas--goto-group group)
    (maf-formulas--item-start)))

(defun maf-formulas-toggle-all-groups ()
  "Fold every group away to its headers, or unfold them all.
The fold view for the whole list in one key: with anything folded this
unfolds the lot, otherwise it folds the lot. Point keeps its group,
landing on that header when the rows it was among have gone.

What it folds does not depend on where it is pressed — the key is for
a view of the whole list, and means the same thing from any line in
it. Folding one group at a time is
\\<maf-formulas-mode-map>\\[maf-formulas-toggle-group]."
  (interactive)
  (let ((group (maf-formulas--group-of-point)))
    (setq maf-formulas--collapsed
          (unless maf-formulas--collapsed
            (mapcar #'car (maf-formulas--groups))))
    (maf-formulas--render)
    (when group (maf-formulas--goto-group group))
    (maf-formulas--item-start)))

(defun maf-formulas-quit ()
  "Quit the formula menu, closing the detail pane too.
The menu's window is deleted if `maf-formulas' made one, or goes back to
the buffer it displaced if it borrowed one; the rest of the frame is
untouched either way."
  (interactive)
  (maf-formulas--close-detail)
  ;; `quit-window' is `pop-to-buffer''s counterpart: it deletes the
  ;; window when the menu made one, and puts the displaced buffer back
  ;; when it borrowed one. Either way the frame returns as it was.
  (quit-window))

(defvar maf-formulas-mode-map (make-sparse-keymap)
  "Keymap for `maf-formulas-mode'.")

;; Bindings outside the defvar so reloading applies edits.
(define-key maf-formulas-mode-map (kbd "RET") #'maf-formulas-select)
(define-key maf-formulas-mode-map (kbd "/")   #'maf-formulas-filter)
(define-key maf-formulas-mode-map (kbd "g")   #'maf-formulas-clear-filter)
(define-key maf-formulas-mode-map (kbd "c")   #'maf-formulas-clear-filter)
(define-key maf-formulas-mode-map (kbd "q")   #'maf-formulas-quit)
(define-key maf-formulas-mode-map (kbd "o")   #'maf-formulas-show-detail)
(define-key maf-formulas-mode-map (kbd "?")   #'maf-formulas-show-detail)
;; `d' — once an alias for `o' — is deliberately unbound; the explicit
;; nil clears it from a live map on reload.
(define-key maf-formulas-mode-map (kbd "d")   nil)
(define-key maf-formulas-mode-map (kbd "O")   #'maf-formulas-toggle-detail)
(define-key maf-formulas-mode-map (kbd "a")   #'maf-formulas-add-recent)
(define-key maf-formulas-mode-map (kbd "i")   #'maf-formulas-add-recent)
(define-key maf-formulas-mode-map (kbd "D")   #'maf-formulas-delete-recent)
(define-key maf-formulas-mode-map (kbd "C-g") #'maf-formulas-keyboard-quit)
;; Two levels of motion: n/p/j/k step formula to formula (headers and
;; the blank lines between groups are skipped), M-n/M-p step group to
;; group.
(define-key maf-formulas-mode-map (kbd "n")   #'maf-formulas-next-item)
(define-key maf-formulas-mode-map (kbd "p")   #'maf-formulas-prev-item)
(define-key maf-formulas-mode-map (kbd "j")   #'maf-formulas-next-item)
(define-key maf-formulas-mode-map (kbd "k")   #'maf-formulas-prev-item)
(define-key maf-formulas-mode-map (kbd "M-n") #'maf-formulas-next-group)
(define-key maf-formulas-mode-map (kbd "M-p") #'maf-formulas-prev-group)
;; TAB folds, the outline reflex — and the list is long enough now to
;; be read as its headers. It had been a third key for the item
;; motion, which n/p/j/k already cover twice over; the fold has no
;; other key it would be looked for on.
;;
;; The whole list, not the group under point: TAB means the same thing
;; wherever it is pressed, which is what makes it the key for a view
;; of the list rather than an edit to one corner of it. S-TAB is the
;; one group, for picking the wanted one out of a folded list.
(define-key maf-formulas-mode-map (kbd "TAB")       #'maf-formulas-toggle-all-groups)
(define-key maf-formulas-mode-map (kbd "<backtab>") #'maf-formulas-toggle-group)

(define-derived-mode maf-formulas-mode special-mode "maf-formulas"
  "Major mode for the saved-formula list.
Formulas are grouped by category, the ones inserted this session
repeated in a \"Recent\" group at the top, each shown beside its
form. \\<maf-formulas-mode-map>\\[maf-formulas-select]
pushes the formula at point onto the stack — or, on a group header,
narrows the list to that group, whole, and widens again when pressed
there a second time. \\[maf-formulas-next-item] and
\\[maf-formulas-prev-item] step between the rows and the headers
alike, landing on the entry itself rather than the column before it;
\\[maf-formulas-next-group] and \\[maf-formulas-prev-group] step
group to group. \\[maf-formulas-toggle-all-groups] folds every group
away to its header and unfolds them all again, so a long list can be
read as its group names; \\[maf-formulas-toggle-group] folds or
unfolds the one group at point. \\[maf-formulas-show-detail] shows
the formula at point in the detail pane (again to close it),
\\[maf-formulas-toggle-detail] toggles the pane following point (on
by default, remembered for the session), \\[maf-formulas-add-recent]
adds the formula at point to the Recent group without inserting it,
\\[maf-formulas-delete-recent] drops the recent entry at point,
\\[maf-formulas-filter] filters as you type,
\\[maf-formulas-clear-filter] clears every narrowing,
\\[maf-formulas-quit] quits."
  (setq truncate-lines t)
  ;; The legend's band is the options buffer's: `header-line's own look
  ;; is replaced outright, not layered under, so the two read as one
  ;; piece of chrome across maf's buffers.
  (face-remap-set-base 'header-line 'dial-controls)
  (add-hook 'post-command-hook #'maf-formulas--detail-on-move nil t))

;;;###autoload
(defun maf-formulas ()
  "Open the saved-formula menu, its detail pane following point.
If the menu is already on screen, go to its window instead, leaving the
filter and the pane as they stand.
\\<maf-formulas-mode-map>\\[maf-formulas-select] on a group header narrows the list to that group.
\\[maf-formulas-toggle-detail] toggles the pane, \\[maf-formulas-show-detail] freezes it on the formula at point."
  (interactive)
  (if-let ((win (get-buffer-window "*maf-formulas*" 0)))
      ;; Already on screen somewhere: visit it where it stands. Opening
      ;; it again would re-run `maf-formulas-mode', and the mode call
      ;; kills the buffer-local state the menu is carrying — the filter
      ;; and the detail line — so the visible menu would reset under
      ;; the user for a command that only meant "go there".
      (progn
        (select-frame-set-input-focus (window-frame win))
        (select-window win))
    (let ((buf (get-buffer-create "*maf-formulas*")))
      (with-current-buffer buf
        (maf-formulas-mode)
        (maf-formulas--render))
      ;; Ordinary `pop-to-buffer' display: Emacs picks the window by the
      ;; usual rules, so `display-buffer-alist' can route the menu, and
      ;; `maf-formulas-quit' undoes exactly what was done.
      (pop-to-buffer buf)
      ;; The pane's state survives the menu being quit (following by
      ;; default), so opening brings it back rather than starting closed.
      (when maf-formulas--pane-state
        (maf-formulas--open-detail)))))

;;; The module

;;;###autoload
(define-minor-mode maf-use-formulas-mode
  "Make your saved formulas available in Calc.

Press s o to open *maf-formulas*. Formulas are grouped by category.
RET pushes the formula at point onto the stack, and o shows or hides
its explanation and variable names.

For example, a saved formula named distance can be inserted from the
menu instead of typed again. While this mode is on, Calc can also use
saved formulas as variables in recall and rewrite commands.

The formulas come from `maf-formulas-builtin' (the set maf ships with)
and `maf-formulas-file' (your own). Turning the mode off removes the
key and Calc variable registrations, but does not change that file.
You can still open the menu with M-x maf-formulas."
  :global t
  :group 'maf
  (if maf-use-formulas-mode
      (progn
        (maf-formulas--register-vars)
        (maf-bindings--refresh))
    (maf-formulas--unregister-vars)
    (maf-bindings--refresh)))

(maf-bindings-module-keys 'maf-formulas 'maf-use-formulas-mode
  '(((calc native vim) "s o" maf-formulas)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-formulas #'maf-use-formulas-mode
                       "Keep a library of formulas and push them onto the stack.

Press s o to open your formula library. RET pushes the formula at
point onto the stack; o shows its purpose and variable names. Basic
identities ship with maf; your own are stored in `maf-formulas-file'."
                       "s o" "Memory"))

(provide 'maf-formulas)
