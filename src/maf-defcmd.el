;; -*- lexical-binding: t; -*-
;;
;; maf-defcmd.el

(require 'maf-lib)

(defun maf--defcmd-parse-docstring (forms)
  "Return the docstring from FORMS if the first element is a string, else nil."
  (when (stringp (car forms))
    (car forms)))

(defun maf--defcmd-parse-opts (forms)
  "Return an alist of keyword-value pairs from FORMS, skipping a leading docstring."
  ;; Strip docstring
  (when (stringp (car forms)) (pop forms))
  (let (final-opts)
    (while (keywordp (car forms))
      (seq-let (k v) (list (pop forms) (pop forms))
        (push (cons k v) final-opts)))
    final-opts))

(defun maf--defcmd-validate-opts (opts)
  "Validate OPTS, signaling an error if any are invalid."
  (unless (alist-get :arity opts)
    (error "Missing required option :arity")))

(defun maf--defcmd-parse-body (forms)
  "Return the body forms from FORMS, skipping a leading docstring and keyword-value pairs."
  ;; Strip docstring and options
  (when (stringp (car forms)) (pop forms))
  (while (keywordp (car forms)) (pop forms) (pop forms))
  forms)

(defun maf--defcmd-parse-rest (forms)
  (let ((docstring (maf--defcmd-parse-docstring forms))
        (opts (maf--defcmd-parse-opts forms))
        (body (maf--defcmd-parse-body forms)))
    `(,docstring ,opts ,body)))

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
    (let* ((keep calc-keep-args-flag)
           (arity (alist-get :arity opts))
           (unary? (eq arity 'unary))
           (binary? (eq arity 'binary)))
      (append (cond ((maf--at-home-p) `((:target . home)
                                        (:expr   . ,(calc-top 1 'full))
                                        (:arg    . ,(cond (unary? nil) (binary? (calc-top 2 'full))))
                                        (:pop-n  . ,(if keep 0 (cond (unary? 1) (binary? 2))))))
                    (t nil))
              ;; Also include options declared in the defcmd body like :arity, :prefix, etc
              opts
              ;; Include some useful properties as well like calc flag states
              `((:keep . ,keep))))))

;; @NOW
;;
;; This function takes a value (user provided) and context structure. Given the
;; context, it pushes or replaces the given value into the correct location, and
;; then pops the values where necessary.
;;
;; For example, if point is at home, and the command is 'binary, this function
;; should pop the top stack value and push `val` onto the stack.
;;
;; It should handle the rest of the possible contexts appropriately.
(defun maf--defcmd-commit (val context)
  (maf--with-calc-buffer
    (let* ((target (alist-get :target context))
           (prefix (alist-get :prefix context))
           (pop-n (alist-get :pop-n context)))
      (pcase target
        ('home (calc-pop-push-record-list pop-n prefix val))))))

(defmacro maf-defcmd (name bindings &rest rest)
  (declare (indent 2) (doc-string 3))
  (pcase-let* ((`(,docstring ,opts ,body) (maf--defcmd-parse-rest rest))
               (`(,expr ,arg ,commit) bindings)
               (context (gensym "context-")))
    (maf--defcmd-validate-opts opts)
    `(defun ,name ()
       ,@(when docstring (list docstring))
       (interactive)
       (let* ((,context (maf--resolve-context ',opts))
              (,expr (alist-get :expr ,context))
              (,arg (alist-get :arg ,context)))
         (cl-flet ((,commit (val) (maf--defcmd-commit val ,context)))
           ,@body)))))

(provide 'maf-defcmd)

;; ===================
;; ***** TESTING *****
;; ===================

(defun test-mult ()
  (maf-defcmd maf-mult (expr arg commit)
    "Test multiplication function."
    :arity binary
    :prefix "mult"
    ;; :simp t
    ;; :map t
    (commit (calcFunc-mul expr arg)))

  (maf--with-calc-buffer
    (calc-reset 0)
    (maf-debug-slowly
      (calc-push 3)
      (calc-push 2)
      (call-interactively 'maf-mult))))

(defun test-double ()
  (maf-defcmd maf-double (expr arg commit)
    "Test multiplication function."
    :arity unary
    :prefix "double"
    (commit (calcFunc-mul expr 2)))

  (maf--with-calc-buffer
    (calc-reset 0)
    ;; (calc-push '(var x var-x))
    (calc-push 3)
    (call-interactively 'maf-double)))

(test-mult)
