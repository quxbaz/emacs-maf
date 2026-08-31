;; Self-contained: the real formulas now live in `maf-formulas-file'
;; (the user's Emacs config), so this test supplies its own fixture in
;; `maf-formulas-user', sets `maf-formulas-builtin' aside, and marks
;; the file already-consulted so nothing on disk is read. The menu is
;; a filter-view; its session state (recents, folds, the pane flag)
;; lives in `filter-view--sessions' under the buffer's name, and is
;; stashed and restored around the run. The last form restores the
;; session state.

(maf-step
  (setq maf--formulas-stash (list maf-formulas-user maf-formulas--loaded
                                  maf-use-formulas-mode
                                  maf-formulas-builtin
                                  (gethash "*maf-formulas*" filter-view--sessions))
        maf-formulas--loaded t          ; skip loading maf-formulas-file
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

  ;; A clean session: no recents, no folds, the pane on its default.
  (progn
    (remhash "*maf-formulas*" filter-view--sessions)
    (maf-use-formulas-mode 1)
    (get-buffer-create " *maf-formulas-detail*"))

  ;; Ten formulas are kept by default. Recording an eleventh drops the
  ;; oldest, leaving the ten most recently reached-for formulas — held
  ;; by :name, the formula's identity for the group.
  (cl-assert (= (eval (car (get 'maf-formulas-recent-max 'standard-value)) t)
                10))
  (with-current-buffer (apply #'filter-view-setup "*maf-formulas*"
                              (maf-formulas--config))
    (let ((maf-formulas-recent-max 10))
      (dotimes (n 11)
        (filter-view--record-recent (list :name (format "recent-%d" n))))
      (cl-assert (equal (filter-view--state :recents)
                        '("recent-10" "recent-9" "recent-8" "recent-7" "recent-6"
                          "recent-5" "recent-4" "recent-3" "recent-2" "recent-1")))
      (filter-view--set-state :recents nil)))

  (with-current-buffer "*maf-formulas*"
    (filter-view--render)
    ;; The menu lands on a formula line, grouped by category, with the
    ;; formula shown beside the title.
    (cl-assert (get-text-property (point) 'filter-view-item))
    (cl-assert (string-match-p "=" (buffer-substring (line-beginning-position)
                                                     (line-end-position))))

    ;; The pane follows by default, and the legend's "O follows" shows
    ;; gold — `warning' — while it does.
    (cl-assert (eq (filter-view--pane-state) 'follow))
    (let ((h header-line-format))
      (cl-assert (eq (get-text-property (string-match "O follows" h) 'face h)
                     'warning)))

    ;; The detail renderer (behind `o' / `?', i.e.
    ;; `filter-view-show-detail') fills the detail buffer for the
    ;; formula at point.
    (cl-assert (eq (key-binding (kbd "o")) #'filter-view-show-detail))
    (cl-assert (eq (key-binding (kbd "?")) #'filter-view-show-detail))
    ;; `d' is unbound; `O' toggles the following pane and `D' prunes
    ;; the Recent group.
    (cl-assert (null (lookup-key filter-view-mode-map (kbd "d"))))
    (cl-assert (eq (key-binding (kbd "O")) #'filter-view-toggle-detail))
    (cl-assert (eq (key-binding (kbd "D")) #'filter-view-delete-recent))
    ;; The Big rendering is asserted with the pretty module's renderer
    ;; pinned off: installed, it would answer with an image instead.
    (let ((maf-preview-render-function nil))
      (filter-view--update-detail))
    (with-current-buffer " *maf-formulas-detail*"
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

    ;; With the pretty module's renderer installed the detail is
    ;; typeset instead — the same ask the preview panel makes, through
    ;; `maf-preview-render-function'. Mocked here; what marks a
    ;; rendering is its display property. A renderer that refuses
    ;; (nil) leaves the Big fallback standing.
    (when (display-graphic-p)
      (let ((maf-preview-render-function
             (lambda (_value) (propertize " " 'display '(image :type svg)))))
        (filter-view--update-detail))
      (with-current-buffer " *maf-formulas-detail*"
        (cl-assert (text-property-not-all (point-min) (point-max)
                                          'display nil))))
    (let ((maf-preview-render-function (lambda (_value) nil)))
      (filter-view--update-detail))
    (with-current-buffer " *maf-formulas-detail*"
      (cl-assert (null (text-property-not-all (point-min) (point-max)
                                              'display nil)))
      (goto-char (point-min))
      (cl-assert (re-search-forward "^  \\(A\\)\\( = \\)- \\(b\\) \\(h\\)$" nil t)))

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
        (filter-view-show-detail)
        (cl-assert (eq cwin (get-buffer-window " *maf-formulas-detail*")))
        ;; Borrowed, not created — so its height is left alone.
        (cl-assert (not (filter-view--split-p cwin)))
        (cl-assert (= 2 (length (window-list))))
        (filter-view--close-detail)
        (cl-assert (eq (window-buffer cwin) (get-buffer "*Calculator*")))
        (cl-assert (= 2 (length (window-list)))))
      ;; Alone in the frame there is nothing to borrow, so the pane is
      ;; split off and closing deletes it again.
      (delete-other-windows)
      (filter-view-show-detail)
      (let ((win (get-buffer-window " *maf-formulas-detail*")))
        (cl-assert (filter-view--split-p win))
        (filter-view--close-detail)
        (cl-assert (= 1 (length (window-list)))))

      ;; With follow off, `o' shows the formula at point on request:
      ;; staying on the line the pane stays, `o' again closes it by
      ;; hand, and moving off the line dismisses it — the window going
      ;; back to what it held, in respect of `O' being off.
      (delete-other-windows)
      (filter-view--set-pane-state nil)
      (goto-char (point-min))
      (filter-view-next-item)
      (filter-view-show-detail)
      (cl-assert (eq (filter-view--pane-state) 'frozen))
      (cl-assert (get-buffer-window " *maf-formulas-detail*"))
      (filter-view--detail-on-move)     ; point unmoved: the pane stays
      (cl-assert (get-buffer-window " *maf-formulas-detail*"))
      (filter-view-show-detail)
      (cl-assert (not (get-buffer-window " *maf-formulas-detail*")))
      (filter-view-show-detail)
      (cl-assert (get-buffer-window " *maf-formulas-detail*"))
      (filter-view-next-item)
      (filter-view--detail-on-move)
      (cl-assert (null (filter-view--pane-state)))
      (cl-assert (not (get-buffer-window " *maf-formulas-detail*")))

      ;; `O' opens the pane that follows point; pressed again it
      ;; closes.
      (filter-view-toggle-detail)
      (cl-assert (eq (filter-view--pane-state) 'follow))
      (let ((shown (with-current-buffer " *maf-formulas-detail*" (buffer-string))))
        (filter-view-prev-item)
        (filter-view--detail-on-move)
        (cl-assert (not (equal shown (with-current-buffer " *maf-formulas-detail*"
                                       (buffer-string))))))
      ;; `o' on a following pane is a peek at calc: follow stays on —
      ;; the legend keeps its gold — and the pane returns on its own
      ;; the moment point reaches another formula.
      (filter-view-show-detail)
      (cl-assert (eq (filter-view--pane-state) 'follow))
      (cl-assert (not (get-buffer-window " *maf-formulas-detail*")))
      (let ((h header-line-format))
        (cl-assert (eq (get-text-property (string-match "O follows" h) 'face h)
                       'warning)))
      (filter-view-next-item)
      (filter-view--detail-on-move)
      (cl-assert (eq (filter-view--pane-state) 'follow))
      (cl-assert (get-buffer-window " *maf-formulas-detail*"))
      (filter-view-toggle-detail)
      (cl-assert (null (filter-view--pane-state)))
      (cl-assert (not (get-buffer-window " *maf-formulas-detail*")))
      ;; Off, the legend's "O follows" loses its gold, the key wearing
      ;; the legend's usual `help-key-binding' like its neighbours.
      (let ((h header-line-format))
        (cl-assert (eq (get-text-property (string-match "O follows" h) 'face h)
                       'help-key-binding))))

    ;; `O's choice is the session's: quitting the menu and opening it
    ;; again brings the following pane back with it.
    (save-window-excursion
      (delete-other-windows)
      (filter-view--set-pane-state 'follow)
      (maf-formulas)
      (cl-assert (get-buffer-window " *maf-formulas-detail*"))
      (filter-view-quit)
      (cl-assert (not (get-buffer-window " *maf-formulas-detail*")))
      (maf-formulas)
      (cl-assert (eq (filter-view--pane-state) 'follow))
      (cl-assert (get-buffer-window " *maf-formulas-detail*"))
      ;; Toggled off, quit, reopened: it stays off.
      (with-current-buffer "*maf-formulas*" (filter-view-toggle-detail))
      (filter-view-quit)
      (maf-formulas)
      (cl-assert (null (filter-view--pane-state)))
      (cl-assert (not (get-buffer-window " *maf-formulas-detail*")))
      (filter-view-quit))

    ;; That split goes where the shape is better: beside the list when
    ;; halving the menu's window still leaves both halves at least
    ;; `maf-formulas-detail-min-width', under it when it would not.
    ;; Bound around the live window's own width, so the check does not
    ;; depend on the frame the suite happens to run in. The config
    ;; hands the width over as a closure, so the let is seen live.
    (cl-assert (eq 'right (let ((maf-formulas-detail-min-width 1))
                            (filter-view--detail-direction))))
    (cl-assert (eq 'below (let ((maf-formulas-detail-min-width 1000))
                            (filter-view--detail-direction))))
    ;; Only a pane split below is fitted to its text — beside the list
    ;; its height is the menu's, and borrowed it is not the pane's.
    (let ((filter-view--detail-dir 'right))
      (cl-assert (null (filter-view--fit-detail (selected-window)))))

    ;; Groups are separated by a blank line (the two volume formulas sit
    ;; in different categories).
    (setq filter-view--query "volume")
    (filter-view--render)
    (cl-assert (string-match-p "\n\n" (buffer-string)))

    ;; The filter narrows the list.
    (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
    (cl-assert (not (string-match-p "triangle" (buffer-string))))

    ;; Several words are several searches, not one string: each word
    ;; has to turn up somewhere in the formula, in any order — the
    ;; literal "sphere volume" is nowhere in the list at all.
    (setq filter-view--query "sphere volume")
    (filter-view--render)
    (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
    (cl-assert (not (string-match-p "cylinder" (buffer-string))))
    ;; And the words may land in different fields: "volume" is a title
    ;; word, "height" a variable only the cylinder carries among the
    ;; two the first word leaves.
    (setq filter-view--query "volume height")
    (filter-view--render)
    (cl-assert (string-match-p "Volume of cylinder" (buffer-string)))
    (cl-assert (not (string-match-p "Volume of sphere" (buffer-string))))
    ;; Whitespace is what separates words, never something to match.
    (cl-assert (filter-view--matches-p (car maf-formulas-user)
                                       "Geometry — 3D: Sphere"
                                       "  sphere   volume "))
    (setq filter-view--query "")
    (filter-view--render)

    ;; n steps formula to formula; M-n walks the groups and stops dead
    ;; at the last one rather than cycling. TAB is the fold
    ;; (tests/formulas-fold.el), n/p/j/k the item motion.
    (cl-assert (eq (key-binding (kbd "n")) #'filter-view-next-item))
    (cl-assert (eq (key-binding (kbd "TAB")) #'filter-view-toggle-all-groups))
    (cl-assert (eq (key-binding (kbd "M-n")) #'filter-view-next-group))
    (goto-char (point-min))
    (filter-view-next-item)
    (filter-view-next-group)
    (cl-assert (not (get-text-property (point) 'filter-view-item)))  ; a header
    (cl-assert (equal (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))
                      "Geometry — 3D: Cylinder"))
    (filter-view-next-group)
    (cl-assert (equal (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))
                      "Geometry — 3D: Sphere"))
    (let ((p (point)))                  ; the last header: M-n stops here
      (cl-assert (condition-case nil (progn (filter-view-next-group) nil)
                   (user-error t)))
      (cl-assert (= (point) p)))
    (goto-char (point-min))             ; the first header: M-p stops here
    (cl-assert (condition-case nil (progn (filter-view-prev-group) nil)
                 (user-error t)))
    (cl-assert (= (point) (point-min)))

    ;; Typing into the filter narrows live: the hook the reader installs
    ;; on the minibuffer pushes whatever has been typed so far.
    (let ((filter-view--filter-buffer (current-buffer))
          (filter-view--filter-touched nil))
      (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                 (lambda () "triangle")))
        (filter-view--filter-update))
      (cl-assert (equal filter-view--query "triangle"))
      (cl-assert (string-match-p "Area of triangle" (buffer-string)))
      (cl-assert (not (string-match-p "sphere" (buffer-string))))
      (cl-letf (((symbol-function 'minibuffer-contents-no-properties)
                 (lambda () "")))
        (filter-view--filter-update))
      (cl-assert (string-match-p "sphere" (buffer-string)))))

  ;; Every formula is registered as a calc var-eq-<name>.
  (cl-assert (boundp 'var-eq-volume-of-sphere))

  ;; RET (`filter-view-select') pushes the formula's equation onto the
  ;; stack, through this module's :select action.
  (calc-pop (calc-stack-size))
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (search-forward "Volume of sphere")
    (beginning-of-line)
    (cl-letf (((symbol-function 'filter-view-quit) (lambda (&rest _) nil)))
      (filter-view-select)))
  (cl-assert (string-match-p "V = " (math-format-value (calc-top-n 1))))
  (calc-pop (calc-stack-size))

  ;; That select seeded the Recent group: it heads the list, point lands
  ;; on it, and the formula still appears under its own category too.
  (with-current-buffer "*maf-formulas*"
    (filter-view--render)
    (cl-assert (equal (buffer-substring-no-properties (point-min)
                                                      (save-excursion
                                                        (goto-char (point-min))
                                                        (line-end-position)))
                      "Recent"))
    ;; It is set apart in its own face — the group is not a category, so
    ;; it does not take the group color the headers below it keep.
    (cl-assert (eq (get-text-property (point-min) 'face) 'filter-view-recent))
    (cl-assert (eq (save-excursion
                     (goto-char (point-min))
                     (search-forward "Geometry — 3D: Sphere")
                     (get-text-property (line-beginning-position) 'face))
                   'filter-view-group))
    (cl-assert (equal (maf-formulas--title (get-text-property (point) 'filter-view-item))
                      "Volume of sphere"))
    (cl-assert (= 2 (let ((n 0) (i 0) (s (buffer-string)))
                      (while (setq i (string-search "Volume of sphere" s i))
                        (setq n (1+ n) i (1+ i)))
                      n))))

  ;; A second select takes the head of the group, most recent first.
  ;; The group holds the formulas by :name, their filter-view key.
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (search-forward "Area of triangle")
    (beginning-of-line)
    (cl-letf (((symbol-function 'filter-view-quit) (lambda (&rest _) nil)))
      (filter-view-select))
    (filter-view--render)
    (cl-assert (equal (filter-view--state :recents)
                      '("area-of-triangle" "volume-of-sphere")))
    (cl-assert (equal (maf-formulas--title (get-text-property (point) 'filter-view-item))
                      "Area of triangle")))
  (calc-pop (calc-stack-size))

  ;; `D' forgets the recent entry at point: the group shrinks, point
  ;; stays in it, and the formula keeps its place under its own
  ;; category.
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (filter-view-next-item)
    (filter-view-delete-recent)
    (cl-assert (equal (filter-view--state :recents) '("volume-of-sphere")))
    (cl-assert (equal (maf-formulas--title (get-text-property (point) 'filter-view-item))
                      "Volume of sphere"))
    (cl-assert (filter-view--recent-line-p))
    (cl-assert (string-match-p "Area of triangle" (buffer-string)))
    ;; On a formula's category copy — or any non-Recent line — it refuses.
    (goto-char (point-max))
    (filter-view-prev-item)
    (cl-assert (not (filter-view--recent-line-p)))
    (cl-assert (condition-case nil (progn (filter-view-delete-recent) nil)
                 (user-error t)))
    ;; Deleting the last entry drops the group; point settles on a formula.
    (goto-char (point-min))
    (filter-view-next-item)
    (filter-view-delete-recent)
    (cl-assert (null (filter-view--state :recents)))
    (cl-assert (not (string-match-p "Recent" (buffer-string))))
    (cl-assert (get-text-property (point) 'filter-view-item)))

  ;; Restore the session state the fixture displaced. Turning the mode
  ;; off first unregisters the fixture's var-eq-* variables; the real
  ;; formulas are then back in place, so re-enabling (when the session
  ;; had it on) registers those and hands `s o' back — a test run must
  ;; not leave the live instance without the module it borrowed.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 maf--formulas-stash)
          maf-formulas--loaded (nth 1 maf--formulas-stash)
          maf-formulas-builtin (nth 3 maf--formulas-stash))
    (if (nth 4 maf--formulas-stash)
        (puthash "*maf-formulas*" (nth 4 maf--formulas-stash)
                 filter-view--sessions)
      (remhash "*maf-formulas*" filter-view--sessions))
    (when (get-buffer "*maf-formulas*") (kill-buffer "*maf-formulas*"))
    (when (nth 2 maf--formulas-stash)
      (maf-use-formulas-mode 1))))
