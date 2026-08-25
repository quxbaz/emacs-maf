(maf-step
  ;; Stacks are top-first lists; dummy symbol values suffice for `equal'.

  ;; A new entry added — on top, in the middle, or at the bottom; the
  ;; rest unchanged. Added anywhere counts as `new'.
  (cl-assert (equal (maf-history--classify '(b a) '(c b a)) "new"))
  (cl-assert (equal (maf-history--classify '(c b a) '(c b x a)) "new"))
  (cl-assert (equal (maf-history--classify '(c b a) '(c b a d)) "new"))
  ;; The first entry on an empty stack.
  (cl-assert (equal (maf-history--classify '() '(a)) "new"))

  ;; An added entry the stack already held is a duplication, not a fresh
  ;; entry — RET on a whole entry, wherever the copy lands.
  (cl-assert (equal (maf-history--classify '(b a) '(b b a)) "dupe"))
  (cl-assert (equal (maf-history--classify '(b a) '(a b a)) "dupe"))
  (cl-assert (equal (maf-history--classify '(b a) '(b a a)) "dupe"))
  (cl-assert (equal (maf-history--classify '(a) '(a a)) "dupe"))

  ;; Exactly one value changed in place — an edit.
  (cl-assert (equal (maf-history--classify '(b a) '(x a)) "edit"))
  (cl-assert (equal (maf-history--classify '(a) '(z)) "edit"))

  ;; Entries removed.
  (cl-assert (equal (maf-history--classify '(c b a) '(b a)) "del"))

  ;; Two values changed, or grew by more than one — not a simple add or
  ;; edit.
  (cl-assert (equal (maf-history--classify '(b a) '(y x)) "change"))
  (cl-assert (equal (maf-history--classify '(b a) '(w x b a)) "change")))
