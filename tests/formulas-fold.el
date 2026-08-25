;; Folding the formula menu's groups: TAB folds every group away to its
;; header and unfolds them all again, S-TAB folds or unfolds the one
;; group at point, and a folded header wears the count of what it
;; holds. The point is navigation — a list of a hundred-odd formulas
;; read as its group names, the wanted one unfolded.
;;
;; TAB is not contextual. It means the whole list from any line in it,
;; which is what makes it the key for a view rather than an edit to
;; one corner; picking a single group out is S-TAB's job.
;;
;; The fold is not a narrowing. The folded formulas are still in the
;; list and still counted; `c' does not lift a fold. What does lift one
;; is a search: every group unfolds, because a folded search is a
;; search whose results cannot be seen. It stays unfolded afterwards —
;; a list that re-folded itself as the filter lifted would take the
;; results back from a user still reading them.
;;
;; Self-contained the way formulas-groups.el is: its own fixture in
;; `maf-formulas-user' with `maf-formulas-builtin' set aside, the file
;; marked already-consulted so nothing on disk is read, and the
;; session's state put back at the end.

(maf-step
  (setq fold--stash (list maf-formulas-user maf-formulas--loaded
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

  ;; A counting helper, so each step can say what is on show rather
  ;; than matching the whole buffer.
  (progn
    (defun fold--rows ()
      "Titles of the formula rows the current render put on screen."
      (let (titles)
        (save-excursion
          (goto-char (point-min))
          (while (not (eobp))
            (when-let ((f (get-text-property (line-beginning-position) 'maf-formula)))
              (push (maf-formulas--title f) titles))
            (forward-line 1)))
        (nreverse titles)))
    (defun fold--headers ()
      "Category names of the header lines on screen, in order."
      (let (names)
        (save-excursion
          (goto-char (point-min))
          (while (not (eobp))
            (when-let ((g (maf-formulas--group-at-point))) (push g names))
            (forward-line 1)))
        (nreverse names)))
    :helpers)

  ;; TAB is the fold, not a third key for the item motion — n/p/j/k
  ;; already cover that twice over.
  (progn
    (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd "TAB"))
                   'maf-formulas-toggle-all-groups))
    (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd "<backtab>"))
                   'maf-formulas-toggle-group))
    (cl-assert (eq (lookup-key maf-formulas-mode-map (kbd "n"))
                   'maf-formulas-next-item))
    :bound)

  ;; S-TAB on a header folds that group away: its rows leave the buffer,
  ;; the header stays and takes the count of what went with it. The
  ;; other group is untouched — a fold is one group's, not a mode the
  ;; buffer is in.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (cl-assert (equal (fold--headers) '("Geometry — 2D" "Geometry — 3D: Sphere")))
      (cl-assert (equal (fold--rows)
                        '("Area of triangle" "Volume of sphere"
                          "Surface area of sphere")))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 2D"))
      (execute-kbd-macro (kbd "<backtab>"))
      (cl-assert (equal maf-formulas--collapsed '("Geometry — 2D")))
      ;; The row is gone; the sphere group's two are not.
      (cl-assert (equal (fold--rows)
                        '("Volume of sphere" "Surface area of sphere")))
      ;; Both headers are still there, and the folded one says how many.
      (cl-assert (equal (fold--headers) '("Geometry — 2D" "Geometry — 3D: Sphere")))
      (cl-assert (equal (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))
                        "Geometry — 2D (1)"))
      ;; The count is on the line but is no part of the group's name:
      ;; the header carries that in a text property, so RET and the
      ;; motions still have the string the groups are keyed by.
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 2D"))
      ;; S-TAB on the header again unfolds it, point staying put.
      (execute-kbd-macro (kbd "<backtab>"))
      (cl-assert (null maf-formulas--collapsed))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 2D"))
      (cl-assert (= (length (fold--rows)) 3))
      (maf-formulas-quit)))

  ;; S-TAB pressed on a formula row folds the group that row is in, and
  ;; point comes to rest on its header — the row it was on having gone.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (search-forward "Volume of sphere")
      (beginning-of-line)
      (cl-assert (get-text-property (point) 'maf-formula))
      (execute-kbd-macro (kbd "<backtab>"))
      (cl-assert (equal maf-formulas--collapsed '("Geometry — 3D: Sphere")))
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (equal (fold--rows) '("Area of triangle")))
      (maf-formulas-quit)))

  ;; The motions walk what is on screen: a folded group is one stop,
  ;; its rows being no longer in the buffer to stop on.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (execute-kbd-macro (kbd "<backtab>"))    ; fold Geometry — 2D
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 2D"))
      (execute-kbd-macro (kbd "n"))
      ;; Straight to the next header, not into the folded group.
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      (execute-kbd-macro (kbd "n"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                        "Volume of sphere"))
      (maf-formulas-quit)))

  ;; TAB folds every group at once — the fold view the whole feature
  ;; is for: nothing but group names, one line each, no blank lines
  ;; between them to read past. The same key from any line in the list.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (execute-kbd-macro (kbd "TAB"))
      (cl-assert (= (length maf-formulas--collapsed) 2))
      (cl-assert (null (fold--rows)))
      (cl-assert (equal (fold--headers) '("Geometry — 2D" "Geometry — 3D: Sphere")))
      (cl-assert (= (count-lines (point-min) (point-max)) 2))
      ;; With something folded, TAB unfolds the lot rather than
      ;; folding what is already folded.
      (execute-kbd-macro (kbd "TAB"))
      (cl-assert (null maf-formulas--collapsed))
      (cl-assert (= (length (fold--rows)) 3))
      (maf-formulas-quit)))

  ;; And it is not contextual: pressed on a formula row, deep in a
  ;; group, TAB still folds the whole list rather than the group that
  ;; row is in. The key means one thing wherever it is pressed, which
  ;; is what makes it the key for a view of the list.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (search-forward "Surface area of sphere")
      (beginning-of-line)
      (cl-assert (get-text-property (point) 'maf-formula))
      (execute-kbd-macro (kbd "TAB"))
      (cl-assert (= (length maf-formulas--collapsed) 2))
      (cl-assert (null (fold--rows)))
      ;; Point keeps its group, landing on that header — the row it was
      ;; on having gone with the rest.
      (cl-assert (equal (maf-formulas--group-at-point) "Geometry — 3D: Sphere"))
      ;; S-TAB from the same place is the contextual one: it unfolds
      ;; that group alone, the other staying folded.
      (execute-kbd-macro (kbd "<backtab>"))
      (cl-assert (equal maf-formulas--collapsed '("Geometry — 2D")))
      (cl-assert (equal (fold--rows)
                        '("Volume of sphere" "Surface area of sphere")))
      (maf-formulas-quit)))

  ;; A search unfolds everything, so that what it turns up can be seen:
  ;; results hidden behind a fold made earlier would be a search that
  ;; answered nothing. Driven through `/' and real keystrokes, the way
  ;; it is met — the live narrowing runs off the minibuffer's own hook,
  ;; which a programmatic call would step around.
  (save-window-excursion
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (execute-kbd-macro (kbd "TAB"))
      (cl-assert (= (length maf-formulas--collapsed) 2))
      (cl-assert (null (fold--rows)))
      ;; RET rides in the same macro: the filter's read blocks until it.
      (execute-kbd-macro (kbd "/ s p h e r e RET"))
      (cl-assert (equal maf-formulas--query "sphere"))
      (cl-assert (null maf-formulas--collapsed))
      ;; The matches are on screen, folded a moment ago or not.
      (cl-assert (equal (fold--rows)
                        '("Volume of sphere" "Surface area of sphere")))
      ;; And they stay on screen: lifting the filter leaves the list
      ;; unfolded rather than folding the results away again.
      (maf-formulas-clear-filter)
      (cl-assert (null maf-formulas--collapsed))
      (cl-assert (= (length (fold--rows)) 3))
      (maf-formulas-quit)))

  ;; RET on a folded header unfolds it on the way in: asking for a
  ;; group is asking to see it, not to narrow to a header with nothing
  ;; under it.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "<backtab>"))
      (cl-assert (maf-formulas--collapsed-p "Geometry — 3D: Sphere"))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal maf-formulas--group "Geometry — 3D: Sphere"))
      (cl-assert (not (maf-formulas--collapsed-p "Geometry — 3D: Sphere")))
      (cl-assert (equal (fold--rows)
                        '("Volume of sphere" "Surface area of sphere")))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null maf-formulas--group))
      (maf-formulas-quit)))

  ;; The legend names the key, beside the filter it sits next to.
  (with-current-buffer (get-buffer-create "*maf-formulas*")
    (maf-formulas-mode)
    (let ((s (substring-no-properties (maf-formulas--header-line))))
      (cl-assert (string-match-p "TAB folds" s))
      (cl-assert (string-match-p "/ filters" s)))
    :legend)

  ;; Put the session's formulas state back, as formulas-groups.el does.
  (progn
    (maf-use-formulas-mode -1)
    (fmakunbound 'fold--rows)
    (fmakunbound 'fold--headers)
    (when-let ((buf (get-buffer "*maf-formulas*")))
      (with-current-buffer buf
        (setq maf-formulas--collapsed nil)))
    (setq maf-formulas-user (nth 0 fold--stash)
          maf-formulas--loaded (nth 1 fold--stash)
          maf-formulas--recent (nth 2 fold--stash)
          maf-formulas--pane-state (nth 4 fold--stash)
          maf-formulas-builtin (nth 5 fold--stash))
    (when (nth 3 fold--stash)
      (maf-use-formulas-mode 1))
    :restored))
