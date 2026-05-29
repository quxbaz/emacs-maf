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
        ((or 'selection 'subexpr)
         ;; Body received the clean :expr and produced a clean val. Splice
         ;; val back into the entry by matching the encased :expr-ref against
         ;; the cons in the stack's formula (only the encased ref is eq).
         ;;
         ;; Pre-encase val ourselves so we hold a reference to the cons that
         ;; ends up in new-formula. calc-replace-sub-formula would encase its
         ;; replacement internally anyway — doing it up front lets us reuse
         ;; the same cons as :reselect's sels, so the new entry's selection
         ;; slot is eq to the sub-formula in its own formula.
         (let* ((expr-ref     (alist-get :expr-ref context))
                (full-formula (calc-top m 'full))
                (val-encased  (calc-encase-atoms val))
                (new-formula  (calc-replace-sub-formula full-formula expr-ref val-encased))
                ;; Carry val-encased as the new selection only if :reselect is set
                ;; (selection had an explicit user selection; subexpr did not).
                (sels         (when (alist-get :reselect context) val-encased)))
           (maf--commit-push push-n prefix new-formula push-m sels post-pop-n)))
        ('home  (maf--commit-push push-n prefix val push-m nil post-pop-n))
        ('entry (maf--commit-push push-n prefix val push-m nil post-pop-n))
        ;; val is the relation already reassembled by the macro from both sides.
        ('equation (maf--commit-push push-n prefix val push-m nil post-pop-n))))))

(provide 'maf-commit)
