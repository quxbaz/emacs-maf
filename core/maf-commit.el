;; -*- lexical-binding: t; -*-
;;
;; maf-commit.el
;;
;; Apply a computed value to the calc buffer according to a resolved context.
;; The peer of maf-resolve: resolve reads point/state into a context alist;
;; commit consumes that alist and performs the appropriate calc operations.

(require 'maf-lib)
(require 'maf-chain)

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calc-top "calc-ext")
(declare-function calc-encase-atoms "calc-sel")
(declare-function calc-replace-sub-formula "calc-sel")
(defvar calc-use-selections)
(defvar calc-any-selections)
(defvar calc-stack)

(defun maf--commit-push (commit-n prefix val commit-m sels post-pop)
  "Push VAL at COMMIT-M (popping COMMIT-N entries there first), then optionally
pop POST-POP entries from the top of the stack (consuming any remaining
binary arg). SELS is the selection to restore on the pushed entry, or nil.
Must be called with the calc buffer current."
  (calc-pop-push-record-list commit-n prefix val commit-m sels)
  (when (> post-pop 0) (calc-pop-stack post-pop)))

(defun maf--commit (val context)
  "Commit VAL into the calc buffer according to CONTEXT.

Given the context, push or replace VAL into the correct location and pop
values where necessary.

For example, if point is at home and the command's arity is binary, pop the
top 2 stack values and push VAL onto the stack.

Return an alist describing where the result landed, consumed by anchor
point restoration: :node is the formula cons now sitting in the stack
entry (the spliced sub-formula for selection/subexpr, the whole pushed
formula otherwise) and :m is that entry's stack level after the pops."
  (maf--with-calc-buffer
    (let* ((target   (alist-get :target context))
           (prefix   (alist-get :prefix context))
           (commit-m (alist-get :commit-m context))
           (commit-n (alist-get :commit-n context))
           (post-pop (alist-get :post-pop context))
           (m        (alist-get :m context))
           ;; The target entry's level once post-pop consumes entries at
           ;; the top: every pop below it renumbers it down by one.
           (landed-m (- commit-m post-pop)))
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
           (maf--commit-push commit-n prefix new-formula commit-m sels post-pop)
           `((:node . ,val-encased) (:m . ,landed-m))))
        ('region
         ;; The run the body received is not a node in the entry, but
         ;; the chain it was carved from is: rebuild the chain with val
         ;; as one term in the run's place — the terms around it keep
         ;; their original conses — and splice the rebuilt chain at the
         ;; container's cons.
         (let* ((full-formula (calc-top m 'full))
                (val-encased  (calc-encase-atoms val))
                (new-chain    (maf--chain-build
                               (alist-get :chain-kind context)
                               (alist-get :pre-terms context)
                               val-encased
                               (alist-get :post-terms context)))
                (new-formula  (calc-replace-sub-formula
                               full-formula
                               (alist-get :chain-ref context)
                               new-chain)))
           (maf--commit-push commit-n prefix new-formula commit-m nil post-pop)
           `((:node . ,val-encased) (:m . ,landed-m))))
        ((or 'home 'entry 'equation)
         ;; For equation, val is the relation already reassembled by the
         ;; macro from both sides.  Calc normally redirects a nil-SELS push
         ;; into any active sub-formula selection.  Entry-scoped commands
         ;; deliberately bypass selections, so disable that redirection for
         ;; this operation; the replacement entry carries no selection.
         (let* ((entry-scoped-p
                 (eq (alist-get :scope context) 'entry))
                (calc-use-selections
                 (and (not entry-scoped-p) calc-use-selections)))
           (maf--commit-push commit-n prefix val commit-m nil post-pop)
           ;; calc-any-selections is a cache, not derived on every access.
           (when entry-scoped-p
             (setq calc-any-selections
                   (cl-some (lambda (entry) (nth 2 entry)) calc-stack))))
         `((:node . ,val) (:m . ,landed-m)))))))

(provide 'maf-commit)
