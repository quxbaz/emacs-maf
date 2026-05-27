;; -*- lexical-binding: t; -*-
;;
;; maf-commit.el
;;
;; Apply a computed value to the calc buffer according to a resolved context.
;; The peer of maf-resolve: resolve reads point/state into a context alist;
;; commit consumes that alist and performs the appropriate calc operations.

(require 'maf-lib)

(defun maf--commit-push (push-n prefix val push-m sels post-pop-n)
  "Push VAL at PUSH-M (popping PUSH-N entries there first), then optionally
pop POST-POP-N entries from the top of the stack (consuming any remaining
binary arg). SELS is the selection to restore on the pushed entry, or nil.
Must be called with the calc buffer current."
  (calc-pop-push-record-list push-n prefix val push-m sels)
  (when (> post-pop-n 0) (calc-pop-stack post-pop-n)))

(defun maf--commit (val context)
  "Commit VAL into the calc buffer according to CONTEXT.

Given the context, push or replace VAL into the correct location and pop
values where necessary.

For example, if point is at home and the command's arity is binary, pop the
top 2 stack values and push VAL onto the stack."
  (maf--with-calc-buffer
    (let* ((target     (alist-get :target context))
           (prefix     (alist-get :prefix context))
           (push-m     (alist-get :push-m context))
           (push-n     (alist-get :push-n context))
           (post-pop-n (alist-get :post-pop-n context))
           (m          (alist-get :m context)))
      (pcase target
        ('selection
         (let* ((expr         (alist-get :expr context))
                (full-formula (calc-top m 'full))
                (new-formula  (calc-replace-sub-formula full-formula expr val)))
           (maf--commit-push push-n prefix new-formula push-m val post-pop-n)))
        ('home  (maf--commit-push push-n prefix val push-m nil post-pop-n))
        ('entry (maf--commit-push push-n prefix val push-m nil post-pop-n))
        ('subexpr  nil) ;; TODO
        ('equation nil)))));; TODO

(provide 'maf-commit)
