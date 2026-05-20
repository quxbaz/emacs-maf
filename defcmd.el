(defmacro maf-cmd (bindings &rest body)
  (declare (indent 2)))


;; Example
(maf-cmd mult (expr arg commit)
  :prefix "*"
  (let ((product (calcFunc-mul expr arg)))
    (commit product)))
