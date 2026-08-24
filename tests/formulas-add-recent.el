;; maf-formulas-add-recent (a, and i beside it): mark the formula at
;; point as reached-for without inserting it and without leaving the
;; menu, so a handful can be gathered in one visit. The group was
;; otherwise written only by an insert, which quits the buffer.
;;
;; Self-contained the way formulas.el is: its own fixture in
;; `maf-formulas-user', the file marked already-consulted so nothing on
;; disk is read, and the session's state put back at the end.

(maf-step
  (setq addrec--stash (list maf-formulas-user maf-formulas--loaded
                            maf-formulas--recent maf-use-formulas-mode
                            maf-formulas--pane-state)
        maf-formulas--loaded t
        maf-formulas--recent nil
        maf-formulas--pane-state nil    ; no detail pane in the way
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

  ;; The keys are both there, on the one command.
  (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd "a"))
                 'maf-formulas-add-recent))
  (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd "i"))
                 'maf-formulas-add-recent))
  ;; And the legend says so, where the legend is shown.
  (cl-assert (string-match-p
              "a/i adds recent"
              (with-current-buffer (get-buffer-create "*maf-formulas*")
                (let ((maf-formulas--query ""))
                  (substring-no-properties (maf-formulas--header-line))))))

  ;; Marking a formula records it and puts a Recent group up, without
  ;; touching the stack and without closing the menu. Point keeps its
  ;; place — on the category's copy, where the mark was made — rather
  ;; than following the render to the top of the new group.
  ;;
  ;; The window is selected throughout: point moves and key sequences
  ;; run in the buffer's window, and redisplay would undo a `goto-char'
  ;; made outside it.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      ;; The depth is read in the calc buffer: `calc-stack-top' is
      ;; buffer-local to it, and nil out here.
      (let ((depth (maf--with-calc-buffer (calc-stack-size))))
        (goto-char (point-min))
        (search-forward "Volume of sphere")
        (beginning-of-line)
        (execute-kbd-macro (kbd "a"))
        (cl-assert (equal (mapcar #'maf-formulas--title maf-formulas--recent)
                          '("Volume of sphere")))
        (cl-assert (get-buffer-window "*maf-formulas*"))   ; still open
        (cl-assert (= (maf--with-calc-buffer (calc-stack-size)) depth))
        (cl-assert (string-match-p
                    "Volume of sphere"
                    (buffer-substring-no-properties (line-beginning-position)
                                                    (line-end-position))))
        (cl-assert (not (maf-formulas--recent-line-p)))

        ;; i marks the same way, and a second formula joins the first,
        ;; newest at the head.
        (goto-char (point-min))
        (search-forward "Area of triangle")
        (beginning-of-line)
        (execute-kbd-macro (kbd "i"))
        (cl-assert (equal (mapcar #'maf-formulas--title maf-formulas--recent)
                          '("Area of triangle" "Volume of sphere")))

        ;; Marking from the group's own copy stays on that copy.
        (goto-char (point-min))
        (forward-line 1)
        (cl-assert (maf-formulas--recent-line-p))
        (execute-kbd-macro (kbd "a"))
        (cl-assert (maf-formulas--recent-line-p))

        ;; A header line, or any line with no formula on it, refuses.
        (goto-char (point-min))
        (cl-assert (null (get-text-property (point) 'maf-formula)))
        (cl-assert (equal (condition-case err (progn (maf-formulas-add-recent) nil)
                            (user-error (cadr err)))
                          "No formula on this line")))
      (maf-formulas-quit)))

  ;; The narrowed list marks the same way: the row under point is what
  ;; counts, so a filter is no obstacle, and it survives the re-render.
  (progn (setq maf-formulas--recent nil) nil)
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (maf-formulas-filter "triangle")
      (cl-assert (equal maf-formulas--query "triangle"))
      (goto-char (point-min))
      (search-forward "Area of triangle")
      (beginning-of-line)
      (execute-kbd-macro (kbd "a"))
      (cl-assert (equal (mapcar #'maf-formulas--title maf-formulas--recent)
                        '("Area of triangle")))
      ;; The narrowing is still in force, the group is up inside it,
      ;; and point is still on the row it was marked from.
      (cl-assert (equal maf-formulas--query "triangle"))
      (cl-assert (string-match-p "^Recent$"
                                 (buffer-substring-no-properties
                                  (point-min) (line-end-position 1))))
      (cl-assert (string-match-p
                  "Area of triangle"
                  (buffer-substring-no-properties (line-beginning-position)
                                                  (line-end-position))))
      (maf-formulas-quit)))

  ;; With the group turned off there is nowhere to add, and the command
  ;; says so rather than doing nothing.
  (progn (setq maf-formulas--recent nil) nil)
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (search-forward "Volume of sphere")
      (beginning-of-line)
      (cl-assert (equal (let ((maf-formulas-recent-max 0))
                          (condition-case err
                              (progn (maf-formulas-add-recent) nil)
                            (user-error (cadr err))))
                        "The Recent group is turned off (maf-formulas-recent-max)"))
      (cl-assert (null maf-formulas--recent))
      (maf-formulas-quit)))

  ;; Put the session's formulas state back, as formulas.el does.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 addrec--stash)
          maf-formulas--loaded (nth 1 addrec--stash)
          maf-formulas--recent (nth 2 addrec--stash)
          maf-formulas--pane-state (nth 4 addrec--stash))
    (when (nth 3 addrec--stash)
      (maf-use-formulas-mode 1))
    :restored))
