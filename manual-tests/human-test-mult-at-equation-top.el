;; Edge case: a binary command on a relation that IS the top entry.
;; The arg would have to come from the relation itself, so resolve rejects it.

(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command."
  :arity binary
  :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(maf--debug-setup-test)

(maf--debug-slowly :delay 0.3
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (progn
    (calc-refresh)
    (goto-char 0))                      ; relation at top (m=1), margin
  (progn
    (let ((errored nil))
      (condition-case nil
          (call-interactively 'maf-mult)
        (error (setq errored t)))
      (if errored
          (message "PASS mult-at-equation-top — binary at top relation rejected")
        (error "FAIL mult-at-equation-top: expected an error, command succeeded")))))
