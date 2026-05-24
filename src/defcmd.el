;; -*- lexical-binding: t; -*-


(defun maf-defcmd--parse-docstring (forms)
  "TODO: Add docstring"
  (when (stringp (car forms))
    (car forms)))

(defun maf-defcmd--parse-opts (forms)
  "TODO: Add docstring"
  ;; Strip docstring
  (when (stringp (car forms)) (pop forms))
  (let (final-opts)
    (while (keywordp (car forms))
      (seq-let (k v) (list (pop forms) (pop forms))
        (push (cons k v) final-opts)))
    final-opts))

(defun maf-defcmd--parse-body (forms)
  "TODO: Add docstring"
  ;; Strip docstring and options
  (when (stringp (car forms)) (pop forms))
  (while (keywordp (car forms)) (pop forms) (pop forms))
  forms)

(defun maf-defcmd--parse-rest (forms)
  (let ((docstring (maf-defcmd--parse-docstring forms))
        (opts (maf-defcmd--parse-opts forms))
        (body (maf-defcmd--parse-body forms)))
    `(,docstring ,opts ,body)))

(defmacro maf-defcmd (name bindings &rest rest)
  (declare (indent 2) (doc-string 3))
  (seq-let (docstring opts body) (maf-defcmd--parse-rest rest)
    (message "docstring = %s" docstring)
    (message "opts = %s" opts)
    (message "body = %s" body))
  ;; `(defmath ,name (a b)
  ;;    (interactive "p")
  ;;    ,@body)
  )


;; Example
(maf-defcmd maf/mult ()

  "This is an example docstring."

  :prefix "*"
  :simp t
  :map t

  (+ 1 2)

  ;; (let ((product (* expr arg)))
  ;;   ;; (commit product)
  ;;   product
  ;;   )

  )

;; (with-current-buffer (calc-select-buffer)
;;   (calc-reset 0)
;;   (calc-push '(var x var-x))
;;   (calc-push 1)
;;   (call-interactively 'calc-maf/mult))


;; Testing
