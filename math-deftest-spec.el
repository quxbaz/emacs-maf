(defmacro maf-deftest (name doc &rest body)
  (declare (indent 1)))

(maf-deftest factor

  ;; Auto-generated test case names: factor/home, factor/sub-formula,
  ;; factor/line-end, factor/line-start, factor/equation, factor/option-flag
  ;;
  ;; The macro should expand into multiple tests for different contexts.
  ;; `maf-test-x`, `math-test-y`, and `maf-test-out` don't refer to stack
  ;; entries, they represent pure inputs and outputs independent of where
  ;; they're coming from. `x` and `y` could both refer to stack entries, or `x`
  ;; could refer to a sub-formula and `y` could be a stack entry.
  ;;
  ;; maf-deftest should generate a test for each context. At the very least,
  ;; given a binary arity command:
  ;;
  ;; 1. Point is at home: x=stack-1 (the subject), y=stack (the argument)
  ;; 2. Point is on a sub-formula: x=sub-formula (the subject, y=stack (the argument)
  ;;
  ;;    EXAMPLE - point is on the `+`, so the sub-formula is 16 + 4:
  ;;
  ;;      2: y = 16 x + 4
  ;;      1: 4
  ;;
  ;;    Auto-generated test case expects output to be:
  ;;
  ;;      1: y = 4 (4x + 1) * q
  ;;
  ;; 3. Point is at the end of the line
  ;; 3a. Line is NOT an equation or inequality: x=the entry, y=stack
  ;; 3b. Line IS an equation of inequality: x=LHS and RHS, y=stack.
  ;;     The command is executed on both sides using y as the argument.
  ;;     Some commands NEVER operate on equations and default to line context.
  ;;
  ;;     The primary mechanism for creating custom commands is the macro
  ;;     (maf-defcmd). It declares a list of options including if equation
  ;;     mapping is disabled for the command. Through this, the test should
  ;;     understand if a test should not be generated.
  ;;
  ;; 4. Point is at the start of the line: same as (3)
  ;; 5. Point is on an entry and Option flag is one: x=the entry, y=stack

  "DOCSTRING" ;; Macro expands to a standard ERT test

  ;; Also accepts calc expressions like '(+ 1 (+ (var x x)))
  (maf-test-x "10 x^2 + 5 x")
  (maf-test-y "5 x")  ;; if maf-test-y is given, we know this is a binary function
  (maf-test-out "5 (2 x + 1)")

  ;; OPTIONAL
  ;; (maf-test-start-point 'h)
  ;; (maf-test-end-point 'h)

  (maf-test-do 'maf-factor)

  ;; Also acceptable:
  ;; (maf-test-do BODY)

  ;; OPTIONAL: maf-test-out is the main condition
  ;; (maf-test-is CONDS)

  )

(maf-deftest roll-down

  ;; This form is better suited to testing non-computational commands. Test is
  ;; much more explicit in this form. The macro does not generate contextual
  ;; forms here. 1 deftest = 1 ert test
  ;;
  ;; What if a single maf-deftest has both (maf-test-x …) and (maf-test-stack-in
  ;; …)? Error at macro-expansion time. Add a clear message: "math-relation
  ;; shape and stack-snapshot shape are mutually exclusive."

  "DOCSTRING" ;; Macro expands to a standard ERT test

  (maf-test-stack-in "b" "a")
  (maf-test-stack-out "a" "b")

  (maf-test-start-point 'h)
  (maf-test-end-point 'h)

  (maf-test-do 'maf-roll-down)

  )
