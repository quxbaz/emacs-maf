;; -*- lexical-binding: t; -*-
;;
;; defcmd.el

(require 'maf-lib)

(defun maf-defcmd--parse-docstring (forms)
  "Return the docstring from FORMS if the first element is a string, else nil."
  (when (stringp (car forms))
    (car forms)))

;; TODO: Make :arity opt required
(defun maf-defcmd--parse-opts (forms)
  "Return an alist of keyword-value pairs from FORMS, skipping a leading docstring."
  ;; Strip docstring
  (when (stringp (car forms)) (pop forms))
  (let (final-opts)
    (while (keywordp (car forms))
      (seq-let (k v) (list (pop forms) (pop forms))
        (push (cons k v) final-opts)))
    final-opts))

(defun maf-defcmd--parse-body (forms)
  "Return the body forms from FORMS, skipping a leading docstring and keyword-value pairs."
  ;; Strip docstring and options
  (when (stringp (car forms)) (pop forms))
  (while (keywordp (car forms)) (pop forms) (pop forms))
  forms)

(defun maf-defcmd--parse-rest (forms)
  (let ((docstring (maf-defcmd--parse-docstring forms))
        (opts (maf-defcmd--parse-opts forms))
        (body (maf-defcmd--parse-body forms)))
    `(,docstring ,opts ,body)))

(defun maf--resolve-context ()
  "Inspect point and calc state; return a context descriptor.

Possible contexts, in order of priority:
  selection  Active calc selection; expr is the selected sub-expression.
  home       Point is at or below the . line.
  subexpr    Implicit selection. Point is inside an entry.
  equation   Entry is a relation (=, !=, <, <=, >, >=); body runs once per side.
  entry      Whole stack entry; point is at EOL, line-prefix zone, or line mode is forced."
  (maf--with-calc-buffer
   (cond ((maf--at-home-p) `((:kind . home)
                             (:expr . ,(calc-top 1 'full))))
         (t nil))))

(defmacro maf-defcmd (name bindings &rest rest)
  (declare (indent 2) (doc-string 3))
  (seq-let (docstring opts body) (maf-defcmd--parse-rest rest)

    ;; (message "docstring = %s" docstring)
    ;; (message "opts = %s" opts)
    ;; (message "body = %s" body)

    ;; @NOW: Extract bindings into (expr arg commit)

    ;; (let (((car bindings) (gensym "expr-")))xpr
    ;;   (message "bindings = %s" (car bindings)))

    ;; (setcar bindings 42)

    `(defun ,name ()
       ,docstring
       (interactive)
       ;; @NOW
       ;; Bind bindings in let form here.
       ;;
       ;;
       ;;
       ;;
       ;; TODO: Make bindings hygienic
       (let ((expr 42)
             (arg nil))
         (cl-flet ((commit (x) (message "%s" x)))
           ,@body)))

    ;; `(defmath ,name (a b)
    ;;    (interactive "p")
    ;;    ,@body)

    ))


;; ====================
;; TESTING
;; ====================

(defun test-mult ()
  (maf-defcmd maf-mult (expr arg commit)
    "Test multiplication function."
    :prefix "mult"
    ;; :simp t
    ;; :map t
    (commit (calcFunc-mul expr arg)))
  (maf--with-calc-buffer
    (calc-reset 0)
    ;; (calc-push '(var x var-x))
    (calc-push 2)
    (calc-push 3)
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

(test-double)
