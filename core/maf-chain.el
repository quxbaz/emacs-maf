;; -*- lexical-binding: t; -*-
;;
;; maf-chain.el
;;
;; Flatten and rebuild associative operator chains (+/- and *). A calc
;; sum is a left-nested binary tree ((a + b) + c) and a product is
;; right-nested (a * (b * c)); neither shape can express a contiguous
;; run of terms like "b + c" as a single node. These helpers view a
;; chain as its rendered term list — each term paired with the operator
;; glyph in front of it — so the region target can carve a run out of a
;; chain and commit can splice a result back in its place.
;;
;; Only the spine is flattened (left for sums, right for products,
;; matching how calc's reader nests each): an off-spine sub-chain
;; renders parenthesized, reads as a unit, and stays one term.

(require 'cl-lib)

(defun maf--chain-kind (expr)
  "Return EXPR's chain kind — `sum' or `prod' — or nil when not a chain."
  (pcase (car-safe expr)
    ((or '+ '-) 'sum)
    ('* 'prod)))

(defun maf--chain-terms (expr)
  "Flatten chain EXPR into a list of (OP . TERM) in rendering order.
TERM is the original cons (or encased atom) straight from the formula;
OP is the operator glyph rendered in front of the term — `+', `-', or
`*' — with the first term carrying the chain's identity (+ or *).
EXPR must be a chain per `maf--chain-kind'."
  (pcase (maf--chain-kind expr)
    ('sum
     (let (terms)
       (while (memq (car-safe expr) '(+ -))
         (push (cons (car expr) (nth 2 expr)) terms)
         (setq expr (nth 1 expr)))
       (cons (cons '+ expr) terms)))
    ('prod
     (let (terms)
       (while (eq (car-safe expr) '*)
         (push (cons '* (nth 1 expr)) terms)
         (setq expr (nth 2 expr)))
       (nreverse (cons (cons '* expr) terms))))))

(defun maf--chain-fold (terms)
  "Fold TERMS — (OP . TERM) as from `maf--chain-terms' — into one expression.
Sums fold along the left spine and products along the right, the
shapes calc's reader builds. A run sliced from mid-chain may lead with
a - term; it contributes negated, so the fold is exactly the value the
run adds to its chain — never re-read, never normalized."
  (if (eq (caar terms) '*)
      (cl-reduce (lambda (a b) (list '* a b)) (mapcar #'cdr terms)
                 :from-end t)
    (let ((acc (if (eq (caar terms) '-)
                   (list 'neg (cdar terms))
                 (cdar terms))))
      (dolist (term (cdr terms))
        (setq acc (list (car term) acc (cdr term))))
      acc)))

(defun maf--chain-build (kind pre val post)
  "Rebuild a KIND chain: PRE terms, then VAL, then POST terms.
PRE and POST are (OP . TERM) lists from `maf--chain-terms', their TERM
conses kept intact so untouched text re-renders identically. VAL joins
with the chain's identity operator (+ or *), carrying its run's sign in
its value — except that a VAL which is itself a KIND chain joins as its
own terms: the run it replaces was terms of this chain, and a same-kind
result reads as terms in its place, not as a parenthesized unit. That
absorption only reassociates; the value is untouched."
  (maf--chain-fold
   (append pre
           (if (eq (maf--chain-kind val) kind)
               (maf--chain-terms val)
             (list (cons (if (eq kind 'prod) '* '+) val)))
           post)))

(provide 'maf-chain)
