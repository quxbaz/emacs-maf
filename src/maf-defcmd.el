;; -*- lexical-binding: t; -*-
;;
;; maf-defcmd.el
;;
;; Defines the `maf-defcmd' macro for declaring contextual calc commands.
;; A defcmd inspects point and the calc stack at call time, resolves a context
;; (home, entry, selection, etc.), and commits its result to the right location.

(require 'maf-lib)
(require 'maf-resolve)

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

(defun maf--defcmd-commit (val context)
  "Commit VAL into the calc buffer according to CONTEXT.

Given the context, push or replace VAL into the correct location and pop
values where necessary.

For example, if point is at home and the command's arity is binary, pop the
top 2 stack values and push VAL onto the stack."
  (maf--with-calc-buffer
    (let* ((target (alist-get :target context))
           (prefix (alist-get :prefix context))
           (pop-n (alist-get :pop-n context)))
      (pcase target
        ('selection nil)   ;; TODO
        ('home      (calc-pop-push-record-list pop-n prefix val))
        ('subexpr   nil)   ;; TODO
        ('equation  nil)   ;; TODO
        ('entry     nil))))) ;; TODO

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
