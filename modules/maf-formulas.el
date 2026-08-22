;; -*- lexical-binding: t; -*-
;;
;; modules/maf-formulas.el
;;
;; Saved-formula library. `maf-formulas' opens a menu of formulas
;; grouped by category, each shown beside its form, with a detail pane
;; following point — the formula in Big display, a description, and
;; what each variable means — re-rendering for each formula reached.
;; `O' toggles that following pane off and on, and the choice holds
;; for the rest of the session, so the menu reopens the way it was
;; left; the legend's "O follows" shows gold while it is on. `o' (or
;; `?') toggles the pane's visibility, deferring to that flag: with
;; `O' on, closing is only a peek at calc, the pane returning as soon
;; as point reaches another formula; with `O' off, `o' shows the
;; formula at point and moving off its line dismisses the pane again.
;; `C-g' closes the pane and turns follow off. RET pushes the formula
;; at point onto the calc stack.
;;
;; A formula is a plist. Only :expr is required; the rest are optional
;; and the detail pane renders just what is present:
;;
;;   (:name "area-of-triangle"          ; id for the calc var-eq-<name>
;;    :title "Area of triangle"         ; menu label (derived if absent)
;;    :category "Geometry — 2D"         ; grouping (a default if absent)
;;    :expr (calcFunc-eq ...)           ; REQUIRED — the equation/expr
;;    :doc "..."                        ; optional one-line description
;;    :examples ("..." ...)             ; optional worked examples
;;    :vars ((A . "area") ...))         ; optional variable meanings
;;
;; Formulas you insert are remembered in a "Recent" group at the top of
;; the menu for the rest of the session; it is not written anywhere.
;; `D' drops the entry at point from the group (the formula itself
;; stays, under its own category).
;;
;; The formulas live in `maf-formulas-file' (a file in your Emacs config
;; by default); it is loaded on first use and sets `maf-formulas-user'.
;; Set that variable directly in your init to skip the file. Enabling
;; the module (see `maf-modules') registers every formula as a calc
;; `var-eq-<name>' variable, so calc's own recall and rewrite see them
;; too — `maf-formulas-user' is the single source, calc's variables
;; generated from it.

(require 'calc)
(require 'maf-lib)
(require 'cl-lib)
(require 'maf-conf "conf")  ; the `maf' customize group
(require 'dial)             ; `dial-controls', the legend's chrome

;; The module installs its `s o' binding into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

;; Defined in lazily-loaded calc modules; declared for the byte compiler.
(declare-function math-format-value "calc-ext")
(declare-function calc-pop-push-record-list "calc-ext")

(defface maf-formulas-category
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for category headers and the detail title in the formula menu."
  :group 'maf)

(defface maf-formulas-recent
  '((t :inherit warning :weight bold))
  "Face for the \"Recent\" header in the formula menu.
Gold rather than the category color the other headers take: the group
is not a category at all, but what this session reached for last, and
it leads the buffer where the eye starts. The gold is `warning's,
which is where maf-edit's header badge takes its own from — one gold
across maf's buffers, and it follows the theme rather than pinning a
color that only suits some."
  :group 'maf)

(defface maf-formulas-var
  '((t :inherit font-lock-variable-name-face))
  "Face for variable names in the formula detail."
  :group 'maf)

(defface maf-formulas-leader
  '((t :inherit shadow))
  "Face for the dotted leader between a formula's name and its form."
  :group 'maf)

(defface maf-formulas-title
  '((((background dark))  :foreground "grey70")
    (((background light)) :foreground "grey35")
    (t :foreground "grey70"))
  "Face for the formula name (title) in the menu list."
  :group 'maf)

(defface maf-formulas-form
  '((((background dark))  :foreground "white")
    (((background light)) :foreground "black")
    (t :foreground "white"))
  "Face for the formula shown beside each title in the menu list."
  :group 'maf)

(defcustom maf-formulas-file (locate-user-emacs-file "maf-formulas.el")
  "File of saved formulas, loaded on first use when it exists.
The file sets `maf-formulas-user' to a list of formula plists (see the
commentary above for the shape). nil disables file loading; populate
`maf-formulas-user' from your init instead."
  :type '(choice (const :tag "None" nil) file)
  :group 'maf)

(defcustom maf-formulas-user nil
  "Your saved formulas, in the plist shape described in the commentary.
Loaded from `maf-formulas-file' when that file exists; set it directly
in your init to add formulas without a file. Only :expr is required."
  :type '(repeat plist)
  :group 'maf)

(defcustom maf-formulas-recent-max 5
  "How many recently-inserted formulas the \"Recent\" group holds.
Zero drops the group entirely. The list is per-session; nothing is
written to disk."
  :type 'integer
  :group 'maf)

(defcustom maf-formulas-detail-min-width 64
  "Narrowest pane, in columns, the detail is worth showing beside the list.
The pane splits the menu's window, so a side split halves its width
while a split below halves its height — the two leave the same number
of cells either way. What differs is the shape: the Big rendering and
the filled prose need a floor on width but can be scrolled for height,
so the side split is only taken when both halves clear this width."
  :type 'integer
  :group 'maf)

(defconst maf-formulas--detail-buffer " *maf-formulas-detail*"
  "Name of the buffer showing detail for the formula at point.")

(defconst maf-formulas--recent-category "Recent"
  "Category header for the recently-inserted group, shown first.")

(defvar maf-formulas--loaded nil
  "Non-nil once `maf-formulas-file' has been consulted this session.")

(defun maf-formulas--all ()
  "All saved formulas, loading `maf-formulas-file' the first time.
The file, when present, populates `maf-formulas-user'; after that the
variable is the single source, so runtime additions to it persist."
  (unless maf-formulas--loaded
    (setq maf-formulas--loaded t)
    (when (and maf-formulas-file (file-exists-p maf-formulas-file))
      (load (expand-file-name maf-formulas-file) nil t)))
  maf-formulas-user)

(defun maf-formulas--title (f)
  "Menu title for formula F, derived from its name when :title is absent."
  (or (plist-get f :title)
      (let ((s (replace-regexp-in-string "-" " " (or (plist-get f :name) "formula"))))
        (concat (upcase (substring s 0 1)) (substring s 1)))))

(defun maf-formulas--category (f)
  "Category for formula F, a default when :category is absent."
  (or (plist-get f :category) "Uncategorized"))

;;; The calc var-eq-<name> registration (single source of truth)

(defun maf-formulas--register-vars ()
  "Register each formula as a calc `var-eq-<name>' variable."
  (dolist (f (maf-formulas--all))
    (when-let ((name (plist-get f :name)))
      (set (intern (concat "var-eq-" name)) (plist-get f :expr)))))

(defun maf-formulas--unregister-vars ()
  "Unbind the `var-eq-<name>' variables this module registered."
  (dolist (f (maf-formulas--all))
    (when-let ((name (plist-get f :name)))
      (makunbound (intern (concat "var-eq-" name))))))

;;; Rendering

(defvar-local maf-formulas--query ""
  "Current filter string narrowing the formula menu, or empty.")

(defvar maf-formulas--recent nil
  "Formulas inserted this session, most recent first.
A plain variable, so the list dies with the session — recency is a
convenience for the sitting, not something to carry between them.")

(defun maf-formulas--record-recent (f)
  "Remember F as the most recently inserted formula."
  (when (> maf-formulas-recent-max 0)
    (setq maf-formulas--recent
          (cons f (seq-take (delq f maf-formulas--recent)
                            (1- maf-formulas-recent-max))))))

(defun maf-formulas--matches-p (f query)
  "Non-nil if formula F matches QUERY (title, category, or a variable)."
  (or (string-empty-p query)
      (let ((q (downcase query)))
        (or (string-search q (downcase (maf-formulas--title f)))
            (string-search q (downcase (maf-formulas--category f)))
            (cl-some (lambda (v) (string-search q (downcase (format "%s %s" (car v) (cdr v)))))
                     (plist-get f :vars))))))

(defun maf-formulas--groups ()
  "The menu's groups, an alist of (CATEGORY . FORMULAS).
Categories come alphabetically, each holding the formulas matching the
current query; the recently-inserted group leads when it has any, so
what you reached for last is where the cursor already is. A recent
formula also stays listed under its own category — the group is a
shortcut, not a move."
  (let* ((all (maf-formulas--all))
         (match (lambda (f) (maf-formulas--matches-p f maf-formulas--query)))
         ;; Recents are held by identity, so formulas dropped from
         ;; `maf-formulas-user' since (a reloaded file, say) fall out.
         (recent (seq-filter (lambda (f) (and (memq f all) (funcall match f)))
                             maf-formulas--recent))
         (groups nil))
    (dolist (f (seq-filter match all))
      (let* ((cat (maf-formulas--category f))
             (cell (assoc cat groups)))
        (if cell
            (setcdr cell (cons f (cdr cell)))
          (push (list cat f) groups))))
    (setq groups (sort (mapcar (lambda (g) (cons (car g) (nreverse (cdr g)))) groups)
                       (lambda (a b) (string< (car a) (car b)))))
    (if recent
        (cons (cons maf-formulas--recent-category recent) groups)
      groups)))

(defun maf-formulas--oneline (expr)
  "Render EXPR as a single normal-language line, for the list column."
  (let ((s (ignore-errors (let ((calc-language nil)) (math-format-value expr)))))
    (if s (replace-regexp-in-string "\n" " " s) "")))

;; Two of the detail pane's variables live up here with the renderer,
;; which consults them, rather than with the pane: forward references
;; from `maf-formulas--render' would otherwise be to free variables.

(defvar-local maf-formulas--detail-line nil
  "Beginning of the line the detail pane is currently rendered for, or nil.
`maf-formulas--detail-on-move' compares point against it, so the pane
re-renders when point reaches another formula and not on every command
that leaves it where it was.")

;; Not `--detail-state', its name when it was `defvar-local': the
;; buffer-local marking survives a reload, so going global took a new
;; name for live sessions to actually get a global.
(defvar maf-formulas--pane-state 'follow
  "How the detail pane is open: `frozen', `follow', or nil for closed.
`follow' is `maf-formulas-toggle-detail' (\\`O'): the pane re-renders
for each formula point reaches — the default, so the menu opens with
the pane already following. `frozen' is `maf-formulas-show-detail'
(\\`o') with follow off: the pane shows the one formula it was opened
on, and moving off that line dismisses it. Global where the pane's
other bookkeeping is buffer-local: the state is the session's choice,
not the buffer's, so quitting the menu and opening it again brings
the pane back the way it was left.")

(defun maf-formulas--header-line ()
  "The menu's header line: the key legend, or the filter in effect.
The legend reads like dial's controls line in *maf-options*: keys wear
`help-key-binding', entries set apart by spaces alone, and the band
itself takes `dial-controls' (the mode remaps `header-line' to it).
The \"O follows\" entry renders in gold — `warning's, the one gold
across maf's buffers — while the pane is following, so the legend
doubles as the toggle's indicator."
  (if (string-empty-p maf-formulas--query)
      (let ((entry (lambda (key verb)
                     (concat (propertize key 'face 'help-key-binding)
                             " " verb))))
        (mapconcat #'identity
                   (list "maf-formulas"
                         (funcall entry "RET" "inserts")
                         (funcall entry "/" "filters")
                         (funcall entry "o" "details")
                         (if (eq maf-formulas--pane-state 'follow)
                             (propertize "O follows" 'face 'warning)
                           (funcall entry "O" "follows"))
                         (funcall entry "D" "deletes recent")
                         (funcall entry "q" "quits"))
                   "   "))
    (format "maf-formulas — filter: %s  (q clears)" maf-formulas--query)))

(defun maf-formulas--refresh-header ()
  "Recompute the header line, for a state change without a re-render."
  (setq header-line-format (maf-formulas--header-line))
  (force-mode-line-update))

(defun maf-formulas--render ()
  "Render the categorized list: each formula beside its one-line form.
Groups are separated by a blank line."
  (let* ((inhibit-read-only t) (first t)
         (groups (maf-formulas--groups))
         (fs (apply #'append (mapcar #'cdr groups))))
    (erase-buffer)
    (setq header-line-format (maf-formulas--header-line))
    (let ((w (apply #'max 0 (mapcar (lambda (f) (length (maf-formulas--title f))) fs))))
      (dolist (g groups)
        (unless first (insert "\n"))    ; blank line above each group
        (setq first nil)
        (insert (propertize (car g) 'face
                            (if (equal (car g) maf-formulas--recent-category)
                                'maf-formulas-recent
                              'maf-formulas-category))
                "\n")
        (dolist (f (cdr g))
          (let* ((start (point))
                 (title (maf-formulas--title f))
                 ;; A dotted leader bridges the gap to the aligned formula
                 ;; column so the eye can track a short title across.
                 (leader (make-string (+ 1 (- w (length title))) ?.)))
            (insert "  " (propertize title 'face 'maf-formulas-title) " "
                    (propertize leader 'face 'maf-formulas-leader) " "
                    (propertize (maf-formulas--oneline (plist-get f :expr)) 'face 'maf-formulas-form)
                    "\n")
            (put-text-property start (point) 'maf-formula f)))))
    (goto-char (point-min))
    (while (and (not (eobp)) (not (get-text-property (point) 'maf-formula)))
      (forward-line 1))
    ;; A re-render changes what every line means, so a following pane
    ;; re-renders with it, for whatever point landed on. A frozen one
    ;; holds its formula: the filter it was narrowed by is no reason to
    ;; drop what the user put up to read.
    (when (eq maf-formulas--pane-state 'follow)
      (setq maf-formulas--detail-line (line-beginning-position))
      (maf-formulas--update-detail))))

;;; The detail pane

(defvar-local maf-formulas--detail-dir nil
  "Direction the detail pane was last split off in, `right' or `below'.
Chosen by `maf-formulas--detail-direction' when the pane opens; the
renderer consults it to know whether the pane's height is its own to
shrink.")

(defvar-local maf-formulas--detail-height nil
  "Height the detail pane has grown to while open, or nil when closed.
A floor for `maf-formulas--fit-detail', so the pane never shrinks
under a following pane's point.")

(defun maf-formulas--fill (text width)
  "TEXT filled to WIDTH and indented two spaces, for the description.
Only the description wraps: the Big rendering and the variable lines
keep their exact layout, but prose should bend to the pane."
  (with-temp-buffer
    (insert text)
    ;; Two columns for the indent, and one more spare: on a tty the
    ;; window's last column holds the truncation glyph, so a line of
    ;; exactly the pane's width still shows as `$'-truncated.
    (let ((fill-column (max 20 (- width 3))))
      (fill-region (point-min) (point-max)))
    (mapconcat (lambda (l) (concat "  " l))
               (split-string (buffer-string) "\n") "\n")))

(defun maf-formulas--detail-string (f width)
  "Detail text for F: title, Big rendering, description, variable meanings.
WIDTH is the pane's width in columns; the description fills to it."
  (let* ((expr (plist-get f :expr))
         (doc (plist-get f :doc))
         (examples (plist-get f :examples))
         (vars (plist-get f :vars))
         (big (ignore-errors (let ((calc-language 'big)) (math-format-value expr)))))
    (concat
     "\n  " (propertize (maf-formulas--title f) 'face 'maf-formulas-category) "\n\n"
     (propertize
      (mapconcat (lambda (l) (concat "  " l)) (split-string (or big "") "\n") "\n")
      'face 'maf-formulas-form)
     "\n"
     (when doc
       (concat "\n"
               (propertize (maf-formulas--fill doc width) 'face 'maf-formulas-title)
               "\n"))
     (when vars
       (concat "\n"
               (mapconcat (lambda (v)
                            (concat "  "
                                    (propertize (format "%s" (car v)) 'face 'maf-formulas-var)
                                    (propertize (format " = %s" (cdr v)) 'face 'maf-formulas-title)))
                          vars "\n")
               "\n"))
     (when examples
       (concat "\n"
               (mapconcat (lambda (e) (concat "  " (propertize (concat "e.g. " e) 'face 'shadow)))
                          examples "\n")
               "\n")))))

(defun maf-formulas--detail-direction ()
  "Where to split the detail pane off when no window can be borrowed.
`right' when there is width to spare, else `below'. The menu's own
window is what gets split, so the test is on its width, not the
frame's: a menu already sharing the frame with calc has less to give
away than the frame size suggests."
  (if (>= (window-body-width) (* 2 maf-formulas-detail-min-width))
      'right
    'below))

(defun maf-formulas--display-detail-elsewhere (buf alist)
  "Show BUF in another window on this frame, calc's for choice.
A `display-buffer' action function, and the pane's first preference:
the detail borrows a window the way a help buffer does rather than
carving the frame smaller. Calc's window is picked over the
least-recently-used one because the menu was called from calc — the
stack is what the user is least likely to be reading while looking a
formula up. Returns nil when there is nothing to borrow, so
`display-buffer' falls through to splitting."
  (let* ((cbuf (maf--find-calc-buffer))
         (win (or (and cbuf (get-buffer-window cbuf))
                  (get-lru-window nil nil t))))
    (when (and win
               (not (eq win (selected-window)))
               (not (window-dedicated-p win)))
      (window--display-buffer buf win 'reuse alist))))

(defun maf-formulas--split-p (win)
  "Non-nil when WIN was made for the detail pane rather than borrowed.
`display-buffer' records that in the window's `quit-restore' parameter:
a leading `window' means it created the window."
  (eq (car-safe (window-parameter win 'quit-restore)) 'window))

(defun maf-formulas--fit-detail (win)
  "Fit the detail pane WIN to the height its text needs.
Only for a pane split off below: there the height is room taken from
the list, so the pane asks for no more than it uses — a borrowed
window keeps whatever size its own buffer had. Capped at half the
frame so a long description cannot swallow the menu. Once open the
pane only ever grows: a following pane re-renders formula by formula,
and shrinking back on the short ones would leave the list jumping
under the cursor on every move."
  (when (and (eq maf-formulas--detail-dir 'below)
             (maf-formulas--split-p win))
    (let ((max-h (max 6 (/ (frame-height) 2))))
      (fit-window-to-buffer win max-h
                            (min max-h (or maf-formulas--detail-height 4)))
      (setq maf-formulas--detail-height (window-height win)))))

(defun maf-formulas--update-detail ()
  "Render the formula at point into the detail buffer.
The detail lives in its own buffer, so showing it never shifts the
list's own layout."
  (let ((f (or (get-text-property (line-beginning-position) 'maf-formula)
               ;; On a category header, preview that group's first formula.
               (save-excursion
                 (forward-line 1)
                 (while (and (not (eobp))
                             (not (get-text-property (line-beginning-position)
                                                     'maf-formula)))
                   (forward-line 1))
                 (get-text-property (line-beginning-position) 'maf-formula))))
        (dbuf (get-buffer maf-formulas--detail-buffer)))
    (when dbuf
      ;; The pane's real width when it is showing, else a stock fill.
      ;; `window-body-width' counts the columns line numbers occupy, so
      ;; subtract those or the fill overshoots by their width.
      (let ((width (let ((win (get-buffer-window dbuf)))
                     (if win
                         (- (window-body-width win)
                            (with-selected-window win
                              (ceiling (line-number-display-width 'columns))))
                       fill-column))))
        (with-current-buffer dbuf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (when f (insert (maf-formulas--detail-string f width)))
            (goto-char (point-min))))
        (when-let ((win (get-buffer-window dbuf)))
          (maf-formulas--fit-detail win))))))

(defun maf-formulas--close-detail ()
  "Put the detail pane's window back the way it was, when one is showing.
`quit-restore-window' undoes exactly what `display-buffer' did: the
window goes away if the pane made one, and the buffer it borrowed —
calc, normally — comes back if it did not."
  (let ((win (get-buffer-window maf-formulas--detail-buffer)))
    (setq maf-formulas--detail-height nil)
    (when (and win (not (eq win (selected-window))))
      (quit-restore-window win 'bury))))

(defun maf-formulas--detail-on-move ()
  "React to point's moves with the detail pane; on `post-command-hook'.
The pane reacts only to a line other than the one rendered, so the
commands that leave point where it was cost nothing. What it does
there is the `O' flag's call. Following, it re-renders — or comes
back, when \\<maf-formulas-mode-map>\\[maf-formulas-show-detail] hid it for a peek at what its window held. Frozen
\(follow off), the pane is dismissed instead, the window handed back:
the details were for the formula it was opened on, and point has
moved on."
  (unless (eq (line-beginning-position) maf-formulas--detail-line)
    (pcase maf-formulas--pane-state
      ('follow
       (if (get-buffer-window maf-formulas--detail-buffer)
           (progn (setq maf-formulas--detail-line (line-beginning-position))
                  (maf-formulas--update-detail))
         (maf-formulas--open-detail)))
      ('frozen
       (setq maf-formulas--pane-state nil
             maf-formulas--detail-line nil)
       (maf-formulas--close-detail)))))

(defun maf-formulas-keyboard-quit ()
  "Close the detail pane, then quit as \\[keyboard-quit] does.
On the menu's \\`C-g': the usual dismiss gesture shuts the pane whichever
way it was opened, so it takes neither a matching key nor leaving the menu."
  (interactive)
  (setq maf-formulas--detail-line nil
        maf-formulas--pane-state nil)
  (maf-formulas--close-detail)
  (maf-formulas--refresh-header)
  (keyboard-quit))

(defun maf-formulas--open-detail ()
  "Display the detail pane and render the formula at point into it."
  (let ((dbuf (get-buffer-create maf-formulas--detail-buffer)))
    (with-current-buffer dbuf
      (unless (derived-mode-p 'special-mode) (special-mode))
      (setq buffer-read-only t))
    ;; Borrow a window if the frame has one to lend (calc's, usually),
    ;; keeping it where it already is on a re-show; failing that, split
    ;; whichever way leaves the detail the better shape. Displayed
    ;; before rendering, so the description fills to the pane's real
    ;; width.
    (setq maf-formulas--detail-dir (maf-formulas--detail-direction))
    (display-buffer dbuf `((display-buffer-reuse-window
                            maf-formulas--display-detail-elsewhere
                            display-buffer-in-direction)
                           (direction . ,maf-formulas--detail-dir)
                           (inhibit-same-window . t)))
    (maf-formulas--update-detail)
    (setq maf-formulas--detail-line (line-beginning-position))))

(defun maf-formulas-show-detail ()
  "Show the detail pane, or close a pane that is up — a visibility toggle.
Either way the `O' flag (\\<maf-formulas-mode-map>\\[maf-formulas-toggle-detail]) keeps the say over what happens next.
With follow on, closing is a peek at what the window held — calc's
stack normally — the legend's gold untouched, and the pane returns on
its own the moment point reaches another formula. With follow off,
the pane shows the formula at point and moving off that line
dismisses it again: details on request, where follow makes them a
running commentary. On a category header it shows the group's first
formula."
  (interactive)
  (if (get-buffer-window maf-formulas--detail-buffer)
      (maf-formulas--close-detail)
    (unless maf-formulas--pane-state
      (setq maf-formulas--pane-state 'frozen))
    (maf-formulas--open-detail))
  (maf-formulas--refresh-header))

(defun maf-formulas-toggle-detail ()
  "Open a detail pane that follows point, or close a following one.
Where \\<maf-formulas-mode-map>\\[maf-formulas-show-detail] holds one formula, this re-renders for each formula
point reaches — for reading down a group. Pressed while such a pane is
up it closes it; pressed while \\[maf-formulas-show-detail] holds one, it takes the pane over
and starts following. The choice holds for the session: the menu
reopens with the pane the way this left it."
  (interactive)
  (if (eq maf-formulas--pane-state 'follow)
      (progn (setq maf-formulas--pane-state nil
                   maf-formulas--detail-line nil)
             (maf-formulas--close-detail))
    (setq maf-formulas--pane-state 'follow)
    (maf-formulas--open-detail))
  (maf-formulas--refresh-header))

;;; Commands

(defun maf-formulas-insert ()
  "Push the formula at point onto the calc stack, and quit the menu."
  (interactive)
  (let ((f (get-text-property (line-beginning-position) 'maf-formula)))
    (unless f (user-error "No formula on this line"))
    (let ((buf (or (maf--find-calc-buffer) (get-buffer "*Calculator*"))))
      (unless buf (user-error "No calc buffer found"))
      (with-current-buffer buf
        (calc-wrapper
         (calc-pop-push-record-list 0 "frml" (list (copy-tree (plist-get f :expr)))
                                    1 (list nil))))
      (maf-formulas--record-recent f)
      (message "Inserted: %s" (maf-formulas--title f))
      (maf-formulas-quit))))

(defun maf-formulas--recent-line-p ()
  "Non-nil when the line at point lies in the \"Recent\" group.
A recent formula is listed twice — here and under its own category —
so what matters is which copy point is on: the nearest header above
decides."
  (let* ((p (line-beginning-position))
         (header (car (last (seq-filter (lambda (s) (<= s p))
                                        (maf-formulas--group-starts))))))
    (and header
         (equal (save-excursion
                  (goto-char header)
                  (buffer-substring-no-properties header (line-end-position)))
                maf-formulas--recent-category))))

(defun maf-formulas-delete-recent ()
  "Drop the entry at point from the \"Recent\" group.
Only a line in that group qualifies: the group is the session's memory
of what was inserted, and this forgets one entry. The formula itself
is untouched, still listed under its own category."
  (interactive)
  (let ((f (get-text-property (line-beginning-position) 'maf-formula)))
    (unless (and f (maf-formulas--recent-line-p))
      (user-error "Not on a Recent entry"))
    (setq maf-formulas--recent (delq f maf-formulas--recent))
    (let ((line (line-number-at-pos)))
      (maf-formulas--render)
      (goto-char (point-min))
      (forward-line (1- line))
      ;; The line may now lie past the shrunken group — or the group may
      ;; be gone entirely — so settle on the nearest formula.
      (unless (get-text-property (line-beginning-position) 'maf-formula)
        (or (ignore-errors (maf-formulas-prev-item) t)
            (ignore-errors (maf-formulas-next-item) t))))
    (message "Removed from Recent: %s" (maf-formulas--title f))))

(defvar maf-formulas--filter-buffer nil
  "Menu buffer being narrowed while the minibuffer reads a filter.
Bound for the dynamic extent of `maf-formulas-filter' only.")

(defun maf-formulas--set-query (buf query)
  "Narrow menu buffer BUF to QUERY, re-rendering when it changed.
Rendering happens with BUF's window selected so point and the window's
view move together, as they would if the user had navigated there."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (unless (equal query maf-formulas--query)
        (setq maf-formulas--query query)
        (let ((win (get-buffer-window buf)))
          (if win
              (with-selected-window win (maf-formulas--render))
            (maf-formulas--render)))))))

(defun maf-formulas--filter-update ()
  "Narrow the menu to what is typed so far.
Runs on the minibuffer's own `post-command-hook'."
  (maf-formulas--set-query maf-formulas--filter-buffer
                           (minibuffer-contents-no-properties)))

(defun maf-formulas-filter (&optional query)
  "Narrow the formula menu to QUERY (title, category, or variable).
Called interactively, the list narrows as each character is typed, so
the match is visible before the filter is committed; RET keeps the
narrowing and \\[keyboard-quit] restores the one in effect before."
  (interactive)
  (if query
      (maf-formulas--set-query (current-buffer) query)
    (let* ((buf (current-buffer))
           (prev maf-formulas--query)
           (maf-formulas--filter-buffer buf))
      (condition-case nil
          ;; The live narrowing has already applied what was typed; the
          ;; returned string settles anything a final command changed.
          (maf-formulas--set-query
           buf (minibuffer-with-setup-hook
                   (lambda ()
                     (add-hook 'post-command-hook #'maf-formulas--filter-update nil t))
                 (read-string "Filter formulas: " prev)))
        (quit (maf-formulas--set-query buf prev)
              (signal 'quit nil))))))

(defun maf-formulas-clear-filter ()
  "Clear the formula menu filter."
  (interactive)
  (setq maf-formulas--query "")
  (maf-formulas--render))

(defun maf-formulas--group-starts ()
  "Buffer positions of each category header line."
  (let (starts)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((bol (line-beginning-position)))
          ;; A header is a non-blank line carrying no formula.
          (when (and (> (line-end-position) bol)
                     (not (get-text-property bol 'maf-formula)))
            (push bol starts)))
        (forward-line 1)))
    (nreverse starts)))

(defun maf-formulas-next-item ()
  "Move to the next formula line, skipping blank and category lines."
  (interactive)
  (let ((p (point)))
    (forward-line 1)
    (while (and (not (eobp)) (not (get-text-property (point) 'maf-formula)))
      (forward-line 1))
    (if (get-text-property (point) 'maf-formula)
        (beginning-of-line)
      (goto-char p)
      (user-error "No next formula"))))

(defun maf-formulas-prev-item ()
  "Move to the previous formula line, skipping blank and category lines."
  (interactive)
  (let ((p (point)))
    (forward-line -1)
    (while (and (not (bobp)) (not (get-text-property (point) 'maf-formula)))
      (forward-line -1))
    (if (get-text-property (point) 'maf-formula)
        (beginning-of-line)
      (goto-char p)
      (user-error "No previous formula"))))

(defun maf-formulas-next-group ()
  "Move to the next category header, stopping at the last one."
  (interactive)
  (let* ((p (line-beginning-position))
         (starts (maf-formulas--group-starts))
         (next (seq-find (lambda (s) (> s p)) starts)))
    (if next (goto-char next) (user-error "No next group"))))

(defun maf-formulas-prev-group ()
  "Move to this category's header, or the previous one, stopping at the first.
Like paragraph motion: the first press jumps to the current category
header, a second to the header before it."
  (interactive)
  (let* ((p (line-beginning-position))
         (starts (maf-formulas--group-starts))
         (cur (car (last (seq-filter (lambda (s) (<= s p)) starts))))
         (before (car (last (seq-filter (lambda (s) (< s p)) starts)))))
    (cond ((and cur (< cur p)) (goto-char cur))
          (before (goto-char before))
          (t (user-error "No previous group")))))

(defun maf-formulas-quit ()
  "Quit the formula menu, closing the detail pane too.
The menu's window is deleted if `maf-formulas' made one, or goes back to
the buffer it displaced if it borrowed one; the rest of the frame is
untouched either way."
  (interactive)
  (maf-formulas--close-detail)
  ;; `quit-window' is `pop-to-buffer''s counterpart: it deletes the
  ;; window when the menu made one, and puts the displaced buffer back
  ;; when it borrowed one. Either way the frame returns as it was.
  (quit-window))

(defun maf-formulas-quit-or-clear-filter ()
  "Clear the filter while the menu is narrowed, else quit the menu.
`q' out of a filtered view backs out of the filter first, so the key
that leaves never discards a narrowing you meant to keep looking at; a
second `q' then leaves. `maf-formulas-quit' always quits outright."
  (interactive)
  (if (string-empty-p maf-formulas--query)
      (maf-formulas-quit)
    (maf-formulas-clear-filter)))

(defvar maf-formulas-mode-map (make-sparse-keymap)
  "Keymap for `maf-formulas-mode'.")

;; Bindings outside the defvar so reloading applies edits.
(define-key maf-formulas-mode-map (kbd "RET") #'maf-formulas-insert)
(define-key maf-formulas-mode-map (kbd "/")   #'maf-formulas-filter)
(define-key maf-formulas-mode-map (kbd "g")   #'maf-formulas-clear-filter)
(define-key maf-formulas-mode-map (kbd "q")   #'maf-formulas-quit-or-clear-filter)
(define-key maf-formulas-mode-map (kbd "o")   #'maf-formulas-show-detail)
(define-key maf-formulas-mode-map (kbd "?")   #'maf-formulas-show-detail)
;; `d' — once an alias for `o' — is deliberately unbound; the explicit
;; nil clears it from a live map on reload.
(define-key maf-formulas-mode-map (kbd "d")   nil)
(define-key maf-formulas-mode-map (kbd "O")   #'maf-formulas-toggle-detail)
(define-key maf-formulas-mode-map (kbd "D")   #'maf-formulas-delete-recent)
(define-key maf-formulas-mode-map (kbd "C-g") #'maf-formulas-keyboard-quit)
;; Two levels of motion: n/p/j/k and TAB/S-TAB step formula to formula
;; (headers and the blank lines between groups are skipped), M-n/M-p
;; step group to group.
(define-key maf-formulas-mode-map (kbd "n")   #'maf-formulas-next-item)
(define-key maf-formulas-mode-map (kbd "p")   #'maf-formulas-prev-item)
(define-key maf-formulas-mode-map (kbd "j")   #'maf-formulas-next-item)
(define-key maf-formulas-mode-map (kbd "k")   #'maf-formulas-prev-item)
(define-key maf-formulas-mode-map (kbd "TAB")       #'maf-formulas-next-item)
(define-key maf-formulas-mode-map (kbd "<backtab>") #'maf-formulas-prev-item)
(define-key maf-formulas-mode-map (kbd "M-n") #'maf-formulas-next-group)
(define-key maf-formulas-mode-map (kbd "M-p") #'maf-formulas-prev-group)

(define-derived-mode maf-formulas-mode special-mode "maf-formulas"
  "Major mode for the saved-formula list.
Formulas are grouped by category, the ones inserted this session
repeated in a \"Recent\" group at the top, each shown beside its
form. \\<maf-formulas-mode-map>\\[maf-formulas-insert]
pushes the formula at point onto the stack, \\[maf-formulas-next-item] and \\[maf-formulas-prev-item] step
between formulas, \\[maf-formulas-next-group] between groups, \\[maf-formulas-show-detail] shows the formula at
point in the detail pane (again to close it), \\[maf-formulas-toggle-detail] toggles the pane following point (on by
default, remembered for the session), \\[maf-formulas-delete-recent] drops the recent entry at
point, \\[maf-formulas-filter] filters as you type, \\[maf-formulas-clear-filter] clears the filter, \\[maf-formulas-quit-or-clear-filter] clears the
filter when narrowed and quits otherwise."
  (setq truncate-lines t)
  ;; The legend's band is the options buffer's: `header-line's own look
  ;; is replaced outright, not layered under, so the two read as one
  ;; piece of chrome across maf's buffers.
  (face-remap-set-base 'header-line 'dial-controls)
  (add-hook 'post-command-hook #'maf-formulas--detail-on-move nil t))

;;;###autoload
(defun maf-formulas ()
  "Open the saved-formula menu, its detail pane following point.
\\<maf-formulas-mode-map>\\[maf-formulas-toggle-detail] toggles the pane, \\[maf-formulas-show-detail] freezes it on the formula at point."
  (interactive)
  (let ((buf (get-buffer-create "*maf-formulas*")))
    (with-current-buffer buf
      (maf-formulas-mode)
      (maf-formulas--render))
    ;; Ordinary `pop-to-buffer' display: Emacs picks the window by the
    ;; usual rules, so `display-buffer-alist' can route the menu, and
    ;; `maf-formulas-quit' undoes exactly what was done.
    (pop-to-buffer buf)
    ;; The pane's state survives the menu being quit (following by
    ;; default), so opening brings it back rather than starting closed.
    (when maf-formulas--pane-state
      (maf-formulas--open-detail))))

;;; The module

;;;###autoload
(define-minor-mode maf-use-formulas-mode
  "Make your saved formulas available in Calc.

Press s o to open *maf-formulas*. Formulas are grouped by category.
RET pushes the formula at point onto the stack, and o shows or hides
its explanation and variable names.

For example, a saved formula named distance can be inserted from the
menu instead of typed again. While this mode is on, Calc can also use
saved formulas as variables in recall and rewrite commands.

The formulas come from `maf-formulas-file'. Turning the mode off
removes the key and Calc variable registrations, but does not change
that file. You can still open the menu with M-x maf-formulas."
  :global t
  :group 'maf
  (if maf-use-formulas-mode
      (progn
        (maf-formulas--register-vars)
        (maf-bindings--refresh))
    (maf-formulas--unregister-vars)
    (maf-bindings--refresh)))

(maf-bindings-module-keys 'maf-formulas 'maf-use-formulas-mode
  '(((calc native vim) "s o" maf-formulas)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-formulas #'maf-use-formulas-mode
                       "Keep a library of formulas and push them onto the stack.

Press s o to open your formula library. RET pushes the formula at
point onto the stack; o shows its purpose and variable names. The
library is stored in `maf-formulas-file'."
                       "s o" "Memory"))

(provide 'maf-formulas)
