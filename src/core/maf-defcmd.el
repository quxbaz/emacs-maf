;; -*- lexical-binding: t; -*-
;;
;; maf-defcmd.el
;;
;; Defines the `maf-defcmd' macro for declaring contextual calc commands.
;; A defcmd inspects point and the calc stack at call time, resolves a context
;; (home, entry, selection, etc.), and commits its result to the right location.

(require 'calc)  ; the macro expands to `calc-wrapper', defined in calc
(require 'maf-lib)
(require 'maf-resolve)
(require 'maf-commit)

(defun maf--defcmd-parse-docstring (forms)
  "Return the docstring from FORMS if the first element is a string, else nil."
  (when (stringp (car forms))
    (car forms)))

(defun maf--defcmd-parse-opts (forms)
  "Return an alist of keyword-value pairs from FORMS.
Skips a leading docstring."
  ;; Strip docstring
  (when (stringp (car forms)) (pop forms))
  (let (final-opts)
    (while (keywordp (car forms))
      (seq-let (k v) (list (pop forms) (pop forms))
        (push (cons k v) final-opts)))
    final-opts))

(defun maf--defcmd-validate-opts (opts)
  "Validate OPTS, signaling an error if any are invalid."
  (let ((arity (alist-get :arity opts)))
    (unless arity
      (error "Missing required option :arity"))
    (unless (memq arity '(unary binary))
      (error "Invalid :arity %s (expected unary or binary)" arity))))

(defun maf--defcmd-parse-body (forms)
  "Return the body forms from FORMS.
Skips a leading docstring and keyword-value pairs."
  ;; Strip docstring and options
  (when (stringp (car forms)) (pop forms))
  (while (keywordp (car forms)) (pop forms) (pop forms))
  forms)

(defun maf--defcmd-parse-rest (forms)
  (let ((docstring (maf--defcmd-parse-docstring forms))
        (opts (maf--defcmd-parse-opts forms))
        (body (maf--defcmd-parse-body forms)))
    `(,docstring ,opts ,body)))

(defun maf--defcmd-dispatch (cmd flag-desc)
  "Consume calc's Inverse/Hyperbolic flags, then invoke variant command CMD.
The flags are cleared before CMD runs, so a variant that itself declares
flag variants does not dispatch again — that is what keeps cross-linked
pairs like ln <-> exp from looping. CMD resolves its own context, and its
`calc-do' epilogue refreshes the mode line as usual. A nil CMD means the
invoking command has no FLAG-DESC variant: signal `user-error', still
consuming the flags so the next command starts clean."
  (setq calc-inverse-flag nil
        calc-hyperbolic-flag nil)
  (if cmd
      (call-interactively cmd)
    (calc-set-mode-line)
    (user-error "No %s variant for this command" flag-desc)))

(defmacro maf-defcmd (name bindings &rest rest)
  "Define NAME as an interactive contextual calc command.

BINDINGS is a three-symbol list (EXPR ARG COMMIT) naming the locals the
body sees:

  EXPR    The operand the command acts on, resolved from context — the
          formula at home/entry, the selected sub-expression, the one
          under point, etc.  For an equation target the body runs once
          per side, with EXPR bound to the LHS and then the RHS.
  ARG     The second operand for `binary' commands (taken from the calc
          stack top); nil for `unary' commands.
  COMMIT  A local function; call it with the result to write it back to
          the resolved location.  Call it once per body run (once per
          side, for an equation target).

REST is an optional docstring, then zero or more keyword-value option
pairs (OPTS), then the body forms — in that order.

OPTS configure context resolution and commit:

  :arity  Required.  `unary' or `binary'.  Selects whether ARG is taken
          from the stack and drives how each target resolves EXPR/ARG.
  :prefix String label recorded in the calc trail for the operation.

  :inverse             Command (symbol) to run instead when calc's
  :hyperbolic          Inverse flag is set (the I prefix), the
  :inverse-hyperbolic  Hyperbolic flag (H), or both.  The flags are
          consumed before the variant runs, so variants may themselves
          declare variants (cross-links like ln <-> exp do not loop).
          When a flag is set but the matching variant is absent, the
          command signals `user-error' and still consumes the flags.

Any other keyword in OPTS is merged verbatim into the resolved context
alist, so resolve/commit extensions can read it.

At call time the command resolves point and the calc stack into a
context (home, entry, selection, subexpr, or equation), binds EXPR and
ARG, runs the body, and commits its result to the right stack location."
  (declare (indent 2) (doc-string 3))
  (pcase-let* ((`(,docstring ,opts ,body) (maf--defcmd-parse-rest rest))
               (`(,expr ,arg ,commit) bindings)
               (inv (alist-get :inverse opts))
               (hyp (alist-get :hyperbolic opts))
               (invhyp (alist-get :inverse-hyperbolic opts))
               (context (gensym "context-"))
               (lhs (gensym "lhs-"))
               (rhs (gensym "rhs-"))
               (main
                ;; `calc-wrapper' makes the whole command a single undoable
                ;; unit and runs calc's command epilogue (trail, stack
                ;; refresh/renumber, point).
                `(calc-wrapper
                  (let* ((,context (maf--resolve-context ',opts))
                         (,arg (alist-get :arg ,context)))
                    (if (eq (alist-get :target ,context) 'equation)
                        ;; Equation target: run the body once per side (expr
                        ;; bound to the LHS, then the RHS), capturing each
                        ;; side's committed result. Then reassemble into a new
                        ;; relation and commit once. arg is bound once above,
                        ;; so both sides share it.
                        (let (,lhs ,rhs)
                          (let ((,expr (alist-get :lhs ,context)))
                            (cl-flet ((,commit (val) (setq ,lhs val)))
                              ,@body))
                          (let ((,expr (alist-get :rhs ,context)))
                            (cl-flet ((,commit (val) (setq ,rhs val)))
                              ,@body))
                          (maf--commit (list (alist-get :rel-op ,context)
                                             ,lhs ,rhs)
                                       ,context))
                      ;; All other targets: body runs once with :expr.
                      (let ((,expr (alist-get :expr ,context)))
                        (cl-flet ((,commit (val) (maf--commit val ,context)))
                          ,@body)))))))
    (maf--defcmd-validate-opts opts)
    `(defun ,name ()
       ,@(when docstring (list docstring))
       (interactive)
       ,(if (or inv hyp invhyp)
            ;; Calc's I/H flags reroute to the declared variant command
            ;; before any context is resolved (and before calc-wrapper, so
            ;; the variant's own wrapper is the only one that runs).
            `(cond ((and calc-inverse-flag calc-hyperbolic-flag)
                    (maf--defcmd-dispatch ,(and invhyp `#',invhyp)
                                          "inverse hyperbolic"))
                   (calc-inverse-flag
                    (maf--defcmd-dispatch ,(and inv `#',inv) "inverse"))
                   (calc-hyperbolic-flag
                    (maf--defcmd-dispatch ,(and hyp `#',hyp) "hyperbolic"))
                   (t ,main))
          main))))

(provide 'maf-defcmd)
