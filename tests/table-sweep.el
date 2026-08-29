;; Sweep every mafcmd table row (`maf-cmds--table'): run each command
;; at home over symbolic operands and compare its committed result
;; against the row's function applied the way the row's body applies
;; it — through `calc-normalize'. One assertion per aspect, each over
;; the whole table, so a failure lists the rows that broke: the
;; `maf-operation' stamp, the application itself, and the I/H/I H
;; flag routes reaching each linked variant.

(defvar sweep-q (math-read-expr "q"))
(defvar sweep-r (math-read-expr "r"))

(defun sweep-want (func nargs)
  "FUNC over the sweep operands, as a row's body applies it.
Two operands mirror a binary's expr/arg order: level 2, then top."
  (calc-normalize (if (= nargs 2)
                      (list func sweep-q sweep-r)
                    (list func sweep-r))))

(defun sweep-got (cmd flags)
  "Run CMD at home over fresh operands and return the committed top.
FLAGS is nil, `inv', `hyp', or `invhyp' — the calc flag(s) set for the
call. The stack is emptied afterwards, error or not."
  (unwind-protect
      (progn
        (calc-push sweep-q)
        (calc-push sweep-r)
        (goto-char (point-max))
        (let ((calc-inverse-flag (and (memq flags '(inv invhyp)) t))
              (calc-hyperbolic-flag (and (memq flags '(hyp invhyp)) t)))
          (call-interactively cmd))
        (calc-top 1 'full))
    (calc-pop (calc-stack-size))))

(defun sweep-check (cmd flags func nargs)
  "Compare CMD run under FLAGS against FUNC/NARGS; nil when they agree.
A command that signals matches a direct application signaling the same
error symbol, so a row whose function rejects symbolic operands still
passes when the command surfaces that rejection unchanged."
  (let ((want (condition-case e (sweep-want func nargs)
                (error (list :signal (car e)))))
        (got (condition-case e (sweep-got cmd flags)
               (error (list :signal (car e))))))
    (unless (equal got want)
      (list cmd flags :want want :got got))))

(defun sweep-stamp-failures ()
  "Rows whose `maf-operation' stamp differs from their data row."
  (let (bad)
    (pcase-dolist (`(,name ,arity ,func . ,_) maf-cmds--table)
      (unless (equal (get name 'maf-operation)
                     (cons func (if (eq arity 'binary) 2 1)))
        (push name bad)))
    (nreverse bad)))

(defun sweep-apply-failures ()
  "Rows whose direct call does not commit their function's application."
  (let (bad)
    (pcase-dolist (`(,name ,arity ,func . ,_) maf-cmds--table)
      (let ((miss (sweep-check name nil func (if (eq arity 'binary) 2 1))))
        (when miss (push miss bad))))
    (nreverse bad)))

(defun sweep-flag-failures ()
  "Flag links whose flagged base call does not answer as the variant.
The expected function and operand count come from the variant's own
`maf-operation' stamp, so a link may cross arities."
  (let (bad)
    (pcase-dolist (`(,name ,_arity ,_func ,_key ,inv ,hyp ,invhyp)
                   maf-cmds--table)
      (pcase-dolist (`(,flags . ,variant)
                     `((inv . ,inv) (hyp . ,hyp) (invhyp . ,invhyp)))
        (when variant
          (let* ((op (get variant 'maf-operation))
                 (miss (and op (sweep-check name flags (car op) (cdr op)))))
            (cond ((null op) (push (list name flags :unstamped variant) bad))
                  (miss (push miss bad)))))))
    (nreverse bad)))

(maf-step
  ;; The registry holds the whole table, one data row per command.
  (cl-assert (< 200 (length maf-cmds--table)))

  ;; Every command's maf-operation stamp matches its row, so the
  ;; combinators see the function and operand count the body applies.
  (cl-assert (null (sweep-stamp-failures)))

  ;; Every command commits its function over the resolved operands.
  (cl-assert (null (sweep-apply-failures)))

  ;; Every I/H/I H link routes the flagged base key to its variant.
  (cl-assert (null (sweep-flag-failures))))
