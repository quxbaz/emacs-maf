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
;;                 selected sub-formula, depending on target).
;;   :arg          Second operand for binary commands; nil for unary.
;;   :m            Stack position (1 = top) of the target entry. Only set when
;;                 the target lives at a specific stack level (e.g. selection).
;;
;; Commit instructions (consumed by `maf--defcmd-commit'):
;;
;;   :push-m       Stack level where the result is pushed.
;;   :push-n       N argument to `calc-pop-push-record-list' — number of
;;                 entries popped at :push-m before pushing.
;;   :post-pop-n   Number of entries popped from the top *after* the push,
;;                 to consume extra inputs (e.g. the binary arg on selection).
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
           (keep calc-keep-args-flag))
      ;; If m=1 and arity=binary then there's nowhere to take the arg from - reject.
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on selection require the selected entry below the top"))
      `((:target     . selection)
        (:expr       . ,(maf--sel-effective-expr))
        (:arg        . ,(pcase arity ('unary nil) ('binary (calc-top 1 'full))))
        (:m          . ,m)
        (:push-m     . ,(if keep 1 m))
        (:push-n     . ,(if keep 0 1))
        (:post-pop-n . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))))))

(defun maf--resolve-target-home (opts)
  "Return the home target's context alist."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (keep calc-keep-args-flag))
      `((:target     . home)
        (:expr       . ,(calc-top 1 'full))
        (:arg        . ,(pcase arity ('unary nil) ('binary (calc-top 2 'full))))
        (:push-m     . 1)
        (:push-n     . ,(if keep 0 (pcase arity ('unary 1) ('binary 2))))
        (:post-pop-n . 0)))))

(defun maf--resolve-target-subexpr (opts)
  "Return the subexpr target's context alist.
Point is inside an entry's formula text; :expr is the implicit sub-expression
under cursor. Commit replaces the sub-expression in-place."
  (ignore opts)
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (calc-prepare-selection m)
      `((:target . subexpr)
        (:expr   . ,(calc-find-selected-part))
        (:m      . ,m)))))

(defun maf--resolve-target-equation (opts)
  "Return the equation target's context alist.
Stack entry under point is a relation. The body is expected to run once per
side: commit must iterate with :expr bound to :lhs, then to :rhs.
TODO: the macro/commit dispatch doesn't yet implement the per-side iteration."
  (ignore opts)
  (maf--with-calc-buffer
    (let* ((m    (calc-locate-cursor-element (point)))
           (expr (calc-top m 'full)))
      `((:target . equation)
        (:expr   . ,expr)
        (:lhs    . ,(nth 1 expr))
        (:rhs    . ,(nth 2 expr))
        (:m      . ,m)))))

(defun maf--resolve-target-entry (opts)
  "Return the entry target's context alist.
Point is on a stack entry but not on a sub-expression; :expr is the whole
formula. Commit replaces the entry in-place."
  (ignore opts)
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      `((:target . entry)
        (:expr   . ,(calc-top m 'full))
        (:m      . ,m)))))

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
  entry      Whole stack entry; point is at EOL, line-prefix zone, or line mode is forced."
  (maf--with-calc-buffer
    (append (cond
             ((maf--sel-any-p)        (maf--resolve-target-selection opts)) ;; TODO
             ((maf--at-home-p)        (maf--resolve-target-home opts))
             ((maf--at-subexpr-p)     (maf--resolve-target-subexpr opts))   ;; TODO
             ((maf--at-equation-p)    (maf--resolve-target-equation opts))  ;; TODO
             ((maf--at-line-margin-p) (maf--resolve-target-entry opts))     ;; TODO
             (t (error "Could not resolve target at point")))
            ;; Also include options declared in the defcmd body like :arity, :prefix, etc
            opts
            ;; Include some useful properties as well like calc flag states
            `((:keep . ,calc-keep-args-flag)))))

(provide 'maf-resolve)
