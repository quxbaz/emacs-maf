;; -*- lexical-binding: t; -*-
;;
;; stack.el
;;
;; Hand-written contextual stack commands: composites with no single
;; calcFunc equivalent.

(require 'maf-defcmd)

;; These live in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calcFunc-mul "calc-arith")
(declare-function calcFunc-div "calc-arith")
(declare-function calcFunc-nrat "calc-poly")
(declare-function calcFunc-expand "calc-poly")
(declare-function math-simplify "calc-alg")
(declare-function calc-undo "calc-undo")
(declare-function calc-redo "calc-undo")

(maf-defcmd mafcmd-factor-by (expr arg commit)
  "Factor the resolved expression by the top-of-stack argument.
Divides EXPR by ARG, normalizes the quotient (expand -> nrat -> expand ->
simplify), and commits ARG * quotient with the product left undistributed:
6 x + 12 factored by 6 gives 6 (x + 2), not 6 x + 12 back.

Contextual like every mafcmd: with point on a sub-formula it factors just
that sub-formula; on an equation it factors each side; at home it factors
stack level 2 by level 1."
  :arity binary
  :prefix "fctr"
  (let ((quotient (math-simplify
                   (calcFunc-expand
                    (calcFunc-nrat
                     (calcFunc-expand (calcFunc-div expr arg)))))))
    ;; Build the product literally; commit pushes structurally, so the
    ;; factored form survives without calc-normalize distributing it.
    (commit (let ((calc-simplify-mode 'none))
              (calcFunc-mul arg quotient)))))

(defun maf-undo (n)
  "Like `calc-undo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-undo n)))

(defun maf-redo (n)
  "Like `calc-redo', but keep point in place instead of jumping home."
  (interactive "p")
  (maf--preserve-point (calc-redo n)))

(provide 'maf-stack)
