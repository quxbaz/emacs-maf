;; -*- lexical-binding: t; -*-


(defun maf-defcmd--parse-docstring (forms)
  "TODO: Add docstring"
  (if (stringp (car forms))
      (car forms)))

(defun maf-defcmd--parse-opts (forms)
  "TODO: Add docstring"
  "opts")

(defun maf-defcmd--parse-rest (forms)
  (let ((docstring (maf-defcmd--parse-docstring forms))
        (opts (maf-defcmd--parse-opts forms))
        (body 3))
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
