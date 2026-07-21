(maf-step
  ;; Unnamed states read as "entry": a plain entry (nil) and calc's
  ;; "..." continuation prefix alike.
  (cl-assert (equal (maf-timeline--strip-label '((1) nil)) "entry"))
  (cl-assert (equal (maf-timeline--strip-label '((1) "...")) "entry"))
  (cl-assert (equal (maf-timeline--strip-label '((1) "fctr")) "fctr"))

  (let ((maf-timeline--states
         (list (list (list 1) "nrat") (list (list 1) "expand")
               (list (list 1) "fctr") (list (list 1) "mult")
               (list (list 1) nil)    (list (list 1) "add")))
        (maf-timeline-strip-radius 3))
    ;; Newest (index 0): older overflow on the left (…), current at the
    ;; right end, older→newer left to right, · separators.
    (cl-assert (equal (substring-no-properties (maf-timeline--strip 6 0))
                      "… mult · fctr · expand · nrat"))

    ;; Middle (index 2): whole window fits, no ellipses; the nil label
    ;; renders as the `entry' tag.
    (cl-assert (equal (substring-no-properties (maf-timeline--strip 6 2))
                      "add · entry · mult · fctr · expand · nrat"))

    ;; Oldest (index 5): newer overflow on the right (…), current at the
    ;; left end.
    (cl-assert (equal (substring-no-properties (maf-timeline--strip 6 5))
                      "add · entry · mult · fctr …"))

    ;; The current operation carries the highlight face.
    (let ((s (maf-timeline--strip 6 2)))
      (cl-assert (text-property-any 0 (length s)
                                    'face 'maf-timeline-strip-current s)))))
