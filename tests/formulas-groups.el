;; The formula menu's groups as places in their own right: RET on a
;; group header narrows the list to that group (and widens again when
;; pressed there a second time), n/p/j/k stop on the headers as well as
;; the rows, and land on the entry itself rather than the blank column
;; before it. The key legend stays in the header line while the list is
;; narrowed, with the narrowing shown at its head. The menu is a
;; filter-view; the narrowing state is its buffer-locals, the session
;; state its `filter-view--sessions' entry.
;;
;; Self-contained the way formulas.el is: its own fixture in
;; `maf-formulas-user' with `maf-formulas-builtin' set aside, the file
;; marked already-consulted so nothing on disk is read, and the
;; session's state put back at the end.

(maf-step
  (setq grp--stash (list maf-formulas-user maf-formulas--loaded
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

  ;; The legend survives a narrowing. It used to be traded for a line
  ;; naming the filter, which took the keys away exactly when they were
  ;; in use — the narrowed list is still read with `?', marked with `a'
  ;; and pruned with `D'. Now the narrowing leads the same band, in
  ;; gold, and adds the key that lifts it.
  (with-current-buffer (apply #'filter-view-setup "*maf-formulas*"
                              (maf-formulas--config))
    (let ((plain (filter-view--header-line)))
      (cl-assert (string-prefix-p "maf-formulas" (substring-no-properties plain)))
      (cl-assert (not (string-match-p "c clears" (substring-no-properties plain)))))
    (setq filter-view--query "sphere")
    (let* ((h (filter-view--header-line))
           (s (substring-no-properties h)))
      (cl-assert (string-match-p "\\`filter: sphere" s))
      (cl-assert (string-match-p "c clears" s))
      (dolist (entry '("RET inserts" "/ filters" "w/? details" "O follows"
                       "a/i adds recent" "D deletes recent" "q quits"))
        (cl-assert (string-match-p (regexp-quote entry) s)))
      ;; The filter itself wears the gold "O follows" takes when the
      ;; pane is following: one color for "this is on", across the band.
      (cl-assert (eq (get-text-property (string-match "sphere" s) 'face h)
                     'warning)))
    ;; A group narrowing shows the same way, and the two sit together —
    ;; as they do when a filter is typed inside a narrowed group.
    (setq filter-view--group "Geometry — 2D")
    (let ((s (substring-no-properties (filter-view--header-line))))
      (cl-assert (string-match-p "\\`group: Geometry — 2D  filter: sphere" s))
      (cl-assert (string-match-p "q quits" s)))
    (setq filter-view--query "" filter-view--group nil))

  ;; n/p/j/k walk the rows and the headers alike, and stop on the first
  ;; character of what they reach: the rows are indented, and a cursor
  ;; in that blank column reads as being beside the entry, not on it.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (dolist (k '("n" "j"))
        (cl-assert (eq (lookup-key filter-view-mode-map (kbd k))
                       'filter-view-next-item)))
      (dolist (k '("p" "k"))
        (cl-assert (eq (lookup-key filter-view-mode-map (kbd k))
                       'filter-view-prev-item)))
      (goto-char (point-min))
      (cl-assert (equal (filter-view--group-at-point) "Geometry — 2D"))
      (execute-kbd-macro (kbd "n"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'filter-view-item))
                        "Area of triangle"))
      (cl-assert (= (current-column) 2))
      (cl-assert (eq (char-after) ?A))
      ;; The next stop is the header below, not the row past it.
      (execute-kbd-macro (kbd "j"))
      (cl-assert (equal (filter-view--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (= (current-column) 0))
      (execute-kbd-macro (kbd "n"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'filter-view-item))
                        "Volume of sphere"))
      (cl-assert (= (current-column) 2))
      ;; And back the same way.
      (execute-kbd-macro (kbd "k"))
      (cl-assert (equal (filter-view--group-at-point) "Geometry — 3D: Sphere"))
      (execute-kbd-macro (kbd "p"))
      (cl-assert (equal (maf-formulas--title (get-text-property (point) 'filter-view-item))
                        "Area of triangle"))
      (cl-assert (= (current-column) 2))
      (filter-view-quit)))

  ;; RET on a group header narrows to that group; RET on the header
  ;; again — still there, at the top — widens back. Point stays on the
  ;; header across both, so the key can be pressed twice for a look and
  ;; a return.
  (save-window-excursion
    (delete-other-windows)
    (maf-formulas)
    (with-selected-window (get-buffer-window "*maf-formulas*")
      (cl-assert (eq (lookup-key filter-view-mode-map (kbd "RET"))
                     'filter-view-select))
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal filter-view--group "Geometry — 3D: Sphere"))
      (cl-assert (equal (filter-view--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (= (point) (point-min)))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Area of triangle" (buffer-string))))
      ;; Nothing was pushed: RET on a header is not an insert.
      (cl-assert (get-buffer-window "*maf-formulas*"))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null filter-view--group))
      (cl-assert (equal (filter-view--group-at-point) "Geometry — 3D: Sphere"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))

      ;; From a filtered list the group still comes up whole: the header
      ;; names a group, and reaching for it asks for the group, not for
      ;; the part of it the filter had left standing. "area" leaves one
      ;; formula in each group — and hides "Volume of sphere", which the
      ;; sphere group brings back.
      (filter-view-filter "area")
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal filter-view--group "Geometry — 3D: Sphere"))
      (cl-assert (equal filter-view--query ""))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (string-match-p "Surface area of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Area of triangle" (buffer-string))))
      ;; The filter was set aside, not lost: widening puts back the list
      ;; the header was pressed from.
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null filter-view--group))
      (cl-assert (equal filter-view--query "area"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))

      ;; Filtering is the other way out of a group: a filter searches
      ;; the whole list, so the group is lifted rather than searched
      ;; inside — and the filter it had set aside goes with it, there
      ;; being nothing left to come back to. "area" reaches the
      ;; triangle, in a group the narrowing had put out of sight.
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal filter-view--group "Geometry — 3D: Sphere"))
      (filter-view-filter "area")
      (cl-assert (null filter-view--group))
      (cl-assert (null filter-view--group-query))
      (cl-assert (equal filter-view--query "area"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (string-match-p "Surface area of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))

      ;; Even a filter that asks for what is already in force lifts the
      ;; group: inside one the filter string is empty, and filtering
      ;; for nothing is still a search over everything.
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal filter-view--query ""))
      (filter-view-filter "")
      (cl-assert (null filter-view--group))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))

      ;; `/' on its own widens nothing: the prompt opens on the group,
      ;; and it is the first character typed — the search actually
      ;; beginning — that lifts it.
      (filter-view-filter "area")
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (let (seen)
        (cl-letf (((symbol-function 'read-string)
                   (lambda (&rest _)
                     (setq seen (list filter-view--group (buffer-string)))
                     ;; A character typed: the hook the reader installs
                     ;; pushes what stands so far, and the group goes.
                     (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                                (lambda () "triangle")))
                       (filter-view--filter-update))
                     "triangle")))
          (filter-view-filter))
        ;; The list the prompt opened on was still the group's.
        (cl-assert (equal (car seen) "Geometry — 3D: Sphere"))
        (cl-assert (not (string-match-p "Area of triangle" (cadr seen)))))
      (cl-assert (null filter-view--group))
      (cl-assert (null filter-view--group-query))
      (cl-assert (equal filter-view--query "triangle"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))

      ;; RET on an untouched prompt leaves the group standing: a search
      ;; never made takes nothing away.
      (filter-view-filter "area")
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "")))
        (filter-view-filter))
      (cl-assert (equal filter-view--group "Geometry — 3D: Sphere"))
      (cl-assert (equal filter-view--group-query "area"))
      (cl-assert (equal filter-view--query ""))
      (cl-assert (not (string-match-p "Area of triangle" (buffer-string))))

      ;; And quitting after typing puts the group back, the filter it
      ;; had set aside with it: nothing was asked for after all.
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _)
                   (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                              (lambda () "triangle")))
                     (filter-view--filter-update))
                   (cl-assert (null filter-view--group)) ; widened as it was typed
                   (signal 'quit nil))))
        (cl-assert (condition-case nil (progn (filter-view-filter) nil)
                     (quit t))))
      (cl-assert (equal filter-view--group "Geometry — 3D: Sphere"))
      (cl-assert (equal filter-view--group-query "area"))
      (cl-assert (equal filter-view--query ""))
      (cl-assert (not (string-match-p "Area of triangle" (buffer-string))))

      ;; And `c' drops the lot, rather than leaving the other narrowing
      ;; to be found and undone.
      (filter-view-filter "area")
      (goto-char (point-min))
      (search-forward "Geometry — 3D: Sphere")
      (beginning-of-line)
      (execute-kbd-macro (kbd "RET"))
      (execute-kbd-macro (kbd "c"))
      (cl-assert (null filter-view--group))
      (cl-assert (equal filter-view--query ""))
      (cl-assert (null filter-view--group-query))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))

      ;; On a formula row there is no group to narrow to, and the
      ;; command called directly says so.
      (goto-char (point-min))
      (filter-view-next-item)
      (cl-assert (equal (condition-case err
                            (progn (filter-view-filter-group) nil)
                          (user-error (cadr err)))
                        "Not on a group header"))
      (filter-view-quit)))

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
      (cl-assert (equal (filter-view--group-at-point) "Recent"))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal filter-view--group "Recent"))
      (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
      (cl-assert (not (string-match-p "Geometry" (buffer-string))))
      ;; The formula is listed once now, its category's copy narrowed
      ;; away with the rest.
      (cl-assert (= 1 (let ((n 0) (i 0) (s (buffer-string)))
                        (while (setq i (string-search "Volume of sphere" s i))
                          (setq n (1+ n) i (1+ i)))
                        n)))
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (null filter-view--group))
      (cl-assert (string-match-p "Geometry" (buffer-string)))

      ;; Forgetting the last entry while narrowed to the group takes the
      ;; narrowing with it: the group is gone, and a narrowing to a
      ;; group that is not there is an empty buffer with the legend for
      ;; its only way out.
      (execute-kbd-macro (kbd "RET"))
      (cl-assert (equal filter-view--group "Recent"))
      (filter-view-next-item)
      (execute-kbd-macro (kbd "D"))
      (cl-assert (null (filter-view--state :recents)))
      (cl-assert (null filter-view--group))
      (cl-assert (string-match-p "Geometry" (buffer-string)))
      (filter-view-quit)))

  ;; Put the session's formulas state back, as formulas.el does.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 grp--stash)
          maf-formulas--loaded (nth 1 grp--stash)
          maf-formulas-builtin (nth 3 grp--stash))
    (if (nth 4 grp--stash)
        (puthash "*maf-formulas*" (nth 4 grp--stash) filter-view--sessions)
      (remhash "*maf-formulas*" filter-view--sessions))
    (when (get-buffer "*maf-formulas*") (kill-buffer "*maf-formulas*"))
    (when (nth 2 grp--stash)
      (maf-use-formulas-mode 1))
    :restored))
