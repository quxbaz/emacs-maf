;; -*- lexical-binding: t; -*-
;;
;; filter-view.el — a filterable, grouped list menu
;;
;; Filter-view renders a consumer's items as a grouped menu buffer and
;; owns everything about driving one: instant narrowing as a filter is
;; typed, narrowing to one group, folding groups to their headers,
;; a "Recent" group remembering what was reached for, motion by item
;; and by group, a detail pane that can follow point, and the key
;; legend in the header line. What the items *are* — how one renders,
;; what a filter matches against, what RET does to one — is the
;; consumer's, told to `filter-view-open' as a handful of functions.
;;
;; The consumer's CONFIG is a plist:
;;
;;   :groups  REQUIRED. Function () -> alist of (GROUP-NAME . ITEMS),
;;            read fresh on every render, in the order the menu shows.
;;            An item is any object the other functions understand.
;;   :render  REQUIRED. Function (ITEM CTX) -> the item's text, faces
;;            and indentation included, one line or several. CTX is
;;            what :context answered, nil without one.
;;   :select  REQUIRED. Function (ITEM) -> what RET does to an item.
;;            Called with the menu buffer current; it may quit the
;;            menu (`filter-view-quit') or leave it up.
;;   :context Function (ITEMS) -> a value handed to each :render call,
;;            computed once per render over the items being drawn —
;;            for alignment an item cannot know alone.
;;   :key     Function (ITEM) -> a stable identity for the item,
;;            compared with `equal'. Recents and point restoration
;;            hold items by this key, so it is what lets an item
;;            rebuilt on the next render still count as the same one.
;;            Defaults to the item itself.
;;   :title   Function (ITEM) -> the name messages call the item by.
;;            Defaults to `format' %s of the item.
;;   :fields  Function (ITEM GROUP-NAME) -> strings the filter matches
;;            against (case-insensitively; see `filter-view-filter').
;;            Absent, the view has no filter and `/' says so.
;;   :detail  Function (ITEM WIDTH) -> the detail pane's text for the
;;            item, WIDTH the pane's columns for filling prose.
;;            Absent, the view has no pane and `?'/`w'/`O' say so.
;;   :detail-actions  `display-buffer' action functions for placing
;;            the pane; `display-buffer-in-direction' should end the
;;            list, the direction chosen by width is appended.
;;   :detail-min-width  Narrowest pane worth a side split, in columns;
;;            a number or a function () -> number. Default 64.
;;   :recent-max  How many items the "Recent" group holds; a number or
;;            a function () -> number, consulted live so a defcustom
;;            can back it. Zero keeps the keys but turns the group
;;            off; absent, the view has no recents at all.
;;   :group-blank  Non-nil sets a blank line under each group header,
;;            for items tall enough that the header would otherwise
;;            read as one of them. Folded headers never take it.
;;   :recent-label  The recent group's header. Default "Recent".
;;   :pane-default  How the pane starts the first time the view opens:
;;            `follow' (the default) or nil for closed. Thereafter the
;;            session's own choice holds — see `filter-view--sessions'.
;;   :name    What the legend and mode line call the view. Defaults to
;;            the buffer name.
;;   :select-verb  The legend's verb for RET, "selects" by default.
;;
;; State that should feel like the user's own — the recent items, the
;; folded groups, whether the pane follows — survives the buffer being
;; quit and reopened: it is kept per view name rather than in the
;; buffer, which a reopen resets. The narrowings (filter and group) do
;; reset on reopen, a fresh visit starting from the whole list.
;;
;; The chrome face `filter-view-controls' inherits dial's when dial is
;; loaded first, so the two packages' buffers read as one suite; alone,
;; it carries the same colors itself.

(require 'cl-lib)
(require 'seq)

(defgroup filter-view nil
  "A filterable, grouped list menu."
  :group 'convenience)

;;; Faces

(defface filter-view-group
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for group headers in a filter-view menu."
  :group 'filter-view)

(defface filter-view-recent
  '((t :inherit warning :weight bold))
  "Face for the \"Recent\" header in a filter-view menu.
Gold rather than the color the other headers take: the group is not
one of the consumer's groups at all, but what this session reached
for last, and it leads the buffer where the eye starts. `warning's
gold follows the theme rather than pinning a color."
  :group 'filter-view)

(defface filter-view-count
  '((t :inherit shadow))
  "Face for the item count a folded group's header wears."
  :group 'filter-view)

(defface filter-view-controls
  (if (facep 'dial-controls)
      '((t :inherit dial-controls))
    ;; dial's spec, copied: the band reads as chrome above the list.
    '((((class color) (background dark))  :background "#1c2733" :extend t)
      (((class color) (background light)) :background "#e2eaf3" :extend t)
      (t :inverse-video t)))
  "Face for the key legend's band in the header line.
Inherits `dial-controls' when dial is loaded before this package, so
the legend matches dial's controls line; standalone it carries the
same colors itself."
  :group 'filter-view)

;;; Session state, kept per view name

(defvar filter-view--sessions (make-hash-table :test #'equal)
  "Per-view state that outlives the buffer: view name -> plist.
The keys are :recents (item keys, most recent first), :collapsed
\(group names folded away) and :pane-state (`follow', `frozen' or nil).
Reopening a view resets its buffer — the mode call kills every local —
so what should feel like the user's own standing choices lives here,
keyed by the buffer's name.")

(defun filter-view--session-get (name key)
  "Session state KEY for the view named NAME."
  (plist-get (gethash name filter-view--sessions) key))

(defun filter-view--session-put (name key value)
  "Set session state KEY to VALUE for the view named NAME."
  (puthash name
           (plist-put (gethash name filter-view--sessions) key value)
           filter-view--sessions))

(defun filter-view--state (key)
  "Session state KEY for the current buffer's view."
  (filter-view--session-get (buffer-name) key))

(defun filter-view--set-state (key value)
  "Set session state KEY to VALUE for the current buffer's view."
  (filter-view--session-put (buffer-name) key value))

;;; The consumer's config

(defvar-local filter-view--config nil
  "The view's CONFIG plist; see this file's commentary.
Set by `filter-view-setup', before the first render.")

(defun filter-view--conf (key)
  "The view's CONFIG value for KEY."
  (plist-get filter-view--config key))

(defun filter-view--key (item)
  "ITEM's stable identity, through the consumer's :key."
  (if-let ((f (filter-view--conf :key))) (funcall f item) item))

(defun filter-view--title (item)
  "ITEM's name for messages, through the consumer's :title."
  (if-let ((f (filter-view--conf :title))) (funcall f item) (format "%s" item)))

(defun filter-view--recent-label ()
  "The recent group's header text."
  (or (filter-view--conf :recent-label) "Recent"))

(defun filter-view--recents-p ()
  "Non-nil when this view keeps a Recent group at all."
  (and (filter-view--conf :recent-max) t))

(defun filter-view--recent-max ()
  "How many recent items the view holds right now."
  (let ((m (filter-view--conf :recent-max)))
    (cond ((functionp m) (funcall m))
          ((numberp m) m)
          (t 0))))

(defun filter-view--detail-min-width ()
  "Narrowest pane, in columns, worth showing beside the list."
  (let ((w (filter-view--conf :detail-min-width)))
    (cond ((functionp w) (funcall w))
          ((numberp w) w)
          (t 64))))

(defun filter-view--pane-state ()
  "How the pane is open: `follow', `frozen', or nil for closed.
The session's choice when it has made one; before that, the config's
:pane-default — `follow' unless said otherwise — and always nil for a
view with no :detail."
  (let ((pl (gethash (buffer-name) filter-view--sessions)))
    (cond ((not (filter-view--conf :detail)) nil)
          ((plist-member pl :pane-state) (plist-get pl :pane-state))
          ((plist-member filter-view--config :pane-default)
           (filter-view--conf :pane-default))
          (t 'follow))))

(defun filter-view--set-pane-state (state)
  "Record STATE as the session's pane choice."
  (filter-view--set-state :pane-state state))

;;; Narrowing state, buffer-local (a reopen starts unnarrowed)

(defvar-local filter-view--query ""
  "Current filter string narrowing the menu, or empty.")

(defvar-local filter-view--group nil
  "Group the menu is narrowed to, or nil for every group.
Set by RET on a group header (`filter-view-filter-group'), and cleared
by RET on that header again, by `filter-view-clear-filter', or by a
filter — which searches the whole list, so it lifts this. It sits
beside `filter-view--query' rather than folding into it: the query is
words matched across the consumer's fields, where this picks one group
out by name — including the recent group, which no query can name.")

(defvar-local filter-view--group-query nil
  "Filter string set aside while a group narrowing is in effect, or nil.
Narrowing to a group shows the group whole, so the filter that was in
force is lifted rather than compounded — asking for a group is asking
for the group, not for the part of it that survived what was typed.
It is kept here so RET on the header again puts back the filtered list
it was pressed from. The two narrowings are never in force together:
filtering from inside a group leaves the group, taking this with it.")

(defvar-local filter-view--searching nil
  "Non-nil when the last render ran under a filter.
Lets `filter-view--sync-collapse' tell entering a search from being in
one, which is the difference between unfolding for the results and
overruling a fold the user has just made among them.")

(defun filter-view--sync-collapse ()
  "Unfold every group on entering a search, before a render reads the folds.
A search that left its groups folded would hide the very rows it
found, so starting one flips the folds open — once, not on every
render a filter causes: inside a search the folds are the user's. And
the folds are dropped rather than set aside; what a search leaves
behind is the list it found, open and readable."
  (let ((searching (not (string-empty-p filter-view--query))))
    (when (and searching (not filter-view--searching))
      (filter-view--set-state :collapsed nil))
    (setq filter-view--searching searching)))

(defun filter-view--collapsed-p (group)
  "Non-nil when GROUP is folded away to its header."
  (and (member group (filter-view--state :collapsed)) t))

;;; Matching and the groups a render draws

(defun filter-view--matches-p (item group query)
  "Non-nil if ITEM in GROUP matches QUERY against the consumer's fields.
QUERY is read as words, not as one string: each whitespace-separated
word has to turn up in some field, but they need not turn up together,
in one field, or in the order typed, and each further word narrows
what the ones before it left."
  (let ((fields (mapcar #'downcase
                        (funcall (filter-view--conf :fields) item group))))
    (cl-every (lambda (word)
                (cl-some (lambda (field) (string-search word field)) fields))
              (split-string (downcase query) nil t))))

(defun filter-view--recent-items (source)
  "The recent items still present in SOURCE, most recent first.
Recents are held by key, so an item rebuilt since — or one whose key
no longer appears in any group — resolves to the current item or falls
out."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (g source)
      (dolist (item (cdr g))
        (let ((k (filter-view--key item)))
          (unless (gethash k table) (puthash k item table)))))
    (delq nil (mapcar (lambda (k) (gethash k table))
                      (filter-view--state :recents)))))

(defun filter-view--groups ()
  "The groups this render draws, an alist of (GROUP-NAME . ITEMS).
The consumer's groups in the consumer's order, each holding the items
matching the current query, empty ones dropped. With no query and no
group narrowing, the recent group leads when it has any, so what was
reached for last is where the cursor already is; filtering omits that
shortcut group, its items remaining under their own groups.

`filter-view--group' narrows to the one group it names — the recent
group included, which a query cannot reach on its own. The two
narrowings are never in force at once."
  (let* ((source (funcall (filter-view--conf :groups)))
         (fields (filter-view--conf :fields))
         (query filter-view--query)
         (group filter-view--group)
         (recent-only (equal group (filter-view--recent-label)))
         (groups
          (if (or (string-empty-p query) (null fields))
              source
            (delq nil
                  (mapcar (lambda (g)
                            (let ((items (seq-filter
                                          (lambda (item)
                                            (filter-view--matches-p
                                             item (car g) query))
                                          (cdr g))))
                              (and items (cons (car g) items))))
                          source))))
         (recent (and (filter-view--recents-p)
                      (or recent-only
                          (and (null group) (string-empty-p query)))
                      (filter-view--recent-items source))))
    (when group
      (setq groups (if recent-only
                       nil
                     (seq-filter (lambda (g) (equal (car g) group)) groups))))
    (if recent
        (cons (cons (filter-view--recent-label) recent) groups)
      groups)))

;;; Rendering

(defvar-local filter-view--detail-line nil
  "Beginning of the line the detail pane is currently rendered for, or nil.
`filter-view--detail-on-move' compares point against it, so the pane
re-renders when point reaches another item and not on every command
that leaves it where it was.")

(defun filter-view--header-line ()
  "The menu's header line: the key legend, led by the narrowing in effect.
Entries a view lacks the feature for are left out. The \"O follows\"
entry renders in gold — `warning's — while the pane is following, so
the legend doubles as the toggle's indicator. A narrowing takes the
place of the view's name at the head of the band, and adds the key
that lifts it; the keys themselves stay put."
  (let* ((entry (lambda (key verb)
                  (concat (propertize key 'face 'help-key-binding) " " verb)))
         (state (delq nil
                      (list (when filter-view--group
                              (concat "group: "
                                      (propertize filter-view--group
                                                  'face 'warning)))
                            (unless (string-empty-p filter-view--query)
                              (concat "filter: "
                                      (propertize filter-view--query
                                                  'face 'warning)))))))
    (mapconcat
     #'identity
     (delq nil
           (list (if state (mapconcat #'identity state "  ")
                   (or (filter-view--conf :name) (buffer-name)))
                 (funcall entry "RET" (or (filter-view--conf :select-verb)
                                          "selects"))
                 (when (filter-view--conf :fields)
                   (funcall entry "/" "filters"))
                 (funcall entry "TAB" "folds")
                 ;; Only while something is narrowed: the key is noise
                 ;; until there is something for it to clear.
                 (when state (funcall entry "c" "clears"))
                 (when (filter-view--conf :detail)
                   (funcall entry "w/?" "details"))
                 (when (filter-view--conf :detail)
                   (if (eq (filter-view--pane-state) 'follow)
                       (propertize "O follows" 'face 'warning)
                     (funcall entry "O" "follows")))
                 (when (filter-view--recents-p)
                   (funcall entry "a/i" "adds recent"))
                 (when (filter-view--recents-p)
                   (funcall entry "D" "deletes recent"))
                 (funcall entry "q" "quits")))
     "   ")))

(defun filter-view--refresh-header ()
  "Recompute the header line, for a state change without a re-render."
  (setq header-line-format (filter-view--header-line))
  (force-mode-line-update))

(defun filter-view--render ()
  "Render the grouped list from the consumer's items.
Groups are separated by a blank line. A folded group renders as its
header alone, wearing the count of what it holds so the list still
says how much is down there; consecutive folded groups drop the blank
between them, the fold view being worth reading in one glance.

Each item's text carries the item in a `filter-view-item' property —
every line of it, so a multi-line item answers for any of its lines —
and its first line a `filter-view-stop' the motions stop on. A header
carries its group name in `filter-view-group', the folded count having
made the line and the name two different strings."
  (filter-view--sync-collapse)
  (let* ((inhibit-read-only t) (first t) (prev-folded nil)
         (groups (filter-view--groups))
         ;; Folded rows are not drawn, so they are no reason to shape
         ;; the context the drawn ones are rendered with.
         (visible (apply #'append
                         (mapcar (lambda (g)
                                   (unless (filter-view--collapsed-p (car g))
                                     (cdr g)))
                                 groups)))
         (ctx (when-let ((f (filter-view--conf :context)))
                (funcall f visible))))
    (erase-buffer)
    (setq header-line-format (filter-view--header-line))
    (dolist (g groups)
      (let ((folded (filter-view--collapsed-p (car g)))
            hstart)
        ;; A blank line above each group — unless the row just drawn
        ;; ended in one of its own, a consumer whose items are worth
        ;; spacing apart having already opened the gap. The group
        ;; break is a blank line, not one more than everything else.
        (unless (or first (and folded prev-folded)
                    (looking-back "\n\n" (max (point-min) (- (point) 2))))
          (insert "\n"))
        (setq first nil prev-folded folded hstart (point))
        (insert (propertize (car g) 'face
                            (if (equal (car g) (filter-view--recent-label))
                                'filter-view-recent
                              'filter-view-group)))
        (when folded
          (insert " " (propertize (format "(%d)" (length (cdr g)))
                                  'face 'filter-view-count)))
        (insert "\n")
        (put-text-property hstart (point) 'filter-view-group (car g))
        ;; The blank sits under the header, outside its property, so
        ;; it is no part of the group's own line — the motions and
        ;; `filter-view--group-at-point' read a bare line as nothing.
        ;; Never under a folded header: the fold view is worth reading
        ;; in one glance, which is what dropping the blanks buys.
        (when (and (not folded) (filter-view--conf :group-blank))
          (insert "\n"))
        (unless folded
          (dolist (item (cdr g))
            (let ((start (point)))
              (insert (funcall (filter-view--conf :render) item ctx))
              (unless (bolp) (insert "\n"))
              (put-text-property start (point) 'filter-view-item item)
              (put-text-property start (1+ start) 'filter-view-stop t))))))
    (goto-char (point-min))
    (while (and (not (eobp))
                (not (get-text-property (point) 'filter-view-item)))
      (forward-line 1))
    (filter-view--item-start)
    ;; A re-render changes what every line means, so a following pane
    ;; re-renders with it, for whatever point landed on. A frozen one
    ;; holds its item: the filter it was narrowed by is no reason to
    ;; drop what the user put up to read.
    (when (eq (filter-view--pane-state) 'follow)
      (setq filter-view--detail-line (line-beginning-position))
      (filter-view--update-detail))))

(defun filter-view--render-visible ()
  "Re-render the current menu buffer with its window selected.
Point and the window's view then move together, as they would had the
user navigated there."
  (let ((win (get-buffer-window (current-buffer))))
    (if win
        (with-selected-window win (filter-view--render))
      (filter-view--render))))

;;; Reading the buffer back

(defun filter-view--item-at-point ()
  "The item the line at point belongs to, or nil."
  (get-text-property (line-beginning-position) 'filter-view-item))

(defun filter-view--group-at-point ()
  "The group name when point is on a group header, else nil."
  (let ((bol (line-beginning-position)))
    (and (not (get-text-property bol 'filter-view-item))
         (get-text-property bol 'filter-view-group))))

(defun filter-view--group-starts ()
  "Buffer positions of each group header line."
  (let (starts)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (filter-view--group-at-point)
          (push (line-beginning-position) starts))
        (forward-line 1)))
    (nreverse starts)))

(defun filter-view--goto-group (group)
  "Put point on GROUP's header line, when the current render shows one."
  (when-let ((pos (save-excursion
                    (goto-char (point-min))
                    (catch 'found
                      (while (not (eobp))
                        (when (equal (filter-view--group-at-point) group)
                          (throw 'found (line-beginning-position)))
                        (forward-line 1))
                      nil))))
    (goto-char pos)))

(defun filter-view--group-of-point ()
  "The group the line at point belongs to.
Its own name on a header, and the nearest header above anywhere else —
so a key meaning \"this group\" can be pressed anywhere in it."
  (or (filter-view--group-at-point)
      (let* ((p (line-beginning-position))
             (header (car (last (seq-filter (lambda (s) (<= s p))
                                            (filter-view--group-starts))))))
        (and header (save-excursion (goto-char header)
                                    (filter-view--group-at-point))))))

(defun filter-view--recent-line-p ()
  "Non-nil when the line at point lies in the recent group.
A recent item is listed twice — there and under its own group — so
what matters is which copy point is on: the nearest header above
decides."
  (let* ((p (line-beginning-position))
         (header (car (last (seq-filter (lambda (s) (<= s p))
                                        (filter-view--group-starts))))))
    (and header
         (equal (save-excursion
                  (goto-char header)
                  (filter-view--group-at-point))
                (filter-view--recent-label)))))

(defun filter-view--goto-item (item &optional recent)
  "Put point on ITEM's row, RECENT choosing which copy.
An item in the recent group is listed twice — there and under its own
group — so a re-render leaves two rows to land on. With RECENT non-nil
the group's copy is taken, otherwise the other. When the wanted copy
is not on screen the other serves; when neither is, point stays where
the render left it and nil is returned."
  (let ((key (filter-view--key item))
        wanted other)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let ((it (filter-view--item-at-point)))
          (when (and it
                     (get-text-property (line-beginning-position)
                                        'filter-view-stop)
                     (equal (filter-view--key it) key))
            (if (eq (and (filter-view--recent-line-p) t) (and recent t))
                (unless wanted (setq wanted (line-beginning-position)))
              (unless other (setq other (line-beginning-position))))))
        (forward-line 1)))
    (when-let ((pos (or wanted other)))
      (goto-char pos)
      (filter-view--item-start)
      pos)))

;;; Motion

(defun filter-view--item-start ()
  "Put point on the first character of the line's entry.
The rows are indented, so a line's own beginning is a column of blanks
and a cursor sitting there reads as being beside the entry rather than
on it. Headers start in column zero, and are left where they are."
  (back-to-indentation))

(defun filter-view--stop-p (&optional item-only)
  "Non-nil when the line at point is one the motion commands stop on.
That is an item's first line, or — unless ITEM-ONLY — a group header
too: a header is a place worth reaching now that RET on one narrows
the menu to its group, so the same keys that walk the items walk the
headers between them."
  (if item-only
      (get-text-property (line-beginning-position) 'filter-view-stop)
    (or (get-text-property (line-beginning-position) 'filter-view-stop)
        (filter-view--group-at-point))))

(defun filter-view--seek-item (step &optional item-only)
  "Step by STEP lines to the nearest stop, returning point, or nil for none.
Point is left where it was when there is nothing to reach. ITEM-ONLY
passes through to `filter-view--stop-p'."
  (let ((p (point))
        (edge (if (> step 0) #'eobp #'bobp)))
    (forward-line step)
    (while (and (not (funcall edge)) (not (filter-view--stop-p item-only)))
      (forward-line step))
    (cond ((filter-view--stop-p item-only)
           (filter-view--item-start)
           (point))
          (t (goto-char p) nil))))

(defun filter-view-next-item ()
  "Move to the next item or group header, skipping the lines between."
  (interactive)
  (unless (filter-view--seek-item 1)
    (user-error "No next item")))

(defun filter-view-prev-item ()
  "Move to the previous item or group header, skipping the lines between."
  (interactive)
  (unless (filter-view--seek-item -1)
    (user-error "No previous item")))

(defun filter-view-next-group ()
  "Move to the next group header, stopping at the last one."
  (interactive)
  (let* ((p (line-beginning-position))
         (next (seq-find (lambda (s) (> s p)) (filter-view--group-starts))))
    (if next (goto-char next) (user-error "No next group"))))

(defun filter-view-prev-group ()
  "Move to this group's header, or the previous one, stopping at the first.
Like paragraph motion: the first press jumps to the current group's
header, a second to the header before it."
  (interactive)
  (let* ((p (line-beginning-position))
         (starts (filter-view--group-starts))
         (cur (car (last (seq-filter (lambda (s) (<= s p)) starts))))
         (before (car (last (seq-filter (lambda (s) (< s p)) starts)))))
    (cond ((and cur (< cur p)) (goto-char cur))
          (before (goto-char before))
          (t (user-error "No previous group")))))

;;; Folding

(defvar-local filter-view--fold-return nil
  "The row point was on when the fold just made was made.
A list of (COMMAND ITEM RECENT): the fold command that recorded it, the
item point stood on, and which copy of it — see `filter-view--goto-item'.

Folding takes that row out of the buffer, so point falls back to the
group's header. Unfolding again with the very same key, and nothing
pressed in between, puts point back on the row: the pair reads as one
look down the headers rather than a move. Anything else meanwhile ends
the pair, the record only being consumed while `last-command' is still
the command that wrote it.")

(defun filter-view--fold-remember ()
  "Record the row point is on, for the unfold that may follow the fold."
  (setq filter-view--fold-return
        (when-let ((item (filter-view--item-at-point)))
          (list this-command item (filter-view--recent-line-p)))))

(defun filter-view--fold-restore ()
  "Put point back on the row the fold before this one took it off.
Non-nil when point moved; nil when there is no such row, when
something was pressed since the fold, or when the row is no longer in
the list."
  (let ((rec filter-view--fold-return))
    (setq filter-view--fold-return nil)
    (and rec
         (eq (nth 0 rec) this-command)
         (eq last-command this-command)
         (filter-view--goto-item (nth 1 rec) (nth 2 rec)))))

(defun filter-view-toggle-group ()
  "Fold the group at point away to its header, or unfold it again.
A folded group keeps its header and wears the count of what it holds,
so a list too long to read is read as its group names instead — fold
what is not wanted, glance down the headers, unfold the one that is.
Pressed on an item row it folds the group that row is in, point coming
to rest on the header; pressed on that header it unfolds, point going
back to the row it was on when the group folded
\(`filter-view--fold-return').

Folds are not a narrowing: the folded items are still in the list,
still counted, and clearing the filter leaves them folded — a fold is
undone where it was made. Starting a search is the exception, and
unfolds everything so that what it turns up can be seen
\(`filter-view--sync-collapse')."
  (interactive)
  (let* ((group (filter-view--group-of-point))
         (folded (and group (filter-view--collapsed-p group))))
    (unless group (user-error "No group here"))
    (unless folded (filter-view--fold-remember))
    (filter-view--set-state :collapsed
                            (if folded
                                (remove group (filter-view--state :collapsed))
                              (cons group (filter-view--state :collapsed))))
    (filter-view--render)
    (unless (and folded (filter-view--fold-restore))
      (filter-view--goto-group group)
      (filter-view--item-start))))

(defun filter-view-toggle-all-groups ()
  "Fold every group away to its headers, or unfold them all.
The fold view for the whole list in one key: with anything folded this
unfolds the lot, otherwise it folds the lot. Point keeps its group,
landing on that header when the rows it was among have gone, and the
unfold that follows straight after puts it back on its row
\(`filter-view--fold-return'). What it folds does not depend on where
it is pressed; folding one group at a time is
\\<filter-view-mode-map>\\[filter-view-toggle-group]."
  (interactive)
  (let* ((group (filter-view--group-of-point))
         (folded (filter-view--state :collapsed)))
    (unless folded (filter-view--fold-remember))
    (filter-view--set-state :collapsed
                            (unless folded
                              (mapcar #'car (filter-view--groups))))
    (filter-view--render)
    (unless (and folded (filter-view--fold-restore))
      (when group (filter-view--goto-group group))
      (filter-view--item-start))))

;;; Recents

(defun filter-view--record-recent (item)
  "Remember ITEM as the most recently selected, when the view keeps recents."
  (let ((max (filter-view--recent-max)))
    (when (> max 0)
      (let ((key (filter-view--key item)))
        (filter-view--set-state
         :recents
         (cons key (seq-take (delete key (filter-view--state :recents))
                             (1- max))))))))

(defun filter-view-add-recent ()
  "Add the item at point to the recent group, without selecting it.
The group is otherwise written only by RET; this marks an item as
reached-for and stays put, so a handful can be gathered in one visit
and found at the top of the list next time. An item already in the
group moves back to its head.

The narrowing is no obstacle: the row under point is what counts, so a
filtered list marks the same way an unfiltered one does. Point keeps
its place rather than following the render to the top, and its copy
with it: marking from the group's own line stays there."
  (interactive)
  (let ((item (filter-view--item-at-point)))
    (unless item (user-error "Nothing on this line"))
    (unless (filter-view--recents-p)
      (user-error "This view keeps no Recent group"))
    (when (<= (filter-view--recent-max) 0)
      (user-error "The Recent group is turned off"))
    (let ((recent (filter-view--recent-line-p)))
      (filter-view--record-recent item)
      (filter-view--render)
      (filter-view--goto-item item recent))
    (when (eq (filter-view--pane-state) 'follow)
      (setq filter-view--detail-line (line-beginning-position))
      (filter-view--update-detail))
    (message "Added to Recent: %s" (filter-view--title item))))

(defun filter-view-delete-recent ()
  "Drop the entry at point from the recent group.
Only a line in that group qualifies: the group is the session's memory
of what was selected, and this forgets one entry. The item itself is
untouched, still listed under its own group."
  (interactive)
  (let ((item (filter-view--item-at-point)))
    (unless (and item (filter-view--recent-line-p))
      (user-error "Not on a Recent entry"))
    (filter-view--set-state :recents
                            (delete (filter-view--key item)
                                    (filter-view--state :recents)))
    ;; Forgetting the last entry while narrowed to the group leaves the
    ;; narrowing pointing at a group that no longer exists — an empty
    ;; buffer. The group is gone, so the narrowing to it goes with it.
    (unless (filter-view--state :recents)
      (when (equal filter-view--group (filter-view--recent-label))
        (setq filter-view--group nil)))
    (let ((line (line-number-at-pos)))
      (filter-view--render)
      (goto-char (point-min))
      (forward-line (1- line))
      ;; The line may now lie past the shrunken group — or the group may
      ;; be gone entirely — so settle on the nearest item. A header is
      ;; no landing place here: what was deleted was a row, and a row
      ;; is what replaces it.
      (unless (filter-view--stop-p t)
        (or (filter-view--seek-item -1 t)
            (filter-view--seek-item 1 t))))
    (message "Removed from Recent: %s" (filter-view--title item))))

;;; The filter

(defvar filter-view--filter-buffer nil
  "Menu buffer being narrowed while the minibuffer reads a filter.
Bound for the dynamic extent of `filter-view-filter' only.")

(defvar filter-view--filter-touched nil
  "Non-nil once anything has been typed into the filter minibuffer.
The prompt opens empty, but the narrowing in effect holds until the
user actually types: an untouched empty minibuffer means \"nothing
said yet\", not \"show everything\". Bound alongside
`filter-view--filter-buffer'.")

(defun filter-view--lift-group (buf)
  "Widen menu buffer BUF out of any group narrowing, re-rendering if it had one.
What a filter searches is the whole list, so the group a filter meets
is lifted rather than searched inside — and the filter it had set
aside goes with it, there being nothing left to come back to."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when filter-view--group
        (setq filter-view--group nil
              filter-view--group-query nil)
        (filter-view--render-visible)))))

(defun filter-view--set-query (buf query)
  "Narrow menu buffer BUF to QUERY, re-rendering when it changed.
Any group narrowing is lifted with it: a filter is a search over every
item, not over the corner of the list last stepped into."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (if (equal query filter-view--query)
          (filter-view--lift-group buf)
        (setq filter-view--query query
              filter-view--group nil
              filter-view--group-query nil)
        (filter-view--render-visible)))))

(defun filter-view--restore-narrowing (buf query group group-query)
  "Put menu buffer BUF's narrowing back to QUERY, GROUP and GROUP-QUERY.
The way back from a filter that was abandoned: setting a query only
ever widens out of a group, where \\[keyboard-quit] has one to put back."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq filter-view--query query
            filter-view--group group
            filter-view--group-query group-query)
      (filter-view--render-visible))))

(defun filter-view--filter-update ()
  "Narrow the menu to what is typed so far.
Runs on the minibuffer's own `post-command-hook'. Until the first
edit, the empty prompt leaves the current narrowing alone — a group
included, which the first character typed then lifts, the search being
over the whole list; deleting back to empty after typing does widen to
the full list."
  (let ((s (minibuffer-contents-no-properties)))
    (unless (and (string-empty-p s) (not filter-view--filter-touched))
      (setq filter-view--filter-touched t)
      (filter-view--set-query filter-view--filter-buffer s))))

(defun filter-view-filter (&optional query)
  "Narrow the menu to QUERY, matched against the consumer's fields.
QUERY is matched a word at a time — \"power rule\" finds the items
named by both words, in either order and in any field a filter looks
at (see `filter-view--matches-p').

A filter searches the whole list, so a group narrowing in force is
lifted rather than searched inside — but not before there is a search:
the prompt opens on the group, and the first character typed widens to
every item. An abandoned \\`/' leaves the list exactly as it was, and
\\[keyboard-quit] after typing puts the group back with the rest.

Called interactively, the list narrows as each character is typed, so
the match is visible before the filter is committed; RET keeps the
narrowing and \\[keyboard-quit] restores the one in effect before."
  (interactive)
  (unless (filter-view--conf :fields)
    (user-error "This view has no filter"))
  (if query
      (filter-view--set-query (current-buffer) query)
    (let* ((buf (current-buffer))
           (prev filter-view--query)
           (prev-group filter-view--group)
           (prev-group-query filter-view--group-query)
           (filter-view--filter-buffer buf)
           (filter-view--filter-touched nil))
      (condition-case nil
          ;; The live narrowing has already applied what was typed; the
          ;; returned string settles anything a final command changed.
          ;; RET on an untouched prompt is left alone entirely — the
          ;; list never previewed anything else.
          (let ((s (minibuffer-with-setup-hook
                       (lambda ()
                         (add-hook 'post-command-hook
                                   #'filter-view--filter-update nil t))
                     (read-string "Filter: "))))
            (when filter-view--filter-touched
              (filter-view--set-query buf s)))
        (quit (filter-view--restore-narrowing buf prev prev-group
                                              prev-group-query)
              (signal 'quit nil))))))

(defun filter-view-clear-filter ()
  "Clear the menu's narrowing — the filter string and any group with it.
The list can be narrowed two ways at once, by what was typed and by
the group RET was pressed on; one key puts the whole list back rather
than leaving the other narrowing to be found and undone."
  (interactive)
  (setq filter-view--query ""
        filter-view--group nil
        filter-view--group-query nil)
  (filter-view--render))

(defun filter-view-filter-group (&optional group)
  "Narrow the menu to GROUP, the group header at point by default.
A group's header is both the way in and the way out: RET on one leaves
that group alone on screen, and RET on the header again — it is still
there, at the top — widens back to every group. Point stays on the
header across both, so the key can be pressed twice for a look and a
return.

The group comes up whole. A filter in force is lifted for it, not
compounded with it: the header names a group of items, and reaching
for it from a filtered list asks for that group, not for the part of
it the filter had left standing. The filter is not lost — widening
again puts it back, and the list returns to the one the header was
pressed from. Filtering with \\<filter-view-mode-map>\\[filter-view-filter] is the other way out: a filter
searches the whole list, so it leaves the group rather than narrowing
inside it. \\[filter-view-clear-filter] drops the lot, whichever way the list was narrowed.

The recent group narrows like any other, and is the one group a filter
string cannot reach — it is a shortcut rather than one of the
consumer's groups, so no field of its items names it."
  (interactive)
  (let ((group (or group (filter-view--group-at-point))))
    (unless group (user-error "Not on a group header"))
    (if (equal group filter-view--group)
        ;; Widening: the filter the narrowing lifted comes back with
        ;; the other groups, so the round trip lands where it started.
        (setq filter-view--group nil
              filter-view--query (or filter-view--group-query "")
              filter-view--group-query nil)
      ;; Asking for a group is asking to see it, so a fold on the way
      ;; in is lifted rather than left to hide what was just reached
      ;; for — the same courtesy a filter gets in `filter-view--sync-collapse'.
      (filter-view--set-state :collapsed
                              (remove group (filter-view--state :collapsed)))
      (setq filter-view--group group
            filter-view--group-query filter-view--query
            filter-view--query ""))
    (filter-view--render)
    (filter-view--goto-group group)
    (filter-view--item-start)))

;;; The detail pane

(defvar-local filter-view--detail-dir nil
  "Direction the detail pane was last split off in, `right' or `below'.
Chosen by `filter-view--detail-direction' when the pane opens; the
renderer consults it to know whether the pane's height is its own to
shrink.")

(defvar-local filter-view--detail-height nil
  "Height the detail pane has grown to while open, or nil when closed.
A floor for `filter-view--fit-detail', so the pane never shrinks under
a following pane's point.")

(defun filter-view--detail-buffer-name ()
  "Name of this view's detail buffer, derived from the view's own.
\"*maf-formulas*\" begets \" *maf-formulas-detail*\": a hidden buffer,
one per view, so two views' panes never fight over one buffer."
  (concat " *" (string-trim (buffer-name) "[* ]+" "[* ]+") "-detail*"))

(defun filter-view--detail-direction ()
  "Where to split the detail pane off when no window can be borrowed.
`right' when there is width to spare, else `below'. The menu's own
window is what gets split, so the test is on its width, not the
frame's."
  (if (>= (window-body-width) (* 2 (filter-view--detail-min-width)))
      'right
    'below))

(defun filter-view--split-p (win)
  "Non-nil when WIN was made for the detail pane rather than borrowed.
`display-buffer' records that in the window's `quit-restore' parameter:
a leading `window' means it created the window."
  (eq (car-safe (window-parameter win 'quit-restore)) 'window))

(defun filter-view--fit-detail (win)
  "Fit the detail pane WIN to the height its text needs.
Only for a pane split off below: there the height is room taken from
the list, so the pane asks for no more than it uses — a borrowed
window keeps whatever size its own buffer had. Capped at half the
frame so a long text cannot swallow the menu. Once open the pane only
ever grows: a following pane re-renders item by item, and shrinking
back on the short ones would leave the list jumping under the cursor
on every move."
  (when (and (eq filter-view--detail-dir 'below)
             (filter-view--split-p win))
    (let ((max-h (max 6 (/ (frame-height) 2))))
      (fit-window-to-buffer win max-h
                            (min max-h (or filter-view--detail-height 4)))
      (setq filter-view--detail-height (window-height win)))))

(defun filter-view--update-detail ()
  "Render the item at point into the detail buffer.
On a group header, the group's first item is previewed. The detail
lives in its own buffer, so showing it never shifts the list's own
layout."
  (let ((item (or (filter-view--item-at-point)
                  (save-excursion
                    (forward-line 1)
                    (while (and (not (eobp))
                                (not (filter-view--item-at-point)))
                      (forward-line 1))
                    (filter-view--item-at-point))))
        (dbuf (get-buffer (filter-view--detail-buffer-name)))
        (detail (filter-view--conf :detail)))
    (when (and dbuf detail)
      ;; The pane's real width when it is showing, else a stock fill.
      ;; `window-body-width' counts the columns line numbers occupy, so
      ;; subtract those or a fill overshoots by their width.
      (let ((width (let ((win (get-buffer-window dbuf)))
                     (if win
                         (- (window-body-width win)
                            (with-selected-window win
                              (ceiling (line-number-display-width 'columns))))
                       fill-column))))
        (with-current-buffer dbuf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (when item (insert (funcall detail item width)))
            (goto-char (point-min))))
        (when-let ((win (get-buffer-window dbuf)))
          (filter-view--fit-detail win))))))

(defun filter-view-refresh-detail (name)
  "Re-render view NAME's detail pane, if one is on screen.
For a caller that changed what the pane draws with rather than which
item it shows — a renderer swapped elsewhere, say; the pane otherwise
repaints only when point in the list reaches another item."
  (when-let ((buf (get-buffer name)))
    (with-current-buffer buf
      (when (and (derived-mode-p 'filter-view-mode)
                 (get-buffer-window (filter-view--detail-buffer-name)))
        (filter-view--update-detail)))))

(defun filter-view--close-detail ()
  "Put the detail pane's window back the way it was, when one is showing.
`quit-restore-window' undoes exactly what `display-buffer' did: the
window goes away if the pane made one, and the buffer it borrowed
comes back if it did not."
  (let ((win (get-buffer-window (filter-view--detail-buffer-name))))
    (setq filter-view--detail-height nil)
    (when (and win (not (eq win (selected-window))))
      (quit-restore-window win 'bury))))

(defun filter-view--open-detail ()
  "Display the detail pane and render the item at point into it."
  (let ((dbuf (get-buffer-create (filter-view--detail-buffer-name))))
    (with-current-buffer dbuf
      (unless (derived-mode-p 'special-mode) (special-mode))
      (setq buffer-read-only t))
    ;; Displayed before rendering, so prose fills to the pane's real
    ;; width. The consumer's actions may borrow a window; failing
    ;; everything, split whichever way leaves the detail the better
    ;; shape.
    (setq filter-view--detail-dir (filter-view--detail-direction))
    (display-buffer dbuf
                    `(,(or (filter-view--conf :detail-actions)
                           '(display-buffer-reuse-window
                             display-buffer-in-direction))
                      (direction . ,filter-view--detail-dir)
                      (inhibit-same-window . t)))
    (filter-view--update-detail)
    (setq filter-view--detail-line (line-beginning-position))))

(defun filter-view--detail-on-move ()
  "React to point's moves with the detail pane; on `post-command-hook'.
The pane reacts only to a line other than the one rendered, so the
commands that leave point where it was cost nothing. What it does
there is the follow flag's call. Following, it re-renders — or comes
back, when \\<filter-view-mode-map>\\[filter-view-show-detail] hid it for a peek at what its window held. Frozen
\(follow off), the pane is dismissed instead, the window handed back:
the details were for the item it was opened on, and point has moved
on."
  (unless (eq (line-beginning-position) filter-view--detail-line)
    (pcase (filter-view--pane-state)
      ('follow
       (if (get-buffer-window (filter-view--detail-buffer-name))
           (progn (setq filter-view--detail-line (line-beginning-position))
                  (filter-view--update-detail))
         (filter-view--open-detail)))
      ('frozen
       (filter-view--set-pane-state nil)
       (setq filter-view--detail-line nil)
       (filter-view--close-detail)))))

(defun filter-view-show-detail ()
  "Show the detail pane, or close a pane that is up — a visibility toggle.
Either way the follow flag (\\<filter-view-mode-map>\\[filter-view-toggle-detail]) keeps the say over what happens next.
With follow on, closing is a peek at what the window held, the
legend's gold untouched, and the pane returns on its own the moment
point reaches another item. With follow off, the pane shows the item
at point and moving off that line dismisses it again: details on
request, where follow makes them a running commentary. On a group
header it shows the group's first item."
  (interactive)
  (unless (filter-view--conf :detail)
    (user-error "This view has no detail pane"))
  (if (get-buffer-window (filter-view--detail-buffer-name))
      (filter-view--close-detail)
    (unless (filter-view--pane-state)
      (filter-view--set-pane-state 'frozen))
    (filter-view--open-detail))
  (filter-view--refresh-header))

(defun filter-view-visit-detail ()
  "Show the detail pane and go there.
\\<filter-view-mode-map>\\[filter-view-show-detail] with the pane's window
selected: for reading at length — scrolling, searching, copying —
where that key leaves point on the list. A pane already up is kept
rather than toggled away, and the follow flag is left as it stands.
\\`q' in the pane comes back."
  (interactive)
  (unless (filter-view--conf :detail)
    (user-error "This view has no detail pane"))
  (unless (get-buffer-window (filter-view--detail-buffer-name))
    (unless (filter-view--pane-state)
      (filter-view--set-pane-state 'frozen))
    (filter-view--open-detail)
    (filter-view--refresh-header))
  (select-window (get-buffer-window (filter-view--detail-buffer-name))))

(defun filter-view-toggle-detail ()
  "Open a detail pane that follows point, or close a following one.
Where \\<filter-view-mode-map>\\[filter-view-show-detail] holds one item, this re-renders for each item point
reaches — for reading down a group. Pressed while such a pane is up it
closes it; pressed while \\[filter-view-show-detail] holds one, it takes the pane over and
starts following. The choice holds for the session: the menu reopens
with the pane the way this left it."
  (interactive)
  (unless (filter-view--conf :detail)
    (user-error "This view has no detail pane"))
  (if (eq (filter-view--pane-state) 'follow)
      (progn (filter-view--set-pane-state nil)
             (setq filter-view--detail-line nil)
             (filter-view--close-detail))
    (filter-view--set-pane-state 'follow)
    (filter-view--open-detail))
  (filter-view--refresh-header))

(defun filter-view-keyboard-quit ()
  "Close the detail pane, then quit as \\[keyboard-quit] does.
On the menu's \\`C-g': the usual dismiss gesture shuts the pane
whichever way it was opened, so it takes neither a matching key nor
leaving the menu."
  (interactive)
  (setq filter-view--detail-line nil)
  (when (filter-view--conf :detail)
    (filter-view--set-pane-state nil))
  (filter-view--close-detail)
  (filter-view--refresh-header)
  (keyboard-quit))

;;; Selecting

(defun filter-view-select ()
  "Act on the line at point: select the item, or narrow to the group.
RET does the obvious thing for whatever the line holds — handing the
item to the consumer's :select, or narrowing the menu to the group
whose header it is (`filter-view-filter-group'). A selected item is
remembered in the recent group, when the view keeps one, and the menu
re-renders to say so if it is still on screen — a :select that quits
the menu is left quit."
  (interactive)
  (if (filter-view--group-at-point)
      (filter-view-filter-group)
    (let ((item (filter-view--item-at-point))
          (buf (current-buffer)))
      (unless item (user-error "Nothing on this line"))
      (funcall (filter-view--conf :select) item)
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (filter-view--record-recent item)
          (when-let ((win (and (filter-view--recents-p)
                               (get-buffer-window buf 0))))
            (with-selected-window win
              (let ((recent (filter-view--recent-line-p)))
                (filter-view--render)
                (filter-view--goto-item item recent)))))))))

(defun filter-view-refresh ()
  "Re-render from the consumer's items, keeping point's place when it stays."
  (interactive)
  (let ((item (filter-view--item-at-point))
        (recent (filter-view--recent-line-p))
        (group (filter-view--group-of-point)))
    (filter-view--render)
    (cond ((and item (filter-view--goto-item item recent)))
          (group (filter-view--goto-group group)))))

(defun filter-view-quit ()
  "Quit the menu, closing the detail pane too.
The menu's window is deleted if `filter-view-open' made one, or goes
back to the buffer it displaced if it borrowed one; the rest of the
frame is untouched either way."
  (interactive)
  (filter-view--close-detail)
  (quit-window))

;;; The mode

(defvar filter-view-mode-map (make-sparse-keymap)
  "Keymap for `filter-view-mode'.")

;; Bindings outside the defvar so reloading applies edits.
(define-key filter-view-mode-map (kbd "RET") #'filter-view-select)
(define-key filter-view-mode-map (kbd "/")   #'filter-view-filter)
(define-key filter-view-mode-map (kbd "c")   #'filter-view-clear-filter)
(define-key filter-view-mode-map (kbd "g")   #'filter-view-refresh)
(define-key filter-view-mode-map (kbd "q")   #'filter-view-quit)
;; ? shows the details and w goes to them — the pair dial's buffers
;; and the history browser answer to, so one habit serves them all.
(define-key filter-view-mode-map (kbd "?")   #'filter-view-show-detail)
(define-key filter-view-mode-map (kbd "w")   #'filter-view-visit-detail)
(define-key filter-view-mode-map (kbd "O")   #'filter-view-toggle-detail)
(define-key filter-view-mode-map (kbd "a")   #'filter-view-add-recent)
(define-key filter-view-mode-map (kbd "i")   #'filter-view-add-recent)
(define-key filter-view-mode-map (kbd "D")   #'filter-view-delete-recent)
(define-key filter-view-mode-map (kbd "C-g") #'filter-view-keyboard-quit)
;; Two levels of motion: n/p/j/k step item to item (headers included,
;; the lines between skipped), M-n/M-p step group to group.
(define-key filter-view-mode-map (kbd "n")   #'filter-view-next-item)
(define-key filter-view-mode-map (kbd "p")   #'filter-view-prev-item)
(define-key filter-view-mode-map (kbd "j")   #'filter-view-next-item)
(define-key filter-view-mode-map (kbd "k")   #'filter-view-prev-item)
(define-key filter-view-mode-map (kbd "M-n") #'filter-view-next-group)
(define-key filter-view-mode-map (kbd "M-p") #'filter-view-prev-group)
;; TAB folds, the outline reflex. The whole list, not the group under
;; point: TAB means the same thing wherever it is pressed, which is
;; what makes it the key for a view of the list rather than an edit to
;; one corner of it. S-TAB is the one group, for picking the wanted
;; one out of a folded list.
(define-key filter-view-mode-map (kbd "TAB")       #'filter-view-toggle-all-groups)
(define-key filter-view-mode-map (kbd "<backtab>") #'filter-view-toggle-group)

(define-derived-mode filter-view-mode special-mode "filter-view"
  "Major mode for a filterable, grouped list menu.
\\<filter-view-mode-map>\\[filter-view-select] selects the item at
point — or, on a group header, narrows the list to that group, whole,
and widens again when pressed there a second time.
\\[filter-view-next-item] and \\[filter-view-prev-item] step between
the rows and the headers alike; \\[filter-view-next-group] and
\\[filter-view-prev-group] step group to group.
\\[filter-view-toggle-all-groups] folds every group away to its
header and unfolds them all again; \\[filter-view-toggle-group] folds
or unfolds the one group at point. \\[filter-view-show-detail] shows
the item at point in the detail pane (again to close it),
\\[filter-view-visit-detail] shows it and goes there,
\\[filter-view-toggle-detail] toggles the pane following point,
\\[filter-view-add-recent] adds the item at point to the Recent group
without selecting it, \\[filter-view-delete-recent] drops the recent
entry at point, \\[filter-view-filter] filters as you type,
\\[filter-view-clear-filter] clears every narrowing,
\\[filter-view-refresh] re-reads the items, \\[filter-view-quit]
quits."
  (setq truncate-lines t)
  ;; The legend's band replaces `header-line's own look outright, not
  ;; layered under, so every view reads as one piece of chrome.
  (face-remap-set-base 'header-line 'filter-view-controls)
  (add-hook 'post-command-hook #'filter-view--detail-on-move nil t))

;;; Opening a view

(defun filter-view-setup (name &rest config)
  "Create or reset the view buffer NAME under CONFIG, returning it.
The buffer is (re)initialized and rendered but not displayed — the
piece of `filter-view-open' that a test, or a caller with its own
display plans, wants alone. CONFIG is the plist this file's
commentary describes."
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (filter-view-mode)
      (setq filter-view--config config)
      (when-let ((n (plist-get config :name)))
        (setq mode-name n))
      (filter-view--render))
    buf))

(defun filter-view-open (name &rest config)
  "Open the view buffer NAME under CONFIG, or go to it where it stands.
Already on screen, its window is selected and its state left as it
was — a command that only means \"go there\" must not reset the menu
under the user. Otherwise the buffer is built afresh by
`filter-view-setup' and displayed by the usual `display-buffer'
rules, the pane reopening if the session left it open."
  (if-let ((win (get-buffer-window name 0)))
      (progn
        (select-frame-set-input-focus (window-frame win))
        (select-window win))
    (pop-to-buffer (apply #'filter-view-setup name config))
    (when (filter-view--pane-state)
      (filter-view--open-detail))))

(provide 'filter-view)
