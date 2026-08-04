;; Self-contained: the real formulas now live in `maf-formulas-file'
;; (the user's Emacs config), so this test supplies its own fixture in
;; `maf-formulas-user' and marks the file already-consulted so nothing
;; on disk is read. The last form restores the session state.

(maf-step
  (setq maf--formulas-stash (list maf-formulas-user maf-formulas--loaded
                                  maf-formulas--recent maf-use-formulas-mode)
        maf-formulas--loaded t          ; skip loading maf-formulas-file
        maf-formulas--recent nil        ; a clean session's recents
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

    ;; The detail renderer (behind `o' / `d' / `?', i.e.
    ;; `maf-formulas-show-detail') fills the detail buffer for the
    ;; formula at point.
    (cl-assert (eq (key-binding (kbd "o")) #'maf-formulas-show-detail))
    (cl-assert (eq (key-binding (kbd "d")) #'maf-formulas-show-detail))
    (cl-assert (eq (key-binding (kbd "?")) #'maf-formulas-show-detail))
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
    (maf-formulas--render)

    ;; TAB steps formula to formula, like n; M-n walks the groups and
    ;; stops dead at the last one rather than cycling.
    (cl-assert (eq (key-binding (kbd "TAB")) #'maf-formulas-next-item))
    (cl-assert (eq (key-binding (kbd "M-n")) #'maf-formulas-next-group))
    (goto-char (point-min))
    (maf-formulas-next-item)
    (maf-formulas-next-group)
    (cl-assert (not (get-text-property (point) 'maf-formula)))   ; a header
    (cl-assert (equal (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))
                      "Geometry — 3D: Cylinder"))
    (maf-formulas-next-group)
    (cl-assert (equal (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))
                      "Geometry — 3D: Sphere"))
    (let ((p (point)))                  ; the last header: M-n stops here
      (cl-assert (condition-case nil (progn (maf-formulas-next-group) nil)
                   (user-error t)))
      (cl-assert (= (point) p)))
    (goto-char (point-min))             ; the first header: M-p stops here
    (cl-assert (condition-case nil (progn (maf-formulas-prev-group) nil)
                 (user-error t)))
    (cl-assert (= (point) (point-min)))

    ;; Typing into the filter narrows live: the hook the reader installs
    ;; on the minibuffer pushes whatever has been typed so far.
    (let ((maf-formulas--filter-buffer (current-buffer)))
      (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                 (lambda () "triangle")))
        (maf-formulas--filter-update))
      (cl-assert (equal maf-formulas--query "triangle"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (not (string-match-p "sphere" (buffer-string))))
      (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                 (lambda () "")))
        (maf-formulas--filter-update))
      (cl-assert (string-match-p "sphere" (buffer-string)))))

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

  ;; That insert seeded the Recent group: it heads the list, point lands
  ;; on it, and the formula still appears under its own category too.
  (with-current-buffer "*maf-formulas*"
    (maf-formulas--render)
    (cl-assert (equal (buffer-substring-no-properties (point-min)
                                                      (save-excursion
                                                        (goto-char (point-min))
                                                        (line-end-position)))
                      "Recent"))
    ;; It is set apart in its own face — the group is not a category, so
    ;; it does not take the category color the headers below it keep.
    (cl-assert (eq (get-text-property (point-min) 'face) 'maf-formulas-recent))
    (cl-assert (eq (save-excursion
                     (goto-char (point-min))
                     (search-forward "Geometry — 3D: Sphere")
                     (get-text-property (line-beginning-position) 'face))
                   'maf-formulas-category))
    (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                      "Volume of sphere"))
    (cl-assert (= 2 (let ((n 0) (i 0) (s (buffer-string)))
                      (while (setq i (string-search "Volume of sphere" s i))
                        (setq n (1+ n) i (1+ i)))
                      n))))

  ;; A second insert takes the head of the group, most recent first.
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (search-forward "Area of triangle")
    (beginning-of-line)
    (cl-letf (((symbol-function 'maf-formulas-quit) (lambda (&rest _) nil)))
      (maf-formulas-insert))
    (maf-formulas--render)
    (cl-assert (equal (mapcar #'maf-formulas--title maf-formulas--recent)
                      '("Area of triangle" "Volume of sphere")))
    (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                      "Area of triangle")))
  (calc-pop (calc-stack-size))

  ;; Restore the session state the fixture displaced. Turning the mode
  ;; off first unregisters the fixture's var-eq-* variables; the real
  ;; formulas are then back in place, so re-enabling (when the session
  ;; had it on) registers those and hands `s o' back — a test run must
  ;; not leave the live instance without the module it borrowed.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 maf--formulas-stash)
          maf-formulas--loaded (nth 1 maf--formulas-stash)
          maf-formulas--recent (nth 2 maf--formulas-stash))
    (when (nth 3 maf--formulas-stash)
      (maf-use-formulas-mode 1))))
