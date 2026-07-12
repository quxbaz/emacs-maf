;; -*- lexical-binding: t; -*-
;;
;; maf-resolve.el
;;
;; Resolve point and calc state into a target-specific context descriptor.
;;
;; ----------------------------------------------------------------------------
;; Context schema (alist returned by `maf--resolve-context')
;; ----------------------------------------------------------------------------
;;
;; Target-specific keys (produced by `maf--resolve-target-*'):
;;
;;   :target       Symbol identifying the target: home, selection, subexpr,
;;                 equation, or entry.
;;   :expr         The expression the command operates on (full formula or
;;                 selected sub-formula, depending on target). Normalized — the
;;                 (cplx N 0) encasing that calc-prepare-selection wraps atoms
;;                 in is stripped, so the body sees clean values.
;;   :expr-ref     The same sub-formula as :expr but as the *original encased
;;                 cons cell* from the stack entry. Used by commit's
;;                 `calc-replace-sub-formula` for eq-based splicing — only the
;;                 encased ref matches the cons in the entry. Set only for
;;                 selection and subexpr.
;;   :arg          Second operand for binary commands; nil for unary.
;;   :m            Stack position (1 = top) of the target entry. Only set when
;;                 the target lives at a specific stack level (e.g. selection).
;;   :rel-op       Relation operator symbol (calcFunc-eq/neq/lt/...). Equation
;;                 target only — the macro uses it to reassemble the relation
;;                 after running the body once per side.
;;   :lhs, :rhs    The two sides of the relation. Equation target only — the
;;                 macro binds :expr to each in turn for the per-side body runs.
;;
;; Commit instructions (consumed by `maf--defcmd-commit'):
;;
;;   :commit-m     Stack level where the result is pushed.
;;   :commit-n     N argument to `calc-pop-push-record-list' — number of
;;                 entries popped at :commit-m before pushing.
;;   :post-pop     Number of entries popped from the top *after* the push,
;;                 to consume extra inputs (e.g. the binary arg on selection).
;;   :reselect     If non-nil, commit carries the result as the new selection
;;                 on the pushed entry. Set for targets with an explicit
;;                 user-set selection (selection); nil for implicit ones
;;                 (subexpr) where there's no selection to preserve.
;;
;; Merged in by `maf--resolve-context':
;;
;;   :arity        From OPTS: unary or binary.
;;   :prefix       From OPTS: calc trail label.
;;   :keep         Snapshot of `calc-keep-args-flag' at resolve time.
;;   ...any other keyword option passed to `maf-defcmd'.

(require 'maf-lib)
(require 'maf-sel)

(defun maf--resolve-target-selection (opts)
  "Return the selection target's context alist.
:expr is the selected sub-expression. The chosen entry is the one under point
when it has a selection, otherwise the top-most entry with an active selection.

For binary commands, :arg is the top of the stack. Binary commands require the
selected entry to be below the top (:m > 1); otherwise the arg would be the
entry containing the selection, which has no coherent commit semantics."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (m (maf--sel-effective-m))
           (keep calc-keep-args-flag)
           (encased (maf--sel-effective-expr)))
      ;; If m=1 and arity=binary then there's nowhere to take the arg from - reject.
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on selection require the selected entry below the top"))
      `((:target     . selection)
        ;; :expr is the clean form for the body; :expr-ref is the encased cons
        ;; commit needs for eq-based splicing.
        (:expr       . ,(math-normalize encased))
        (:expr-ref   . ,encased)
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:m          . ,m)
        (:commit-m   . ,(if keep 1 m))
        (:commit-n   . ,(if keep 0 1))
        (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))
        (:reselect   . t)))))

(defun maf--resolve-target-home (opts)
  "Return the home target's context alist."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (keep calc-keep-args-flag))
      `((:target     . home)
        ;; For binary, the lower entry is :expr and the top is :arg, so e.g.
        ;; 3 over 2 subtracts to 3 - 2 (not 2 - 3).
        (:expr       . ,(pcase arity ('unary (calc-top 1 'full)) ('binary (calc-top 2 'full))))
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:commit-m   . 1)
        (:commit-n   . ,(if keep 0 (pcase arity ('unary 1) ('binary 2))))
        (:post-pop   . 0)))))

(defun maf--resolve-target-subexpr (opts)
  "Return the subexpr target's context alist.
Point is inside an entry's formula text; :expr is the implicit sub-expression
under cursor.

For binary commands, :arg is the top of the stack. Binary commands require the
target entry to be below the top (:m > 1); otherwise the arg would be the
entry containing the sub-expression, which has no coherent commit semantics.
With keep-args off, commit replaces the sub-expression in-place; with
keep-args on, commit pushes the spliced result on top, leaving originals
untouched."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (m (calc-locate-cursor-element (point)))
           (keep calc-keep-args-flag))
      ;; If m=1 and arity=binary then there's nowhere to take the arg from - reject.
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on subexpr require the target entry below the top"))
      (calc-prepare-selection m)
      (let ((encased (calc-find-selected-part)))
        `((:target     . subexpr)
          ;; :expr is the clean form for the body; :expr-ref is the encased cons
          ;; commit needs for eq-based splicing.
          (:expr       . ,(math-normalize encased))
          (:expr-ref   . ,encased)
          (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
          (:m          . ,m)
          (:commit-m   . ,(if keep 1 m))
          (:commit-n   . ,(if keep 0 1))
          (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))
          (:reselect   . nil))))))

(defun maf--resolve-target-equation (opts)
  "Return the equation target's context alist.
The stack entry under point is a relation. The body runs once per side (the
macro binds :expr to :lhs, then to :rhs), and the per-side results are
reassembled into a new relation under :rel-op.

For binary commands, :arg is the top of the stack, shared across both sides.
Binary commands require the relation below the top (:m > 1); otherwise the arg
would be the relation itself. Unlike entry, equation cannot shift the target
down — the target must remain a relation — so it errors instead."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (m     (calc-locate-cursor-element (point)))
           (keep  calc-keep-args-flag)
           (expr  (calc-top m 'full)))
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on equation require the relation below the top"))
      `((:target     . equation)
        (:expr       . ,expr)
        (:rel-op     . ,(car expr))
        (:lhs        . ,(math-normalize (nth 1 expr)))
        (:rhs        . ,(math-normalize (nth 2 expr)))
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:m          . ,m)
        (:commit-m   . ,(if keep 1 m))
        (:commit-n   . ,(if keep 0 1))
        (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))))))

(defun maf--resolve-target-entry (opts)
  "Return the entry target's context alist.
Point is on a stack entry's margin (line-prefix or EOL); :expr is the whole
formula of that entry.

For binary commands, :arg is the top of the stack. With keep-args off, commit
replaces the entry in-place; with keep-args on, commit pushes the result on
top instead, leaving originals untouched.

Ergonomic shift: if point is at the top entry (m=1) and the command is binary,
the top is treated as :arg and the entry below as the target — point doesn't
have to be on the operand whose value will be replaced."
  (maf--with-calc-buffer
    (let ((arity (alist-get :arity opts))
          (m (calc-locate-cursor-element (point)))
          (keep calc-keep-args-flag))
      ;; For binary at the top entry, shift m down: the top becomes the arg
      ;; and the entry below becomes the target.
      (when (and (eq arity 'binary) (= m 1))
        (setq m 2))
      `((:target     . entry)
        (:expr       . ,(calc-top m 'full))
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:commit-m   . ,(if keep 1 m))
        (:commit-n   . ,(if keep 0 1))
        (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))))))

(defun maf--resolve-map-relation (context opts)
  "Convert CONTEXT to an equation target when its subject is a relation.
Applies to home, entry, and subexpr targets: whenever the resolved :expr
is itself a relation, the body should run once per side, exactly as it
does when point sits on a relation entry's margin. Commands whose body
consumes the relation whole (solve, mapeq, the relation builders) opt out
with :map -1 in OPTS.

The equation keys are prepended, shadowing :target while keeping the base
target's commit fields — the rebuilt relation replaces whatever the base
target would have replaced."
  (let ((expr (alist-get :expr context)))
    (if (or (eql (alist-get :map opts) -1)
            (not (memq (alist-get :target context) '(home entry subexpr)))
            (not (maf--relation-p expr)))
        context
      (append `((:target . equation)
                (:rel-op . ,(car expr))
                (:lhs    . ,(math-normalize (nth 1 expr)))
                (:rhs    . ,(math-normalize (nth 2 expr))))
              context))))

(defun maf--resolve-context (opts)
  "Inspect point and calc state; return a context descriptor alist.

The returned alist contains:
  - target-specific keys (:target, :expr, :arg) for the matched target
  - all entries from OPTS (e.g. :arity, :prefix), merged in
  - ambient calc state (:keep)

Possible :target values, in order of priority:
  selection  Active calc selection; expr is the selected sub-expression.
  home       Point is at or below the . line.
  subexpr    Implicit selection. Point is inside an entry.
  equation   Entry is a relation (=, !=, <, <=, >, >=); body runs once per side.
  entry      Whole stack entry; point is at EOL or in the line-prefix zone.

Whenever the resolved subject (:expr) is itself a relation — the entry at
the margin, the entry at home, the shifted entry target, or the relation
node under point — the context is converted to the equation target so the
body runs once per side. Commands opt out with :map -1 in OPTS, keeping
the whole relation as :expr."
  (maf--with-calc-buffer
    (append (maf--resolve-map-relation
             (cond
              ((maf--sel-any-p)        (maf--resolve-target-selection opts))
              ((maf--at-home-p)        (maf--resolve-target-home opts))
              ((maf--at-subexpr-p)     (maf--resolve-target-subexpr opts))
              ((and (maf--at-equation-p)
                    (not (eql (alist-get :map opts) -1)))
                                       (maf--resolve-target-equation opts))
              ((maf--at-line-margin-p) (maf--resolve-target-entry opts))
              (t (error "Could not resolve target at point")))
             opts)
            ;; Also include options declared in the defcmd body like :arity, :prefix, etc
            opts
            ;; Include some useful properties as well like calc flag states
            `((:keep . ,calc-keep-args-flag)))))

(provide 'maf-resolve)
