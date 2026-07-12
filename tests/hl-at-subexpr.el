(defun maf-hl-test--text ()
  "Text under the maf-hl overlay, or nil if no highlight is shown."
  (and maf-hl--overlay (overlay-buffer maf-hl--overlay)
       (buffer-substring-no-properties (overlay-start maf-hl--overlay)
                                       (overlay-end maf-hl--overlay))))

(maf-step
  (calc-push '(* 2 (+ (* 3 (var x var-x)) 4)))
  (maf-hl-mode 1)
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1) (maf-hl--update))
  (cl-assert (equal (maf-hl-test--text) "x"))
  (progn (goto-char (point-min)) (search-forward "+") (backward-char 1) (maf-hl--update))
  (cl-assert (equal (maf-hl-test--text) "(3 x + 4)"))
  (progn (goto-char (point-min)) (search-forward "3 ") (backward-char 1) (maf-hl--update))
  (cl-assert (equal (maf-hl-test--text) "3 x"))
  (progn (goto-char (point-max)) (maf-hl--update))
  (cl-assert (null (maf-hl-test--text)))
  (maf-hl-mode -1)
  (cl-assert (null (maf-hl-test--text))))
