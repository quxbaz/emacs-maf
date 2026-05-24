;; -*- lexical-binding: t; -*-
;;
;; defcmd.el

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
        ;; Unwrap quotes so values are assigned to symbols, not quoted symbols.
        (push (cons k (if (eq (car-safe v) 'quote) (cadr v) v)) final-opts)))
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
  "Inspect point and calc state; return a context descriptor.

Possible contexts, in order of priority:
  selection  Active calc selection; expr is the selected sub-expression.
  home       Point is at or below the . line.
  subexpr    Implicit selection. Point is inside an entry.
  equation   Entry is a relation (=, !=, <, <=, >, >=); body runs once per side.
  entry      Whole stack entry; point is at EOL, line-prefix zone, or line mode is forced."

  (with-current-buffer (get-buffer "*scratch*")
    (end-of-buffer)
    (pp (equal (alist-get :arity opts) 'binary) (get-buffer "*scratch*"))
    (let ((print-quoted nil))
      (print (alist-get :arity opts) (get-buffer "*scratch*"))))

  (maf--with-calc-buffer
    (cond ((maf--at-home-p) `((:kind . home)
                              (:expr . ,(calc-top 1 'full))
                              (:arg  . ,(when (eq (alist-get :arity opts) 'binary)
                                          (calc-top 2 'full)))))
          (t nil))))

(defun maf--defcmd-commit (val context)
  ;; do stuff here
  (message "val = %s" val)
  ;; (let ((kind VALUE))
  ;;   )
  )

(defmacro maf-defcmd (name bindings &rest rest)
  (declare (indent 2) (doc-string 3))
  (pcase-let* ((`(,docstring ,opts ,body) (maf--defcmd-parse-rest rest))
               (`(,expr ,arg ,commit) bindings)
               (context (gensym "context-")))
    (maf--defcmd-validate-opts opts)
    `(defun ,name ()
       ,@(when docstring (list docstring))
       (interactive)
       (let ((,context (maf--resolve-context ',opts)))
         (let ((,expr (alist-get :expr ,context))
               (,arg (alist-get :arg ,context)))
           (cl-flet ((,commit (val) (maf--defcmd-commit val ,context)))
             ,@body))))))


;; ===================
;; ***** TESTING *****
;; ===================

(defun test-mult ()
  (maf-defcmd maf-mult (expr arg commit)
    "Test multiplication function."
    :arity 'binary
    :prefix "mult"
    ;; :simp t
    ;; :map t
    (commit (calcFunc-mul expr arg)))

  (maf--with-calc-buffer
    (calc-reset 0)
    ;; (calc-push '(var x var-x))
    (calc-push 2)
    (calc-push 3)
    (calc-align-stack-window)
    (call-interactively 'maf-mult)))

(defun test-double ()
  (maf-defcmd maf-double (expr arg commit)
    "Test multiplication function."
    :arity 'unary
    :prefix "double"
    (commit (calcFunc-mul expr 2)))

  (maf--with-calc-buffer
    (calc-reset 0)
    ;; (calc-push '(var x var-x))
    (calc-push 3)
    (call-interactively 'maf-double)))

(test-mult)
