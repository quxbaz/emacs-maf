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
  (cl-assert (equal (maf-history--classify '(b a) '(w x b a)) "change"))

  ;; From the stack alone, typing a value already on it looks exactly
  ;; like copying it. `maf-history--typed' reads the difference off the
  ;; trail instead: an entry goes through `calc-record' and stashes a
  ;; (PREFIX) — nil prefix and all — while a dup command pushes with
  ;; `calc-push' and records nothing, leaving the stash nil.
  (cl-assert (equal (maf-history--typed '(a) '(a a) '(nil)) "new"))
  (cl-assert (equal (maf-history--typed '(a) '(a a) nil) "dupe"))
  ;; Only a duplication is second-guessed; every other reading passes
  ;; through whichever way the value arrived.
  (cl-assert (equal (maf-history--typed '(b a) '(c b a) '(nil)) "new"))
  (cl-assert (equal (maf-history--typed '(b a) '(x a) '(nil)) "edit"))
  (cl-assert (equal (maf-history--typed '(c b a) '(b a) '(nil)) "del"))
  (cl-assert (equal (maf-history--typed '(b a) '(y x) nil) "change")))
