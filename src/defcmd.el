;; -*- lexical-binding: t; -*-

(defun maf--collect-options (body)
  "Returns options in a structured format."
  nil)

(defmacro maf-defcmd (name bindings &rest body)
  (declare (indent 2))
  `(defmath ,name (a b)
     (interactive "p")
     ,@body))


;; Example
(maf-defcmd maf/mult ()

  ;; :prefix "*"
  ;; :simp t
  ;; :map t

  (let ((product (* expr arg)))
    ;; (commit product)
    product
    )

  )

(with-current-buffer (calc-select-buffer)
  (calc-reset 0)
  (calc-push '(var x var-x))
  (calc-push 1)
  (call-interactively 'calc-maf/mult))


;; Testing
