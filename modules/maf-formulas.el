;; -*- lexical-binding: t; -*-
;;
;; modules/maf-formulas.el
;;
;; Saved-formula library. `maf-formulas' opens a two-pane menu: a list
;; of formulas grouped by category, each shown beside its form, and a
;; detail pane that follows point to show the formula in Big display, a
;; description, and what each variable means. RET pushes the formula at
;; point onto the calc stack.
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

(defun maf-formulas--render ()
  "Render the categorized list: each formula beside its one-line form.
Groups are separated by a blank line."
  (let* ((inhibit-read-only t) (first t)
         (groups (maf-formulas--groups))
         (fs (apply #'append (mapcar #'cdr groups))))
    (erase-buffer)
    (setq header-line-format
          (if (string-empty-p maf-formulas--query)
              "maf-formulas — RET inserts · / filters · q quits"
            (format "maf-formulas — filter: %s  (q clears)" maf-formulas--query)))
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
    (maf-formulas--update-detail)))

;;; The detail pane

(defun maf-formulas--detail-string (f)
  "Detail text for F: title, Big rendering, description, variable meanings."
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
     (when doc (concat "\n  " (propertize doc 'face 'maf-formulas-title) "\n"))
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

(defun maf-formulas--update-detail ()
  "Render the formula at point into the detail buffer; on `post-command-hook'.
The detail lives in its own pane, so navigating the list never shifts
the list's own layout."
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
      (with-current-buffer dbuf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (when f (insert (maf-formulas--detail-string f)))
          (goto-char (point-min)))))))

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
  (let ((dwin (get-buffer-window maf-formulas--detail-buffer)))
    (when (and dwin (not (eq dwin (selected-window))))
      (delete-window dwin)))
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
  "Major mode for the saved-formula list (the master pane).
Formulas are grouped by category, the ones inserted this session
repeated in a \"Recent\" group at the top, each shown beside its form;
the detail pane follows point. \\<maf-formulas-mode-map>\\[maf-formulas-insert]
pushes the formula at point onto the stack, \\[maf-formulas-next-item] and \\[maf-formulas-prev-item] step
between formulas, \\[maf-formulas-next-group] between groups, \\[maf-formulas-filter]
filters as you type, \\[maf-formulas-clear-filter] clears the filter, \\[maf-formulas-quit-or-clear-filter] clears the
filter when narrowed and quits otherwise."
  (setq truncate-lines t)
  (add-hook 'post-command-hook #'maf-formulas--update-detail nil t))

;;;###autoload
(defun maf-formulas ()
  "Open the saved-formula menu: a list pane with a detail pane below."
  (interactive)
  (let ((buf (get-buffer-create "*maf-formulas*"))
        (dbuf (get-buffer-create maf-formulas--detail-buffer)))
    (with-current-buffer dbuf
      (unless (derived-mode-p 'special-mode) (special-mode))
      (setq buffer-read-only t))
    (with-current-buffer buf
      (maf-formulas-mode)
      (maf-formulas--render))
    ;; Ordinary `pop-to-buffer' display: Emacs picks the window by the
    ;; usual rules, so `display-buffer-alist' can route the menu, and
    ;; `maf-formulas-quit' undoes exactly what was done. Only the menu's
    ;; own window is split, for the detail pane.
    (pop-to-buffer buf)
    ;; A float `window-height' is a fraction of the frame, which starves
    ;; the list when the menu got half a frame to begin with: size the
    ;; detail against the menu's own window, and leave the list usable.
    (let* ((avail (window-body-height))
           (h (max 4 (min (round (* 0.4 avail)) (- avail 6)))))
      (display-buffer dbuf `((display-buffer-below-selected)
                             (window-height . ,h)
                             (inhibit-same-window . t))))
    (maf-formulas--update-detail)))

;;; The module

;;;###autoload
(define-minor-mode maf-use-formulas-mode
  "Global minor mode making the saved formulas available.
Enabled, every formula is registered as a calc `var-eq-<name>' variable
so calc's own recall and rewrite see them (`maf-formulas-user',
populated from `maf-formulas-file', is the single source), and the menu
gets its key.

The key is `s o', beside calc's own store and recall on the same prefix
\(s s, s r): a formula is registered as a calc variable, so the menu
belongs where saved things already live. It is unbound in calc itself,
so nothing is shadowed and there is nothing to cede back.

The `maf-formulas' menu is written to work whenever this file is
loaded, so it stays reachable by name with the mode off; only the key
and the variable registration follow the mode. See `maf-modules'."
  :global t
  :group 'maf
  (if maf-use-formulas-mode
      (progn
        (maf-formulas--register-vars)
        (define-key maf-mode-map (kbd "s o") #'maf-formulas))
    (maf-formulas--unregister-vars)
    (define-key maf-mode-map (kbd "s o") nil)))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-formulas #'maf-use-formulas-mode
                       "Menu of saved formulas by category; RET inserts onto the stack."))

(provide 'maf-formulas)
