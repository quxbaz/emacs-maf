;; -*- lexical-binding: t; -*-
;;
;; maf-resolve.el
;;
;; Resolve point and calc state into a target-specific context descriptor.

(require 'maf-lib)
(require 'maf-sel)

(defun maf--resolve-target-selection (opts)
  "Return the selection target's context alist.
:expr is the selected sub-expression. The chosen entry is the one under point
when it has a selection, otherwise the top-most entry with an active selection."
  (ignore opts)
  (maf--with-calc-buffer
    `((:target    . selection)
      (:expr      . ,(maf--sel-effective-expr))
      (:m         . ,(maf--sel-effective-m)))))

(defun maf--resolve-target-home (opts)
  "Return the home target's context alist."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (unary? (eq arity 'unary))
           (binary? (eq arity 'binary))
           (keep calc-keep-args-flag))
      `((:target . home)
        (:expr   . ,(calc-top 1 'full))
        (:arg    . ,(cond (unary? nil)
                          (binary? (calc-top 2 'full))
                          (t (error "Unknown arity: %s" arity))))
        (:pop-n  . ,(if keep 0 (cond (unary? 1)
                                     (binary? 2)
                                     (t (error "Unknown arity: %s" arity)))))))))

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
             ((maf--sel-any-p) (maf--resolve-target-selection opts)) ;; TODO
             ((maf--at-home-p)       (maf--resolve-target-home opts))
             ((maf--at-subexpr-p)    (maf--resolve-target-subexpr opts))   ;; TODO
             ((maf--at-equation-p)   (maf--resolve-target-equation opts))  ;; TODO
             ((maf--at-entry-p)      (maf--resolve-target-entry opts))     ;; TODO
             (t (error "Could not resolve target at point")))
            ;; Also include options declared in the defcmd body like :arity, :prefix, etc
            opts
            ;; Include some useful properties as well like calc flag states
            `((:keep . ,calc-keep-args-flag)))))

(provide 'maf-resolve)
