;; -*- lexical-binding: t; -*-
;;
;; maf-defcmd.el
;;
;; Defines the `maf-defcmd' macro for declaring contextual calc commands.
;; A defcmd inspects point and the calc stack at call time, resolves a context
;; (home, entry, selection, etc.), and commits its result to the right location.

(require 'maf-lib)
(require 'maf-resolve)
(require 'maf-commit)

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
  (let ((arity (alist-get :arity opts)))
    (unless arity
      (error "Missing required option :arity"))
    (unless (memq arity '(unary binary))
      (error "Invalid :arity %s (expected unary or binary)" arity))))

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

(defmacro maf-defcmd (name bindings &rest rest)
  (declare (indent 2) (doc-string 3))
  (pcase-let* ((`(,docstring ,opts ,body) (maf--defcmd-parse-rest rest))
               (`(,expr ,arg ,commit) bindings)
               (context (gensym "context-"))
               (lhs (gensym "lhs-"))
               (rhs (gensym "rhs-")))
    (maf--defcmd-validate-opts opts)
    `(defun ,name ()
       ,@(when docstring (list docstring))
       (interactive)
       (let* ((,context (maf--resolve-context ',opts))
              (,arg (alist-get :arg ,context)))
         (if (eq (alist-get :target ,context) 'equation)
             ;; Equation target: run the body once per side (expr bound to the
             ;; LHS, then the RHS), capturing each side's committed result.
             ;; Then reassemble into a new relation and commit once. arg is
             ;; bound once above, so both sides share it.
             (let (,lhs ,rhs)
               (let ((,expr (alist-get :lhs ,context)))
                 (cl-flet ((,commit (val) (setq ,lhs val)))
                   ,@body))
               (let ((,expr (alist-get :rhs ,context)))
                 (cl-flet ((,commit (val) (setq ,rhs val)))
                   ,@body))
               (maf--commit (list (alist-get :rel-op ,context) ,lhs ,rhs)
                            ,context))
           ;; All other targets: body runs once with :expr.
           (let ((,expr (alist-get :expr ,context)))
             (cl-flet ((,commit (val) (maf--commit val ,context)))
               ,@body)))))))

(provide 'maf-defcmd)
