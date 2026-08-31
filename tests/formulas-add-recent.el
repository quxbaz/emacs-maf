;; filter-view-add-recent (a, and i beside it): mark the formula at
;; point as reached-for without inserting it and without leaving the
;; menu, so a handful can be gathered in one visit. The group was
;; otherwise written only by a select, which quits the buffer.
;;
;; Self-contained the way formulas.el is: its own fixture in
;; `maf-formulas-user' with `maf-formulas-builtin' set aside, the file
;; marked already-consulted so nothing on disk is read, and the
;; session's state put back at the end.

(maf-step
  (setq addrec--stash (list maf-formulas-user maf-formulas--loaded
                            maf-use-formulas-mode maf-formulas-builtin
                            (gethash "*maf-formulas*" filter-view--sessions))
        maf-formulas--loaded t
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
  (progn
    (remhash "*maf-formulas*" filter-view--sessions)
    ;; No detail pane in the way of the window assertions.
    (filter-view--session-put "*maf-formulas*" :pane-state nil)
    (maf-use-formulas-mode 1)
    nil)

  ;; The keys are both there, on the one command.
  (cl-assert (eq (lookup-key filter-view-mode-map (kbd "a"))
                 'filter-view-add-recent))
  (cl-assert (eq (lookup-key filter-view-mode-map (kbd "i"))
                 'filter-view-add-recent))
  ;; And the legend says so, where the legend is shown.
  (cl-assert (string-match-p
              "a/i adds recent"
              (with-current-buffer (apply #'filter-view-setup "*maf-formulas*"
                                          (maf-formulas--config))
                (substring-no-properties (filter-view--header-line)))))

  ;; Marking a formula records it and puts a Recent group up, without
  ;; touching the stack and without closing the menu. Point keeps its
  ;; place — on the category's copy, where the mark was made — rather
  ;; than following the render to the top of the new group. The group
  ;; holds the formulas by :name, their filter-view key.
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
        (cl-assert (equal (filter-view--state :recents) '("vol-sphere")))
        (cl-assert (get-buffer-window "*maf-formulas*"))   ; still open
        (cl-assert (= (maf--with-calc-buffer (calc-stack-size)) depth))
        (cl-assert (string-match-p
                    "Volume of sphere"
                    (buffer-substring-no-properties (line-beginning-position)
                                                    (line-end-position))))
        (cl-assert (not (filter-view--recent-line-p)))

        ;; i marks the same way, and a second formula joins the first,
        ;; newest at the head.
        (goto-char (point-min))
        (search-forward "Area of triangle")
        (beginning-of-line)
        (execute-kbd-macro (kbd "i"))
        (cl-assert (equal (filter-view--state :recents)
                          '("area-triangle" "vol-sphere")))

        ;; Marking from the group's own copy stays on that copy.
        (goto-char (point-min))
        (forward-line 1)
        (cl-assert (filter-view--recent-line-p))
        (execute-kbd-macro (kbd "a"))
        (cl-assert (filter-view--recent-line-p))

        ;; A header line, or any line with no formula on it, refuses.
        (goto-char (point-min))
        (cl-assert (null (get-text-property (point) 'filter-view-item)))
        (cl-assert (equal (condition-case err (progn (filter-view-add-recent) nil)
                            (user-error (cadr err)))
                          "Nothing on this line")))
      (filter-view-quit)))

  ;; The narrowed list marks the same way: the row under point is what
  ;; counts, so a filter is no obstacle, and it survives the re-render.
  ;; Recents remain out of filtered results until the filter is cleared.
  (progn (filter-view--session-put "*maf-formulas*" :recents nil) nil)
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (filter-view-filter "triangle")
      (cl-assert (equal filter-view--query "triangle"))
      (goto-char (point-min))
      (search-forward "Area of triangle")
      (beginning-of-line)
      (execute-kbd-macro (kbd "a"))
      (cl-assert (equal (filter-view--state :recents) '("area-triangle")))
      ;; The narrowing is still in force, no Recent group is mixed into
      ;; its results, and point is still on the row it was marked from.
      (cl-assert (equal filter-view--query "triangle"))
      (cl-assert (not (string-match-p "^Recent$" (buffer-string))))
      (cl-assert (string-match-p
                  "Area of triangle"
                  (buffer-substring-no-properties (line-beginning-position)
                                                  (line-end-position))))
      ;; Clearing the filter reveals the recorded formula in Recent.
      (filter-view-clear-filter)
      (cl-assert (string-match-p "^Recent$" (buffer-string)))
      (filter-view-quit)))

  ;; With the group turned off there is nowhere to add, and the command
  ;; says so rather than doing nothing.
  (progn (filter-view--session-put "*maf-formulas*" :recents nil) nil)
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (search-forward "Volume of sphere")
      (beginning-of-line)
      (cl-assert (equal (let ((maf-formulas-recent-max 0))
                          (condition-case err
                              (progn (filter-view-add-recent) nil)
                            (user-error (cadr err))))
                        "The Recent group is turned off"))
      (cl-assert (null (filter-view--state :recents)))
      (filter-view-quit)))

  ;; Put the session's formulas state back, as formulas.el does.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 addrec--stash)
          maf-formulas--loaded (nth 1 addrec--stash)
          maf-formulas-builtin (nth 3 addrec--stash))
    (if (nth 4 addrec--stash)
        (puthash "*maf-formulas*" (nth 4 addrec--stash) filter-view--sessions)
      (remhash "*maf-formulas*" filter-view--sessions))
    (when (get-buffer "*maf-formulas*") (kill-buffer "*maf-formulas*"))
    (when (nth 2 addrec--stash)
      (maf-use-formulas-mode 1))
    :restored))
