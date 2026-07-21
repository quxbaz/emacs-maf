(maf-step
  ;; Stacks are top-first lists; dummy symbol values suffice for `equal'.

  ;; A new entry added — on top, in the middle, or at the bottom; the
  ;; rest unchanged. Added anywhere counts as `new'.
  (cl-assert (equal (maf-timeline--classify '(b a) '(c b a)) "new"))
  (cl-assert (equal (maf-timeline--classify '(c b a) '(c b x a)) "new"))
  (cl-assert (equal (maf-timeline--classify '(c b a) '(c b a d)) "new"))
  ;; The first entry on an empty stack.
  (cl-assert (equal (maf-timeline--classify '() '(a)) "new"))

  ;; Exactly one value changed in place — an edit.
  (cl-assert (equal (maf-timeline--classify '(b a) '(x a)) "edit"))
  (cl-assert (equal (maf-timeline--classify '(a) '(z)) "edit"))

  ;; Entries removed.
  (cl-assert (equal (maf-timeline--classify '(c b a) '(b a)) "del"))

  ;; Two values changed, or grew by more than one — not a simple add or
  ;; edit.
  (cl-assert (equal (maf-timeline--classify '(b a) '(y x)) "change"))
  (cl-assert (equal (maf-timeline--classify '(b a) '(w x b a)) "change")))
