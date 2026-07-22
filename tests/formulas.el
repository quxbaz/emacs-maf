;; Self-contained: the real formulas now live in `maf-formulas-file'
;; (the user's Emacs config), so this test supplies its own fixture in
;; `maf-formulas-user' and marks the file already-consulted so nothing
;; on disk is read. The last form restores the session state.

(maf-step
  (setq maf--formulas-stash (list maf-formulas-user maf-formulas--loaded)
        maf-formulas--loaded t          ; skip loading maf-formulas-file
        maf-formulas-user
        '((:name "volume-of-sphere" :title "Volume of sphere"
           :category "Geometry — 3D: Sphere"
           :expr (calcFunc-eq (var V var-V)
                              (* (frac 4 3) (* (var pi var-pi) (^ (var r var-r) 3))))
           :doc "Volume of a sphere." :vars ((V . "volume") (r . "radius")))
          (:name "volume-of-cylinder" :title "Volume of cylinder"
           :category "Geometry — 3D: Cylinder"
           :expr (calcFunc-eq (var V var-V)
                              (* (var pi var-pi) (* (^ (var r var-r) 2) (var h var-h))))
           :doc "Volume of a cylinder." :vars ((V . "volume") (r . "radius") (h . "height")))
          (:name "area-of-triangle" :title "Area of triangle"
           :category "Geometry — 2D"
           :expr (calcFunc-eq (var A var-A) (* (frac 1 2) (* (var b var-b) (var h var-h))))
           :doc "Area of a triangle." :vars ((A . "area") (b . "base") (h . "height")))))

  (maf-use-formulas-mode 1)
  (get-buffer-create maf-formulas--detail-buffer)

  (with-current-buffer (get-buffer-create "*maf-formulas*")
    (maf-formulas-mode)
    (maf-formulas--render)
    ;; The menu lands on a formula line, grouped by category, with the
    ;; formula shown beside the title.
    (cl-assert (get-text-property (point) 'maf-formula))
    (cl-assert (string-match-p "=" (buffer-substring (line-beginning-position)
                                                     (line-end-position))))

    ;; The detail pane (a separate buffer) follows point.
    (maf-formulas--update-detail)
    (with-current-buffer maf-formulas--detail-buffer
      (cl-assert (> (buffer-size) 0)))

    ;; Groups are separated by a blank line (the two volume formulas sit
    ;; in different categories).
    (setq maf-formulas--query "volume")
    (maf-formulas--render)
    (cl-assert (string-match-p "\n\n" (buffer-string)))

    ;; The filter narrows the list.
    (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
    (cl-assert (not (string-match-p "triangle" (buffer-string))))
    (setq maf-formulas--query "")
    (maf-formulas--render))

  ;; Every formula is registered as a calc var-eq-<name>.
  (cl-assert (boundp 'var-eq-volume-of-sphere))

  ;; RET pushes the formula's equation onto the stack.
  (calc-pop (calc-stack-size))
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (search-forward "Volume of sphere")
    (beginning-of-line)
    (cl-letf (((symbol-function 'maf-formulas-quit) (lambda (&rest _) nil)))
      (maf-formulas-insert)))
  (cl-assert (string-match-p "V = " (math-format-value (calc-top-n 1))))
  (calc-pop (calc-stack-size))

  ;; Restore the session state the fixture displaced.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 maf--formulas-stash)
          maf-formulas--loaded (nth 1 maf--formulas-stash))))
