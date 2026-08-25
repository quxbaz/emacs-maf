;; Self-contained: the real formulas now live in `maf-formulas-file'
;; (the user's Emacs config), so this test supplies its own fixture in
;; `maf-formulas-user', sets `maf-formulas-builtin' aside, and marks
;; the file already-consulted so nothing on disk is read. The last
;; form restores the session state.

(maf-step
  (setq maf--formulas-stash (list maf-formulas-user maf-formulas--loaded
                                  maf-formulas--recent maf-use-formulas-mode
                                  maf-formulas--pane-state
                                  maf-formulas-builtin)
        maf-formulas--loaded t          ; skip loading maf-formulas-file
        maf-formulas--recent nil        ; a clean session's recents
        maf-formulas--pane-state 'follow  ; a fresh session's default
        maf-formulas-builtin nil        ; the fixture stands alone
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

  ;; Ten formulas are kept by default. Recording an eleventh drops the
  ;; oldest, leaving the ten most recently reached-for formulas.
  (cl-assert (= (eval (car (get 'maf-formulas-recent-max 'standard-value)) t)
                10))
  (let ((maf-formulas-recent-max 10)
        (maf-formulas--recent nil))
    (dotimes (n 11)
      (maf-formulas--record-recent (list :name (format "recent-%d" n))))
    (cl-assert (= (length maf-formulas--recent) 10))
    (cl-assert (equal (mapcar (lambda (f) (plist-get f :name))
                              maf-formulas--recent)
                      '("recent-10" "recent-9" "recent-8" "recent-7" "recent-6"
                        "recent-5" "recent-4" "recent-3" "recent-2" "recent-1"))))

  (with-current-buffer (get-buffer-create "*maf-formulas*")
    (maf-formulas-mode)
    (maf-formulas--render)
    ;; The menu lands on a formula line, grouped by category, with the
    ;; formula shown beside the title.
    (cl-assert (get-text-property (point) 'maf-formula))
    (cl-assert (string-match-p "=" (buffer-substring (line-beginning-position)
                                                     (line-end-position))))

    ;; The pane follows by default, and the legend's "O follows" shows
    ;; gold — `warning' — while it does.
    (cl-assert (eq maf-formulas--pane-state 'follow))
    (let ((h header-line-format))
      (cl-assert (eq (get-text-property (string-match "O follows" h) 'face h)
                     'warning)))

    ;; The detail renderer (behind `o' / `?', i.e.
    ;; `maf-formulas-show-detail') fills the detail buffer for the
    ;; formula at point.
    (cl-assert (eq (key-binding (kbd "o")) #'maf-formulas-show-detail))
    (cl-assert (eq (key-binding (kbd "?")) #'maf-formulas-show-detail))
    ;; `d', once an alias for `o', is unbound; `O' toggles the following
    ;; pane and `D' prunes the Recent group.
    (cl-assert (null (lookup-key maf-formulas-mode-map (kbd "d"))))
    (cl-assert (eq (key-binding (kbd "O")) #'maf-formulas-toggle-detail))
    (cl-assert (eq (key-binding (kbd "D")) #'maf-formulas-delete-recent))
    (maf-formulas--update-detail)
    (with-current-buffer maf-formulas--detail-buffer
      (cl-assert (> (buffer-size) 0))
      ;; A variable in the Big rendering wears the same face as its
      ;; meaning in the list below, so the eye can carry a symbol in the
      ;; formula down to what it stands for; the rest of the rendering
      ;; keeps the formula's own face. Point is on "Area of triangle",
      ;; whose Big middle line reads "A = - b h".
      (goto-char (point-min))
      (cl-assert (re-search-forward "^  \\(A\\)\\( = \\)- \\(b\\) \\(h\\)$" nil t))
      (dolist (g '(1 3 4))
        (cl-assert (eq (get-text-property (match-beginning g) 'face)
                       'maf-formulas-var)))
      (cl-assert (eq (get-text-property (match-beginning 2) 'face)
                     'maf-formulas-form)))

    ;; The pane borrows a window before it takes one: shown from a menu
    ;; that has calc beside it, it lands in calc's window and closing
    ;; hands that window back with calc in it — a help window's
    ;; contract, not a third pane in the frame.
    (save-window-excursion
      (delete-other-windows)
      (switch-to-buffer "*maf-formulas*")
      (let ((cwin (display-buffer (or (maf--find-calc-buffer)
                                      (get-buffer-create "*Calculator*"))
                                  '((display-buffer-in-direction)
                                    (direction . below)))))
        (maf-formulas-show-detail)
        (cl-assert (eq cwin (get-buffer-window maf-formulas--detail-buffer)))
        ;; Borrowed, not created — so its height is left alone.
        (cl-assert (not (maf-formulas--split-p cwin)))
        (cl-assert (= 2 (length (window-list))))
        (maf-formulas--close-detail)
        (cl-assert (eq (window-buffer cwin) (get-buffer "*Calculator*")))
        (cl-assert (= 2 (length (window-list)))))
      ;; Alone in the frame there is nothing to borrow, so the pane is
      ;; split off and closing deletes it again.
      (delete-other-windows)
      (maf-formulas-show-detail)
      (let ((win (get-buffer-window maf-formulas--detail-buffer)))
        (cl-assert (maf-formulas--split-p win))
        (maf-formulas--close-detail)
        (cl-assert (= 1 (length (window-list)))))

      ;; With follow off, `o' shows the formula at point on request:
      ;; staying on the line the pane stays, `o' again closes it by
      ;; hand, and moving off the line dismisses it — the window going
      ;; back to what it held, in respect of `O' being off.
      (delete-other-windows)
      (setq maf-formulas--pane-state nil)
      (goto-char (point-min))
      (maf-formulas-next-item)
      (maf-formulas-show-detail)
      (cl-assert (eq maf-formulas--pane-state 'frozen))
      (cl-assert (get-buffer-window maf-formulas--detail-buffer))
      (maf-formulas--detail-on-move)    ; point unmoved: the pane stays
      (cl-assert (get-buffer-window maf-formulas--detail-buffer))
      (maf-formulas-show-detail)
      (cl-assert (not (get-buffer-window maf-formulas--detail-buffer)))
      (maf-formulas-show-detail)
      (cl-assert (get-buffer-window maf-formulas--detail-buffer))
      (maf-formulas-next-item)
      (maf-formulas--detail-on-move)
      (cl-assert (null maf-formulas--pane-state))
      (cl-assert (not (get-buffer-window maf-formulas--detail-buffer)))

      ;; `O' opens the pane that follows point; pressed again it
      ;; closes.
      (maf-formulas-toggle-detail)
      (cl-assert (eq maf-formulas--pane-state 'follow))
      (let ((shown (with-current-buffer maf-formulas--detail-buffer (buffer-string))))
        (maf-formulas-prev-item)
        (maf-formulas--detail-on-move)
        (cl-assert (not (equal shown (with-current-buffer maf-formulas--detail-buffer
                                       (buffer-string))))))
      ;; `o' on a following pane is a peek at calc: follow stays on —
      ;; the legend keeps its gold — and the pane returns on its own
      ;; the moment point reaches another formula.
      (maf-formulas-show-detail)
      (cl-assert (eq maf-formulas--pane-state 'follow))
      (cl-assert (not (get-buffer-window maf-formulas--detail-buffer)))
      (let ((h header-line-format))
        (cl-assert (eq (get-text-property (string-match "O follows" h) 'face h)
                       'warning)))
      (maf-formulas-next-item)
      (maf-formulas--detail-on-move)
      (cl-assert (eq maf-formulas--pane-state 'follow))
      (cl-assert (get-buffer-window maf-formulas--detail-buffer))
      (maf-formulas-toggle-detail)
      (cl-assert (null maf-formulas--pane-state))
      (cl-assert (not (get-buffer-window maf-formulas--detail-buffer)))
      ;; Off, the legend's "O follows" loses its gold, the key wearing
      ;; the legend's usual `help-key-binding' like its neighbours.
      (let ((h header-line-format))
        (cl-assert (eq (get-text-property (string-match "O follows" h) 'face h)
                       'help-key-binding))))

    ;; `O's choice is the session's: quitting the menu and opening it
    ;; again brings the following pane back with it.
    (save-window-excursion
      (delete-other-windows)
      (setq maf-formulas--pane-state 'follow)
      (maf-formulas)
      (cl-assert (get-buffer-window maf-formulas--detail-buffer))
      (maf-formulas-quit)
      (cl-assert (not (get-buffer-window maf-formulas--detail-buffer)))
      (maf-formulas)
      (cl-assert (eq maf-formulas--pane-state 'follow))
      (cl-assert (get-buffer-window maf-formulas--detail-buffer))
      ;; Toggled off, quit, reopened: it stays off.
      (with-current-buffer "*maf-formulas*" (maf-formulas-toggle-detail))
      (maf-formulas-quit)
      (maf-formulas)
      (cl-assert (null maf-formulas--pane-state))
      (cl-assert (not (get-buffer-window maf-formulas--detail-buffer)))
      (maf-formulas-quit))

    ;; That split goes where the shape is better: beside the list when
    ;; halving the menu's window still leaves both halves at least
    ;; `maf-formulas-detail-min-width', under it when it would not.
    ;; Bound around the live window's own width, so the check does not
    ;; depend on the frame the suite happens to run in.
    (cl-assert (eq 'right (let ((maf-formulas-detail-min-width 1))
                            (maf-formulas--detail-direction))))
    (cl-assert (eq 'below (let ((maf-formulas-detail-min-width 1000))
                            (maf-formulas--detail-direction))))
    ;; Only a pane split below is fitted to its text — beside the list
    ;; its height is the menu's, and borrowed it is not the pane's.
    (let ((maf-formulas--detail-dir 'right))
      (cl-assert (null (maf-formulas--fit-detail (selected-window)))))

    ;; Groups are separated by a blank line (the two volume formulas sit
    ;; in different categories).
    (setq maf-formulas--query "volume")
    (maf-formulas--render)
    (cl-assert (string-match-p "\n\n" (buffer-string)))

    ;; The filter narrows the list.
    (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
    (cl-assert (not (string-match-p "triangle" (buffer-string))))

    ;; Several words are several searches, not one string: each word
    ;; has to turn up somewhere in the formula, in any order — the
    ;; literal "sphere volume" is nowhere in the list at all.
    (setq maf-formulas--query "sphere volume")
    (maf-formulas--render)
    (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
    (cl-assert (not (string-match-p "cylinder" (buffer-string))))
    ;; And the words may land in different fields: "volume" is a title
    ;; word, "height" a variable only the cylinder carries among the
    ;; two the first word leaves.
    (setq maf-formulas--query "volume height")
    (maf-formulas--render)
    (cl-assert (string-match-p "Volume of cylinder" (buffer-string)))
    (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))
    ;; Whitespace is what separates words, never something to match.
    (cl-assert (maf-formulas--matches-p (car maf-formulas-user)
                                        "  sphere   volume "))
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

  ;; `D' forgets the recent entry at point: the group shrinks, point
  ;; stays in it, and the formula keeps its place under its own
  ;; category.
  (with-current-buffer "*maf-formulas*"
    (maf-formulas-delete-recent)
    (cl-assert (equal (mapcar #'maf-formulas--title maf-formulas--recent)
                      '("Volume of sphere")))
    (cl-assert (equal (maf-formulas--title (get-text-property (point) 'maf-formula))
                      "Volume of sphere"))
    (cl-assert (maf-formulas--recent-line-p))
    (cl-assert (string-match-p "Area of triangle" (buffer-string)))
    ;; On a formula's category copy — or any non-Recent line — it refuses.
    (goto-char (point-max))
    (maf-formulas-prev-item)
    (cl-assert (not (maf-formulas--recent-line-p)))
    (cl-assert (condition-case nil (progn (maf-formulas-delete-recent) nil)
                 (user-error t)))
    ;; Deleting the last entry drops the group; point settles on a formula.
    (goto-char (point-min))
    (maf-formulas-next-item)
    (maf-formulas-delete-recent)
    (cl-assert (null maf-formulas--recent))
    (cl-assert (not (string-match-p "Recent" (buffer-string))))
    (cl-assert (get-text-property (point) 'maf-formula)))

  ;; Restore the session state the fixture displaced. Turning the mode
  ;; off first unregisters the fixture's var-eq-* variables; the real
  ;; formulas are then back in place, so re-enabling (when the session
  ;; had it on) registers those and hands `s o' back — a test run must
  ;; not leave the live instance without the module it borrowed.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 maf--formulas-stash)
          maf-formulas--loaded (nth 1 maf--formulas-stash)
          maf-formulas--recent (nth 2 maf--formulas-stash)
          maf-formulas--pane-state (nth 4 maf--formulas-stash)
          maf-formulas-builtin (nth 5 maf--formulas-stash))
    (when (nth 3 maf--formulas-stash)
      (maf-use-formulas-mode 1))))
