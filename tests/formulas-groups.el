;; The formula menu's groups as places in their own right: RET on a
;; group header narrows the list to that group (and widens again when
;; pressed there a second time), n/p/j/k stop on the headers as well as
;; the rows, and land on the entry itself rather than the blank column
;; before it. The key legend stays in the header line while the list is
;; narrowed, with the narrowing shown at its head.
;;
;; Self-contained the way formulas.el is: its own fixture in
;; `maf-formulas-user' with `maf-formulas-builtin' set aside, the file
;; marked already-consulted so nothing on disk is read, and the
;; session's state put back at the end.

(maf-step
  (setq grp--stash (list maf-formulas-user maf-formulas--loaded
                         maf-formulas--recent maf-use-formulas-mode
                         maf-formulas--pane-state maf-formulas-builtin)
        maf-formulas--loaded t
        maf-formulas--recent nil
        maf-formulas--pane-state nil    ; no detail pane in the way
        maf-formulas-builtin nil        ; the fixture stands alone
        maf-formulas-user
        '((:name "vol-sphere" :title "Volume of sphere"
           :category "Geometry — 3D: Sphere"
           :expr (calcFunc-eq (var V var-V) (var r var-r))
           :doc "Volume of a sphere." :vars ((V . "volume") (r . "radius")))
          (:name "area-sphere" :title "Surface area of sphere"
           :category "Geometry — 3D: Sphere"
           :expr (calcFunc-eq (var S var-S) (var r var-r))
           :doc "Surface area of a sphere." :vars ((S . "area") (r . "radius")))
          (:name "area-triangle" :title "Area of triangle"
           :category "Geometry — 2D"
           :expr (calcFunc-eq (var A var-A) (var b var-b))
           :doc "Area of a triangle." :vars ((A . "area") (b . "base")))))
  (progn (maf-use-formulas-mode 1) nil)

  ;; The legend survives a narrowing. It used to be traded for a line
  ;; naming the filter, which took the keys away exactly when they were
  ;; in use — the narrowed list is still read with `o', marked with `a'
  ;; and pruned with `D'. Now the narrowing leads the same band, in
  ;; gold, and adds the key that lifts it.
  (with-current-buffer (get-buffer-create "*maf-formulas*")
    (maf-formulas-mode)
    (let ((plain (maf-formulas--header-line)))
      (cl-assert (string-prefix-p "maf-formulas" (substring-no-properties plain)))
      (cl-assert (not (string-match-p "c clears" (substring-no-properties plain)))))
    (setq maf-formulas--query "sphere")
    (let* ((h (maf-formulas--header-line))
           (s (substring-no-properties h)))
      (cl-assert (string-match-p "\\`filter: sphere" s))
      (cl-assert (string-match-p "c clears" s))
      (dolist (entry '("RET inserts" "/ filters" "o details" "O follows"
                       "a/i adds recent" "D deletes recent" "q quits"))
        (cl-assert (string-match-p (regexp-quote entry) s)))
      ;; The filter itself wears the gold "O follows" takes when the
      ;; pane is following: one color for "this is on", across the band.
      (cl-assert (eq (get-text-property (string-match "sphere" s) 'face h)
                     'warning)))
    ;; A group narrowing shows the same way, and the two sit together —
    ;; as they do when a filter is typed inside a narrowed group.
    (setq maf-formulas--group "Geometry — 2D")
    (let ((s (substring-no-properties (maf-formulas--header-line))))
      (cl-assert (string-match-p "\\`group: Geometry — 2D  filter: sphere" s))
      (cl-assert (string-match-p "q quits" s)))
    (setq maf-formulas--query "" maf-formulas--group nil))

  ;; n/p/j/k walk the rows and the headers alike, and stop on the first
  ;; character of what they reach: the rows are indented, and a cursor
  ;; in that blank column reads as being beside the entry, not on it.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (dolist (k '("n" "j"))
        (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd k))
                       'maf-formulas-next-item)))
      (dolist (k '("p" "k"))
        (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd k))
                       'maf-formulas-prev-item)))
      (goto-char (point-min))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 2D"))
      (execute-kbd-macro (kbd "n"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                        "Area of triangle"))
      (cl-assert (= (current-column) 2))
      (cl-assert (eq (char-after) ?A))
      ;; The next stop is the header below, not the row past it.
      (execute-kbd-macro (kbd "j"))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (= (current-column) 0))
      (execute-kbd-macro (kbd "n"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                        "Volume of sphere"))
      (cl-assert (= (current-column) 2))
      ;; And back the same way.
      (execute-kbd-macro (kbd "k"))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      (execute-kbd-macro (kbd "p"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                        "Area of triangle"))
      (cl-assert (= (current-column) 2))
      (maf-formulas-quit)))

  ;; RET on a group header narrows to that group; RET on the header
  ;; again — still there, at the top — widens back. Point stays on the
  ;; header across both, so the key can be pressed twice for a look and
  ;; a return.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd "RET"))
                     'maf-formulas-select))
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal maf-formulas--group "Geometry — 3D: Sphere"))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (= (point) (point-min)))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Area of triangle" (buffer-string))))
      ;; Nothing was pushed: RET on a header is not an insert.
      (cl-assert (get-buffer-window "*maf-formulas*"))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null maf-formulas--group))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))

      ;; From a filtered list the group still comes up whole: the header
      ;; names a group, and reaching for it asks for the group, not for
      ;; the part of it the filter had left standing. "area" leaves one
      ;; formula in each group — and hides "Volume of sphere", which the
      ;; sphere group brings back.
      (maf-formulas-filter "area")
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal maf-formulas--group "Geometry — 3D: Sphere"))
      (cl-assert (equal maf-formulas--query ""))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (string-match-p "Surface area of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Area of triangle" (buffer-string))))
      ;; The filter was set aside, not lost: widening puts back the list
      ;; the header was pressed from.
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null maf-formulas--group))
      (cl-assert (equal maf-formulas--query "area"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))

      ;; A filter typed while the group is up narrows within it, and
      ;; being the newer word on what to show it stands after widening
      ;; rather than the one that was set aside.
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (maf-formulas-filter "volume")
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Surface area of sphere" (buffer-string))))
      (goto-char (point-min))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null maf-formulas--group))
      (cl-assert (equal maf-formulas--query "volume"))

      ;; And `c' drops the lot, rather than leaving the other narrowing
      ;; to be found and undone.
      (maf-formulas-filter "area")
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (execute-kbd-macro (kbd "c"))
      (cl-assert (null maf-formulas--group))
      (cl-assert (equal maf-formulas--query ""))
      (cl-assert (null maf-formulas--group-query))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))

      ;; On a formula row there is no group to narrow to, and the
      ;; command called directly says so.
      (goto-char (point-min))
      (maf-formulas-next-item)
      (cl-assert (equal (condition-case err
                            (progn (maf-formulas-filter-group) nil)
                          (user-error (cadr err)))
                        "Not on a group header"))
      (maf-formulas-quit)))

  ;; "Recent" narrows like any other group — and it is the one group a
  ;; filter string cannot reach, being a shortcut rather than a
  ;; category, so its header is the only way in.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (search-forward "Volume of sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "a"))
      (goto-char (point-min))
      (cl-assert (equal (maf-formulas--group-at-point) "Recent"))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal maf-formulas--group "Recent"))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Geometry" (buffer-string))))
      ;; The formula is listed once now, its category's copy narrowed
      ;; away with the rest.
      (cl-assert (= 1 (let ((n 0) (i 0) (s (buffer-string)))
                        (while (setq i (string-search "Volume of sphere" s i))
                          (setq n (1+ n) i (1+ i)))
                        n)))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null maf-formulas--group))
      (cl-assert (string-match-p "Geometry" (buffer-string)))

      ;; Forgetting the last entry while narrowed to the group takes the
      ;; narrowing with it: the group is gone, and a narrowing to a
      ;; group that is not there is an empty buffer with the legend for
      ;; its only way out.
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal maf-formulas--group "Recent"))
      (maf-formulas-next-item)
      (execute-kbd-macro (kbd "D"))
      (cl-assert (null maf-formulas--recent))
      (cl-assert (null maf-formulas--group))
      (cl-assert (string-match-p "Geometry" (buffer-string)))
      (maf-formulas-quit)))

  ;; Put the session's formulas state back, as formulas.el does.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 grp--stash)
          maf-formulas--loaded (nth 1 grp--stash)
          maf-formulas--recent (nth 2 grp--stash)
          maf-formulas--pane-state (nth 4 grp--stash)
          maf-formulas-builtin (nth 5 grp--stash))
    (when (nth 3 grp--stash)
      (maf-use-formulas-mode 1))
    :restored))
