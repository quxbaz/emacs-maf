;; -*- lexical-binding: t; -*-
;;
;; modules/maf-formulas.el
;;
;; Saved-formula library. `maf-formulas' opens a menu of formulas
;; grouped by category, each shown beside its form, with a detail pane
;; following point — the formula in Big display, a description, and
;; what each variable means — re-rendering for each formula reached.
;; The menu is a filter-view (pkg/filter-view): that package owns the
;; buffer, the as-you-type filter, the group narrowing and folding,
;; the Recent group, the motions and the detail pane's mechanics; see
;; `filter-view-mode' for the keys. This module supplies what the menu
;; shows — the formulas, their rows, the detail text — and what RET
;; does: push the formula at point onto the calc stack.
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
;; An identity that turns on a premise — a + c = b + c holds because
;; a = b — can show the premise: a :display-expr of
;; (calcFunc-implies PREMISE CONCLUSION) renders as PREMISE => CONCLUSION,
;; typeset with the implies arrow, and (calcFunc-iff P Q) as P <=> Q
;; for one that runs both ways, while :expr stays the conclusion, the
;; form RET pushes.
;;
;; Formulas you insert are remembered in a "Recent" group at the top of
;; the menu for the rest of the session; it is not written anywhere.
;; The group holds formulas by :name, so a reloaded formula file keeps
;; the session's recents.
;;
;; The menu draws on two sources. `maf-formulas-builtin' is the set maf
;; ships with — the identities of school algebra and trigonometry, and
;; the formulas school geometry measures a solid with — and
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
(require 'dial)             ; first, so filter-view's chrome inherits its
(require 'filter-view)      ; the menu shell: filtering, groups, the pane

;; The module installs its `s o' binding into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

;; Defined in lazily-loaded calc modules; declared for the byte compiler.
(declare-function math-format-value "calc-ext")
(declare-function math-compose-expr "calccomp")
(defvar calc-language)
(declare-function calc-pop-push-record-list "calc-ext")
(declare-function maf-register-module "maf-module")
(declare-function maf-bindings-module-keys "maf-bindings")
(declare-function maf-bindings--refresh "maf-bindings")

(defface maf-formulas-category
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for the detail pane's title in the formula menu.
The group headers themselves are the shell's, in `filter-view-group'."
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

(defvar maf-formulas--loaded nil
  "Non-nil once `maf-formulas-file' has been consulted this session.")

;;; Implication and equivalence, for display

;; An identity that turns on a premise — a = b behind a + c = b + c —
;; shows the premise in the detail pane as P => Q, calc's => put to
;; the reading it has on paper, or as P <=> Q where the two sides say
;; the same thing, as the absolute-value splits do. Calc has neither
;; connective to compute with, so RET still pushes the conclusion, the
;; working form, and `implies' and `iff' are display-only calls:
;; nothing defines them, so nothing evaluates them, and these
;; compositions are all there is to them. The nil entry serves every
;; language calc composes for, Big included; the latex entry serves
;; `maf--latex-string', which composes in calc's latex language, where
;; the property is read like any other.

(defun maf-formulas--compose-connective (a arrow)
  "Compose the display call A, a two-sided connective, with ARROW between.
Spaced as calc spaces its own => in each language: doubly in Big,
singly elsewhere."
  (list 'horiz (math-compose-expr (nth 1 a) 0)
        (if (eq calc-language 'big)
            (concat "  " arrow "  ")
          (concat " " arrow " "))
        (math-compose-expr (nth 2 a) 0)))

(defun maf-formulas--compose-implies (a)
  "Compose the display call A, implies(P, Q), as P => Q."
  (maf-formulas--compose-connective a "=>"))

(defun maf-formulas--compose-iff (a)
  "Compose the display call A, iff(P, Q), as P <=> Q."
  (maf-formulas--compose-connective a "<=>"))

(defun maf-formulas--latex-compose-implies (a)
  "Compose the display call A, implies(P, Q), as P \\implies Q."
  (maf-formulas--compose-connective a "\\implies"))

(defun maf-formulas--latex-compose-iff (a)
  "Compose the display call A, iff(P, Q), as P \\iff Q."
  (maf-formulas--compose-connective a "\\iff"))

(put 'calcFunc-implies 'math-compose-forms
     '((nil (nil . maf-formulas--compose-implies))
       (latex (nil . maf-formulas--latex-compose-implies))))

(put 'calcFunc-iff 'math-compose-forms
     '((nil (nil . maf-formulas--compose-iff))
       (latex (nil . maf-formulas--latex-compose-iff))))

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
     :display-expr (calcFunc-iff
                    (calcFunc-eq (* (var a var-a) (var b var-b)) 0)
                    (calcFunc-lor (calcFunc-eq (var a var-a) 0)
                                  (calcFunc-eq (var b var-b) 0)))
     :doc "When a b = 0, at least one factor is zero."
     :vars ((a . "first factor") (b . "second factor"))
     :examples ("(x - 2) (x - 3) = 0 gives x = 2 or x = 3."))
    (:name "addition-property-of-equality"
     :title "Addition property of equality"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (+ (var a var-a) (var c var-c))
                        (+ (var b var-b) (var c var-c)))
     :display-expr (calcFunc-iff
                    (calcFunc-eq (var a var-a) (var b var-b))
                    (calcFunc-eq (+ (var a var-a) (var c var-c))
                                 (+ (var b var-b) (var c var-c))))
     :doc "Adding the same number to both sides of a = b keeps the equality."
     :vars ((a . "left side of a = b") (b . "right side of a = b")
            (c . "number added to both sides"))
     :examples ("x - 3 = 5 gives x = 8, adding 3 to both sides."))
    (:name "subtraction-property-of-equality"
     :title "Subtraction property of equality"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (- (var a var-a) (var c var-c))
                        (- (var b var-b) (var c var-c)))
     :display-expr (calcFunc-iff
                    (calcFunc-eq (var a var-a) (var b var-b))
                    (calcFunc-eq (- (var a var-a) (var c var-c))
                                 (- (var b var-b) (var c var-c))))
     :doc "Subtracting the same number from both sides of a = b keeps the equality."
     :vars ((a . "left side of a = b") (b . "right side of a = b")
            (c . "number subtracted from both sides"))
     :examples ("x + 4 = 9 gives x = 5, subtracting 4 from both sides."))
    (:name "multiplication-property-of-equality"
     :title "Multiplication property of equality"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (* (var a var-a) (var c var-c))
                        (* (var b var-b) (var c var-c)))
     :display-expr (calcFunc-implies
                    (calcFunc-eq (var a var-a) (var b var-b))
                    (calcFunc-eq (* (var a var-a) (var c var-c))
                                 (* (var b var-b) (var c var-c))))
     :doc "Multiplying both sides of a = b by the same number keeps the equality."
     :vars ((a . "left side of a = b") (b . "right side of a = b")
            (c . "number both sides are multiplied by"))
     :examples ("x / 2 = 6 gives x = 12, multiplying both sides by 2."))
    (:name "division-property-of-equality"
     :title "Division property of equality"
     :category "Algebra — Properties of real numbers"
     :expr (calcFunc-eq (/ (var a var-a) (var c var-c))
                        (/ (var b var-b) (var c var-c)))
     :display-expr (calcFunc-iff
                    (calcFunc-eq (var a var-a) (var b var-b))
                    (calcFunc-eq (/ (var a var-a) (var c var-c))
                                 (/ (var b var-b) (var c var-c))))
     :doc "Dividing both sides of a = b by the same nonzero number keeps the equality."
     :vars ((a . "left side of a = b") (b . "right side of a = b")
            (c . "nonzero number both sides are divided by"))
     :examples ("3 x = 12 gives x = 4, dividing both sides by 3."))
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
     :display-expr (calcFunc-iff
                    (calcFunc-eq (/ (var a var-a) (var b var-b))
                                 (/ (var c var-c) (var d var-d)))
                    (calcFunc-eq (* (var a var-a) (var d var-d))
                                 (* (var b var-b) (var c var-c))))
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
     :display-expr (calcFunc-iff
                    (calcFunc-eq (calcFunc-abs (var x var-x)) (var a var-a))
                    (calcFunc-lor (calcFunc-eq (var x var-x) (var a var-a))
                                  (calcFunc-eq (var x var-x) (neg (var a var-a)))))
     :doc "What abs(x) = a splits into, for a nonnegative."
     :vars ((x . "the unknown") (a . "nonnegative number"))
     :examples ("abs(x - 1) = 5 gives x = 6 or x = -4."))
    (:name "absolute-value-less-than"
     :title "Absolute value less than"
     :category "Algebra — Absolute value"
     :expr (calcFunc-land (calcFunc-lt (neg (var a var-a)) (var x var-x))
                          (calcFunc-lt (var x var-x) (var a var-a)))
     :display-expr (calcFunc-iff
                    (calcFunc-lt (calcFunc-abs (var x var-x)) (var a var-a))
                    (calcFunc-land (calcFunc-lt (neg (var a var-a)) (var x var-x))
                                   (calcFunc-lt (var x var-x) (var a var-a))))
     :doc "What abs(x) < a splits into: a band around zero."
     :vars ((x . "the unknown") (a . "positive number")))
    (:name "absolute-value-greater-than"
     :title "Absolute value greater than"
     :category "Algebra — Absolute value"
     :expr (calcFunc-lor (calcFunc-lt (var x var-x) (neg (var a var-a)))
                         (calcFunc-gt (var x var-x) (var a var-a)))
     :display-expr (calcFunc-iff
                    (calcFunc-gt (calcFunc-abs (var x var-x)) (var a var-a))
                    (calcFunc-lor (calcFunc-lt (var x var-x) (neg (var a var-a)))
                                  (calcFunc-gt (var x var-x) (var a var-a))))
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
     :vars ((x . "any angle with cos(x) not 0")))
    (:name "volume-of-rectangular-solid"
     :title "Volume of rectangular solid"
     :category "Geometry — 3D: Rectangular Solid"
     :expr (calcFunc-eq (var V var-V)
                        (* (var l var-l) (* (var w var-w) (var h var-h))))
     :doc "Volume of a rectangular solid: length times width times height."
     :vars ((V . "volume") (l . "length") (w . "width") (h . "height")))
    (:name "surface-area-of-rectangular-solid"
     :title "Surface area of rectangular solid"
     :category "Geometry — 3D: Rectangular Solid"
     :expr (calcFunc-eq (var S var-S)
                        (* 2 (+ (+ (* (var l var-l) (var w var-w))
                                   (* (var w var-w) (var h var-h)))
                                (* (var h var-h) (var l var-l)))))
     :doc "Surface area of a rectangular solid: three pairs of equal faces."
     :vars ((S . "surface area") (l . "length") (w . "width") (h . "height")))
    (:name "lateral-surface-area-of-rectangular-solid"
     :title "Lateral surface area of rectangular solid"
     :category "Geometry — 3D: Rectangular Solid"
     :expr (calcFunc-eq (var SL var-SL)
                        (* 2 (* (var h var-h)
                                (+ (var l var-l) (var w var-w)))))
     :doc "Lateral (side) surface area: the base perimeter times the height."
     :vars ((SL . "lateral surface area") (l . "length") (w . "width")
            (h . "height")))
    (:name "diagonal-of-rectangular-solid"
     :title "Diagonal of rectangular solid"
     :category "Geometry — 3D: Rectangular Solid"
     :expr (calcFunc-eq (var d var-d)
                        (calcFunc-sqrt (+ (+ (^ (var l var-l) 2)
                                             (^ (var w var-w) 2))
                                          (^ (var h var-h) 2))))
     :doc "Corner to opposite corner: the Pythagorean theorem twice over."
     :vars ((d . "space diagonal") (l . "length") (w . "width") (h . "height"))
     :examples ("A 3 by 4 by 12 box has diagonal 13."))
    (:name "volume-of-cube"
     :title "Volume of cube"
     :category "Geometry — 3D: Cube"
     :expr (calcFunc-eq (var V var-V) (^ (var s var-s) 3))
     :doc "Volume of a cube, the solid whose three edges are equal."
     :vars ((V . "volume") (s . "edge length")))
    (:name "surface-area-of-cube"
     :title "Surface area of cube"
     :category "Geometry — 3D: Cube"
     :expr (calcFunc-eq (var S var-S) (* 6 (^ (var s var-s) 2)))
     :doc "Surface area of a cube: six square faces of equal area."
     :vars ((S . "surface area") (s . "edge length")))
    (:name "diagonal-of-cube"
     :title "Diagonal of cube"
     :category "Geometry — 3D: Cube"
     :expr (calcFunc-eq (var d var-d) (* (var s var-s) (calcFunc-sqrt 3)))
     :doc "Space diagonal of a cube: its edge times the root of three."
     :vars ((d . "space diagonal") (s . "edge length")))
    (:name "distance-formula"
     :title "Distance formula"
     :category "Geometry — 2D: Coordinate plane"
     :expr (calcFunc-eq (var d var-d)
                        (calcFunc-sqrt (+ (^ (- (var x2 var-x2) (var x1 var-x1)) 2)
                                          (^ (- (var y2 var-y2) (var y1 var-y1)) 2))))
     :doc "Distance between two points of the plane: the Pythagorean theorem on the run and the rise between them."
     :vars ((d . "distance") (x1 . "first point's x") (y1 . "first point's y")
            (x2 . "second point's x") (y2 . "second point's y"))
     :examples ("From (1, 2) to (4, 6) is 5."))
    (:name "circumference-of-circle"
     :title "Circumference of circle"
     :category "Geometry — 2D: Circle"
     :expr (calcFunc-eq (var C var-C) (* 2 (* (var pi var-pi) (var r var-r))))
     :doc "Circumference of a circle from its radius: two pi times the radius."
     :vars ((C . "circumference") (r . "radius"))
     :examples ("A circle of radius 3 has circumference 6 pi.")))
  "The formulas maf ships with, in the plist shape of `maf-formulas-user'.
The identities school algebra and trigonometry rest on, the formulas
school geometry measures a solid with, and the ones a rewrite is most
often reaching for. They come in categories the menu sorts by name and
narrows to one at a time: the properties of real numbers, absolute
value, exponents, fractions, logarithms, quadratic equations and
radicals, then the trig identities in six groups of their own, then the
circle's circumference, the coordinate plane's distance formula, the
rectangular solid and the cube — a group per figure, as a library of
one's own names its geometry. The properties of real numbers calc applies in its
own default simplifications, so those earn their place by being
readable and by naming what a rewrite is doing rather than by teaching
calc anything; the rest calc will not supply on its own.

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

;;; The menu's rows

(defun maf-formulas--oneline (expr)
  "Render EXPR as a single normal-language line, for the list column."
  (let ((s (ignore-errors (let ((calc-language nil)) (math-format-value expr)))))
    (if s (replace-regexp-in-string "\n" " " s) "")))

(defun maf-formulas--groups-source ()
  "The menu's groups, an alist of (CATEGORY . FORMULAS).
Categories come alphabetically. This is the raw list the shell reads:
filter-view adds the Recent group at its head and applies whatever
narrowing — filter or group — is in force."
  (let ((groups nil))
    (dolist (f (maf-formulas--all))
      (let* ((cat (maf-formulas--category f))
             (cell (assoc cat groups)))
        (if cell
            (setcdr cell (cons f (cdr cell)))
          (push (list cat f) groups))))
    (sort (mapcar (lambda (g) (cons (car g) (nreverse (cdr g)))) groups)
          (lambda (a b) (string< (car a) (car b))))))

(defun maf-formulas--title-width (formulas)
  "The widest title among FORMULAS, the row renderer's alignment context.
Computed once per render, over the rows actually drawn — a folded
group's formulas are no reason to widen the column."
  (apply #'max 0 (mapcar (lambda (f) (length (maf-formulas--title f)))
                         formulas)))

(defun maf-formulas--row (f width)
  "Formula F's menu row: its title beside its one-line form.
A dotted leader bridges the gap to the aligned formula column — WIDTH
is the render context, the widest title drawn — so the eye can track
a short title across."
  (let* ((title (maf-formulas--title f))
         (leader (make-string (+ 1 (max 0 (- width (length title)))) ?.)))
    (concat "  " (propertize title 'face 'maf-formulas-title) " "
            (propertize leader 'face 'maf-formulas-leader) " "
            (propertize (maf-formulas--oneline (plist-get f :expr))
                        'face 'maf-formulas-form))))

(defun maf-formulas--fields (f _group)
  "What the filter matches for formula F: title, category, variables."
  (append (list (maf-formulas--title f) (maf-formulas--category f))
          (mapcar (lambda (v) (format "%s %s" (car v) (cdr v)))
                  (plist-get f :vars))))

(defun maf-formulas--key (f)
  "Formula F's identity for the Recent group: its :name, itself unnamed.
By name rather than by object, so a reloaded formula file — new plists,
same names — keeps the session's recents."
  (or (plist-get f :name) f))

;;; The detail pane's text

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

;;; The menu

(defun maf-formulas--insert (f)
  "Push formula F onto the calc stack, and quit the menu.
The action RET hands the formula at point to (`filter-view-select')."
  (let ((buf (or (maf--find-calc-buffer) (get-buffer "*Calculator*"))))
    (unless buf (user-error "No calc buffer found"))
    (with-current-buffer buf
      (calc-wrapper
       (calc-pop-push-record-list 0 "frml" (list (copy-tree (plist-get f :expr)))
                                  1 (list nil))))
    (message "Inserted: %s" (maf-formulas--title f))
    (filter-view-quit)))

(defun maf-formulas--config ()
  "The filter-view CONFIG the formula menu opens with.
One place for the open command and a test to share; see filter-view's
commentary for what each key means."
  (list :name "maf-formulas"
        :select-verb "inserts"
        :groups #'maf-formulas--groups-source
        :context #'maf-formulas--title-width
        :render #'maf-formulas--row
        :key #'maf-formulas--key
        :title #'maf-formulas--title
        :fields #'maf-formulas--fields
        :select #'maf-formulas--insert
        :detail #'maf-formulas--detail-string
        ;; Borrow a window if the frame has one to lend (calc's,
        ;; usually), keeping it where it already is on a re-show.
        :detail-actions '(display-buffer-reuse-window
                          maf--display-borrowing-window
                          display-buffer-in-direction)
        ;; Functions, so the defcustoms are consulted live.
        :detail-min-width (lambda () maf-formulas-detail-min-width)
        :recent-max (lambda () maf-formulas-recent-max)))

;;;###autoload
(defun maf-formulas ()
  "Open the saved-formula menu, its detail pane following point.
If the menu is already on screen, go to its window instead, leaving the
filter and the pane as they stand. The menu is a filter-view; see
`filter-view-mode' for the keys. \\<filter-view-mode-map>\\[filter-view-select] pushes the formula at point onto
the stack — or, on a group header, narrows the list to that group —
\\[filter-view-toggle-detail] toggles the pane following point, \\[filter-view-visit-detail] shows the formula at point and goes there."
  (interactive)
  (apply #'filter-view-open "*maf-formulas*" (maf-formulas--config)))

(defun maf-formulas-refresh-detail ()
  "Re-render the detail pane, if one is on screen.
For a caller that changed what the pane draws with rather than which
formula it shows: the pretty module's toggle swaps the renderer from
the module menu, and the pane otherwise repaints only when point in
the list reaches another formula."
  (filter-view-refresh-detail "*maf-formulas*"))

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
