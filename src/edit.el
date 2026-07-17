;; -*- lexical-binding: t; -*-
;;
;; edit.el
;;
;; maf-edit: wdired-style in-place editing of the calc stack.
;;
;; `maf-edit' (SPC in maf-mode) turns the calc buffer into editable
;; plain text.
;; Each stack entry is tracked by an overlay; the text is the
;; interface. Newline gestures are the only structural operators:
;;
;;   newline at a balanced point      split into two entries
;;   newline inside open delimiters   continue the entry on a new line
;;   joining two entries' lines       merge them into one entry
;;
;; Deleting delimiters never restructures — an unbalanced entry just
;; fails to parse at commit. Level-number prefixes are machine-owned:
;; the cursor skips them, and a repair pass renumbers and re-stamps
;; them after every change; an entry whose text differs from what is
;; on the stack shows N* instead of N:. C-RET parses the buffer and commits it
;; back to the stack as one undoable operation; entries whose text is
;; untouched keep their value objects (display text can be lossy, so
;; they are never reparsed) and their selections. C-c C-k discards.
;;
;; The editing state is the minor mode `maf-edit-mode': turning it on
;; is entering, turning it off is leaving (with discard semantics —
;; `maf-edit-commit' parses first, then turns it off). Customize via
;; `maf-edit-mode-map' (extra bindings while editing) and the standard
;; hooks — `maf-edit-mode-on-hook' fires on enter, and
;; `maf-edit-mode-off-hook' on any exit, commit and discard alike.

(require 'calc)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'cursor-sensor)  ; cursor-intangible-mode
(require 'maf-lib)

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-read-expr "calc-aent")
(declare-function maf-mode "maf")
(declare-function maf-hl-mode "maf-hl")

(defvar-local maf-edit--dot nil
  "Overlay tracking the home (dot) line during maf-edit.")

(defvar-local maf-edit--saved nil
  "Plist of buffer state saved at maf-edit entry, restored at exit.")

(defvar-local maf-edit--errors nil
  "Error overlays from the last failed commit; cleared on any change.")

(defvar maf-edit--inhibit nil
  "Non-nil while maf-edit's own repair edits run, to skip the hooks.")

(defvar maf-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-<return>") #'maf-edit-commit)
    (define-key map (kbd "C-c C-k") #'maf-edit-discard)
    map)
  "Keymap active while `maf-edit-mode' is on.
Bind commands here to make them available only during editing.")

(defvar maf-edit--text-map (make-sparse-keymap)
  "Local map swapped in over `calc-mode-map' while editing.
Deliberately empty: with calc's command keys out of the way, every
key falls through to the global map and plain typing works.")

;;; Prefixes

(defconst maf-edit--prefix-width 4
  "Width of calc's level-number prefix (see `calc-renumber-stack').")

(defun maf-edit--prefix-string (n &optional dirty)
  "Canonical propertized prefix for level N, in calc's own format.
With DIRTY non-nil the separator is * instead of : — flagging an
entry whose text no longer matches what is on the stack (or a new
entry). Editing text back to its original clears the flag, since
dirtiness is text equality, not a touched bit."
  (propertize
   (let ((sep (if dirty "*" ":")))
     (if (> n 999)
         (format "%03d%s" (% n 1000) sep)
       (let ((num (number-to-string n)))
         (concat num sep (make-string (- 3 (length num)) ?\s)))))
   'maf-edit-prefix t
   'cursor-intangible t
   ;; Stickiness so the cursor can never display on prefix text: the
   ;; position just after the run is legal (rear-nonsticky — C-b stops
   ;; on the first entry char) and BOL is not (front-sticky — motion
   ;; skips clean across to the previous line).
   'rear-nonsticky t
   'front-sticky '(cursor-intangible)
   'face 'shadow))

(defconst maf-edit--pad-string
  (propertize (make-string 4 ?\s)
              'maf-edit-prefix t
              'cursor-intangible t
              'rear-nonsticky t
              'front-sticky '(cursor-intangible)
              'face 'shadow)
  "Machine-owned pad stamped on continuation lines.
The continuation counterpart of the level prefix: same width, same
properties, so column 4 is the first cursor column on every stack
line and motion skips across the pad to the previous line.")

(defun maf-edit--strip-prefix (start end)
  "Delete prefix-propertied characters between START and END."
  (save-excursion
    (goto-char start)
    (let ((lim (copy-marker end)))
      (while (< (point) lim)
        (if (get-text-property (point) 'maf-edit-prefix)
            (delete-char 1)
          (forward-char)))
      (set-marker lim nil))))

(defun maf-edit--leading-prefix-run (bol)
  "Length of the machine-owned run at the start of BOL's line."
  (save-excursion
    (goto-char bol)
    (let ((eol (line-end-position)) (n 0))
      (while (and (< (point) eol)
                  (get-text-property (point) 'maf-edit-prefix))
        (setq n (1+ n))
        (forward-char))
      n)))

;;; Entry overlays

(defun maf-edit--make-entry (start end &optional val sel text)
  "Create an entry overlay from START to END carrying VAL, SEL, TEXT.
Rear-advancing, so text typed at an entry's end still belongs to it."
  (let ((o (make-overlay start end nil nil t)))
    (overlay-put o 'maf-edit-entry t)
    (overlay-put o 'maf-edit-val val)
    (overlay-put o 'maf-edit-sel sel)
    (overlay-put o 'maf-edit-text text)
    o))

(defun maf-edit--overlays ()
  "Entry overlays in buffer order."
  (sort (seq-filter (lambda (o) (overlay-get o 'maf-edit-entry))
                    (overlays-in (point-min) (point-max)))
        (lambda (a b) (< (overlay-start a) (overlay-start b)))))

(defun maf-edit--entry-text (o)
  "Entry O's text, prefix-stripped and whitespace-normalized.
Lines are trimmed and joined with single spaces — parsing ignores
whitespace, so this makes the text independent of prefix renumbering
and indentation shifts. Used both for comparison against the entry's
original text and as parser input."
  (let ((raw (buffer-substring (overlay-start o) (overlay-end o)))
        (out '()))
    (dotimes (i (length raw))
      (unless (get-text-property i 'maf-edit-prefix raw)
        (push (aref raw i) out)))
    (string-join
     (seq-remove #'string-empty-p
                 (mapcar #'string-trim
                         (split-string (concat (nreverse out)) "\n")))
     " ")))

;;; Delimiter depth

(defun maf-edit--depth (start pos)
  "Delimiter depth just before POS, scanning from START.
Any closer matches any opener, so mixed interval delimiters like
(1 .. 2] count correctly. Prefix characters are skipped. Never goes
negative."
  (let ((d 0))
    (save-excursion
      (goto-char start)
      (while (< (point) pos)
        (unless (get-text-property (point) 'maf-edit-prefix)
          (pcase (char-after)
            ((or ?\( ?\[ ?\{) (setq d (1+ d)))
            ((or ?\) ?\] ?\}) (setq d (max 0 (1- d))))))
        (forward-char)))
    d))

(defun maf-edit--string-net-depth (text)
  "Net delimiter depth of TEXT (for commit diagnostics)."
  (let ((d 0))
    (dotimes (i (length text))
      (pcase (aref text i)
        ((or ?\( ?\[ ?\{) (setq d (1+ d)))
        ((or ?\) ?\] ?\}) (setq d (1- d)))))
    d))

;;; Structural newline classification

(defun maf-edit--classify-newlines (beg end)
  "Apply the newline rule to newlines just inserted in BEG..END.
A newline inside an entry at balanced depth splits it in two; inside
open delimiters it is a continuation and the entry keeps spanning it.
Newlines outside any entry are pending lines, adopted by the repair
pass once they carry text."
  (save-excursion
    (goto-char beg)
    (while (search-forward "\n" end t)
      (let* ((pos (1- (point)))
             (o (seq-find (lambda (ov) (overlay-get ov 'maf-edit-entry))
                          (overlays-at pos))))
        (when (and o (zerop (maf-edit--depth (overlay-start o) pos)))
          (let ((tail-start (1+ pos))
                (tail-end (overlay-end o)))
            (move-overlay o (overlay-start o) pos)
            (when (< tail-start tail-end)
              (maf-edit--make-entry tail-start tail-end))))))))

;;; Repair pass

(defconst maf-edit--dot-string
  (propertize "    ." 'maf-edit-dot t)
  "Canonical home-line text, propertized so healing can identify it.")

(defun maf-edit--heal-dot ()
  "Keep the home line — \"    .\" on its own final line — intact.
Foreign text on the dot line (typed there — the natural gesture on an
empty stack) is salvaged: only the dot's own characters are removed
before the line is re-walled to the buffer end, so the typed text
survives as an entry line. Text below the dot likewise ends up above
it."
  (let* ((o maf-edit--dot)
         (live (and o (overlay-buffer o)
                    (< (overlay-start o) (overlay-end o)))))
    (unless (and live
                 (equal-including-properties
                  (buffer-substring (overlay-start o) (overlay-end o))
                  maf-edit--dot-string)
                 (save-excursion (goto-char (overlay-start o)) (bolp))
                 (= (overlay-end o) (1- (point-max)))
                 (eq (char-after (overlay-end o)) ?\n))
      (save-excursion
        ;; Salvage: drop only the chars that belong to the dot itself.
        (when live
          (goto-char (overlay-start o))
          (let ((lim (copy-marker (overlay-end o))))
            (while (< (point) lim)
              (if (get-text-property (point) 'maf-edit-dot)
                  (delete-char 1)
                (forward-char)))
            (set-marker lim nil))
          ;; If nothing foreign was on the line, remove the leftover
          ;; blank line too.
          (when (and (bolp) (eolp) (< (point) (point-max)))
            (delete-char 1)))
        (when o (delete-overlay o))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert maf-edit--dot-string "\n")
        (setq maf-edit--dot (make-overlay (- (point) 6) (1- (point))))))))

(defun maf-edit--drop-empty ()
  "Remove overlays whose text was deleted entirely."
  (dolist (o (maf-edit--overlays))
    (when (>= (overlay-start o) (overlay-end o))
      (delete-overlay o))))

(defun maf-edit--join-damaged-prefixes ()
  "Treat a partially deleted prefix or pad as a join gesture.
Deleting into a line's machine-owned leading run (DEL at its first
text character, say) reads as joining lines: finish the job by
removing what is left of the run and the newline before it. On an
entry's first line that merges it into the previous entry; on a
continuation line it pulls the line up into the one above. A run that
is entirely gone is just re-stamped."
  (let (joins)
    (save-excursion
      (goto-char (point-min))
      (while (< (point) (overlay-start maf-edit--dot))
        (let ((run (maf-edit--leading-prefix-run (point))))
          (when (and (> run 0) (< run maf-edit--prefix-width)
                     (> (point) (point-min)))
            (push (cons (point) run) joins)))
        (forward-line 1)))
    ;; joins is bottom-up, so each deletion leaves the rest valid
    (dolist (j joins)
      (delete-region (car j) (+ (car j) (cdr j)))
      (delete-region (1- (car j)) (car j)))))

(defun maf-edit--strip-stray-props ()
  "Delete machine-owned characters that are not a line's leading run.
Line joins and yanks can strand prefix or pad characters mid-line;
they are display furniture, not entry text."
  (save-excursion
    (goto-char (point-min))
    (while (< (point) (overlay-start maf-edit--dot))
      (goto-char (+ (point) (maf-edit--leading-prefix-run (point))))
      (let ((eol (copy-marker (line-end-position))))
        (while (< (point) eol)
          (if (get-text-property (point) 'maf-edit-prefix)
              (delete-char 1)
            (forward-char)))
        (set-marker eol nil))
      (forward-line 1))))

(defun maf-edit--merge-shared-lines ()
  "Merge entries that ended up sharing a line (the join gesture)."
  (let ((os (maf-edit--overlays)))
    (while (cdr os)
      (let ((a (car os)) (b (cadr os)))
        (if (= (line-number-at-pos (overlay-end a))
               (line-number-at-pos (overlay-start b)))
            (progn
              (maf-edit--strip-prefix (overlay-start b) (overlay-end b))
              (move-overlay a (overlay-start a) (overlay-end b))
              (delete-overlay b)
              (setq os (cons a (cddr os))))
          (setq os (cdr os)))))))

(defun maf-edit--adopt-new-lines ()
  "Give uncovered non-blank lines fresh entry overlays.
Consecutive uncovered lines group into one entry while their running
delimiter depth stays open — the same rule newline insertion follows —
so a yanked multi-line vector arrives as a single entry."
  (save-excursion
    (goto-char (point-min))
    (let ((dot (overlay-start maf-edit--dot))
          (group nil))  ; (start . end) of the group under construction
      (cl-flet ((close-group ()
                  (when group
                    (maf-edit--make-entry (car group) (cdr group))
                    (setq group nil))))
        (while (< (point) dot)
          (let* ((bol (point))
                 (eol (line-end-position))
                 (covered (seq-some
                           (lambda (ov) (overlay-get ov 'maf-edit-entry))
                           (overlays-in bol (min (1+ eol) (point-max)))))
                 (blank (string-blank-p
                         (buffer-substring-no-properties bol eol))))
            (cond
             (covered (close-group))
             ((and blank (not group)))     ; pending blank line: leave it
             (t
              (unless group (setq group (cons bol eol)))
              (setcdr group eol)
              ;; group closes when depth is balanced at this line's end
              (when (zerop (maf-edit--depth (car group) eol))
                (close-group)))))
          (forward-line 1))
        (close-group)))))

(defun maf-edit--stamp-line (want)
  "Ensure the line at point starts with the propertized WANT string.
No-op when it already does; otherwise strips the line's prefix chars,
swallows up to `maf-edit--prefix-width' leading plain spaces (so
re-stamping existing indentation doesn't shift the content), and
inserts WANT at the line beginning."
  (let* ((bol (line-beginning-position))
         (eol (line-end-position))
         (have (buffer-substring bol (min (+ bol maf-edit--prefix-width)
                                          eol))))
    (unless (equal-including-properties have want)
      (maf-edit--strip-prefix bol (line-end-position))
      (save-excursion
        (goto-char bol)
        (skip-chars-forward " " (min (line-end-position)
                                     (+ bol maf-edit--prefix-width)))
        (delete-region bol (point))
        (insert want)))))

(defun maf-edit--renumber ()
  "Stamp the level prefix and continuation pads on every entry.
The first line gets the canonical numbered prefix; each further line
gets the 4-space pad, making column 4 the first cursor column on
every stack line."
  (let ((n (length (maf-edit--overlays))))
    (dolist (o (maf-edit--overlays))
      (let ((start (overlay-start o))
            (bol (save-excursion (goto-char (overlay-start o))
                                 (line-beginning-position))))
        (unless (= start bol) (move-overlay o bol (overlay-end o)))
        (save-excursion
          (goto-char bol)
          (maf-edit--stamp-line
           (maf-edit--prefix-string
            n
            ;; Dirty when the text no longer matches the stack entry
            ;; (a new entry has nothing to match).
            (not (and (overlay-get o 'maf-edit-val)
                      (equal (maf-edit--entry-text o)
                             (overlay-get o 'maf-edit-text))))))
          (while (and (zerop (forward-line 1))
                      (< (point) (overlay-end o)))
            (maf-edit--stamp-line maf-edit--pad-string)))
        (overlay-put o 'maf-edit-stamped t))
      (setq n (1- n)))))

(defun maf-edit--repair ()
  "Restore all structural invariants after a change."
  (maf-edit--heal-dot)
  (maf-edit--drop-empty)
  (maf-edit--join-damaged-prefixes)
  (maf-edit--merge-shared-lines)
  (maf-edit--strip-stray-props)
  (maf-edit--adopt-new-lines)
  (maf-edit--renumber))

(defun maf-edit--after-change (beg end _len)
  (unless maf-edit--inhibit
    (let ((maf-edit--inhibit t)
          (inhibit-modification-hooks t))
      (maf-edit--clear-errors)
      (when (> end beg) (maf-edit--classify-newlines beg end))
      (maf-edit--repair))))

;;; Errors

(defun maf-edit--clear-errors ()
  (mapc #'delete-overlay maf-edit--errors)
  (setq maf-edit--errors nil))

(defun maf-edit--flag-error (o msg)
  "Mark entry O's region with MSG as an unparsable entry."
  (let ((e (make-overlay (overlay-start o) (overlay-end o))))
    (overlay-put e 'face '(:underline (:style wave :color "red")))
    (overlay-put e 'help-echo msg)
    (push e maf-edit--errors)))

;;; The mode and its commands

(define-minor-mode maf-edit-mode
  "Minor mode for in-place editing of the calc stack.
The mode variable is the editing state: turning it on makes the stack
plain editable text (entries tracked by overlays, prefixes machine-
owned and renumbered live); turning it off restores the calc buffer
with the stack untouched — discard semantics. To keep the edits, use
\\<maf-edit-mode-map>\\[maf-edit-commit] (`maf-edit-commit'), which
parses the buffer, then turns the mode off, then replaces the stack.

`maf-edit-mode-on-hook' runs on enter; `maf-edit-mode-off-hook' runs
on every exit, commit and discard alike. Extra bindings for the
editing state go on `maf-edit-mode-map'."
  :lighter " MafEdit"
  :keymap maf-edit-mode-map
  (if maf-edit-mode
      (condition-case err
          (maf-edit--enter)
        (error (setq maf-edit-mode nil)
               (signal (car err) (cdr err))))
    (maf-edit--exit)))

(defun maf-edit--enter ()
  "Make the calc buffer editable: the body of turning `maf-edit-mode' on."
  (unless (derived-mode-p 'calc-mode)
    (user-error "maf-edit only works in a calc buffer"))
  (unless calc-line-numbering
    (user-error "maf-edit requires calc-line-numbering"))
  (let ((snapshot (maf--point-snapshot)))
      ;; Render without width-based line breaking: any multi-line entry
      ;; left is structural (matrix/vector row layout), which the
      ;; newline rule handles; long formulas wrap visually instead.
      (let ((calc-line-breaking nil)) (calc-refresh))
      (let ((inhibit-read-only t)
            (size (calc-stack-size)))
        ;; Adopt each entry: overlay + its value, selection, and the
        ;; text properties that mark its prefix machine-owned.
        (dotimes (i size)
          (let* ((m (- size i))
                 (start (save-excursion (calc-cursor-stack-index m) (point)))
                 (next (save-excursion (calc-cursor-stack-index (1- m)) (point)))
                 (entry (calc-top m 'entry))
                 (o (maf-edit--make-entry start (1- next)
                                          (car entry) (nth 2 entry))))
            (overlay-put o 'maf-edit-stamped t)
            (add-text-properties
             start (+ start maf-edit--prefix-width)
             '(maf-edit-prefix t cursor-intangible t
               rear-nonsticky t front-sticky (cursor-intangible)
               face shadow))))
        (save-excursion
          (calc-cursor-stack-index 0)
          (setq maf-edit--dot (make-overlay (point) (line-end-position)))
          (add-text-properties (point) (line-end-position)
                               '(maf-edit-dot t)))
        ;; Original text recorded after propertizing (so extraction can
        ;; tell prefix from content) but before the stamp pass, which
        ;; needs it to know every entry starts clean.
        (dolist (o (maf-edit--overlays))
          (overlay-put o 'maf-edit-text (maf-edit--entry-text o)))
        ;; Stamp continuation pads (idempotent for the prefixes just
        ;; propertized above), so column 4 is the first cursor column
        ;; on every line from the start.
        (maf-edit--renumber))
      (setq maf-edit--saved
            (list :undo buffer-undo-list
                  :map (current-local-map)
                  :maf-mode (and (boundp 'maf-mode) maf-mode)
                  :hl (and (boundp 'maf-hl-mode) maf-hl-mode)
                  :visual visual-line-mode
                  :electric electric-indent-mode))
      ;; RET must insert a bare newline; electric indentation would
      ;; salt new lines with stray leading whitespace.
      (electric-indent-local-mode -1)
      ;; maf-mode's minor-mode map would shadow plain typing; the local
      ;; map swap alone can't disable it.
      (when (plist-get maf-edit--saved :maf-mode) (maf-mode -1))
      ;; The sub-formula highlighter resolves point against calc-stack,
      ;; which the edited text no longer reflects.
      (when (plist-get maf-edit--saved :hl) (maf-hl-mode -1))
      (use-local-map maf-edit--text-map)
      (visual-line-mode 1)
      (cursor-intangible-mode 1)
      (setq buffer-read-only nil
            buffer-undo-list nil)
      (add-hook 'after-change-functions #'maf-edit--after-change nil t)
      (maf--point-restore snapshot)
      (message (substitute-command-keys
                "maf-edit: editing stack — \\<maf-edit-mode-map>\\[maf-edit-commit] commits, \\[maf-edit-discard] discards"))))

(defun maf-edit--exit ()
  "Restore the calc buffer: the body of turning `maf-edit-mode' off.
Drops all editing state and re-renders from the (untouched) stack —
discard semantics; `maf-edit-commit' parses before getting here and
pushes after."
  (let ((snapshot (maf--point-snapshot)))
    (remove-hook 'after-change-functions #'maf-edit--after-change t)
    (maf-edit--clear-errors)
    (mapc #'delete-overlay (maf-edit--overlays))
    (when maf-edit--dot
      (delete-overlay maf-edit--dot)
      (setq maf-edit--dot nil))
    (use-local-map (plist-get maf-edit--saved :map))
    (unless (plist-get maf-edit--saved :visual) (visual-line-mode -1))
    (cursor-intangible-mode -1)
    (when (plist-get maf-edit--saved :maf-mode) (maf-mode 1))
    ;; Unconditional: re-enabling maf-mode drags maf-hl-mode on with
    ;; it, so a manually-off highlighter must be re-asserted off.
    (maf-hl-mode (if (plist-get maf-edit--saved :hl) 1 -1))
    (electric-indent-local-mode (if (plist-get maf-edit--saved :electric) 1 -1))
    (setq buffer-undo-list (plist-get maf-edit--saved :undo)
          buffer-read-only t
          maf-edit--saved nil)
    (calc-refresh)
    (maf--point-restore snapshot)))

(defun maf-edit ()
  "Toggle in-place editing of the calc stack.
Off: enter `maf-edit-mode' — the stack becomes plain editable text.
On: commit — parse the buffer back to the stack (`maf-edit-commit')."
  (interactive)
  (if maf-edit-mode
      (maf-edit-commit)
    (maf-edit-mode 1)))

(defun maf-edit-commit ()
  "Parse the edited buffer and commit it to the stack, leaving maf-edit.
Entries whose text is untouched keep their value objects and
selections; changed or new text is parsed in the current input modes.
If any entry fails to parse the commit is blocked: the offenders are
underlined, point goes to the first, and editing continues. The whole
commit is one undo group."
  (interactive)
  (unless maf-edit-mode (user-error "maf-edit is not active"))
  (let ((maf-edit--inhibit t)
        (inhibit-modification-hooks t))
    (maf-edit--clear-errors)
    (maf-edit--repair))
  (let (vals sels errors)
    (dolist (o (maf-edit--overlays))
      (let ((text (maf-edit--entry-text o)))
        (cond
         ((string-blank-p text))        ; emptied entry: deleted
         ((and (overlay-get o 'maf-edit-val)
               (equal text (overlay-get o 'maf-edit-text)))
          (push (overlay-get o 'maf-edit-val) vals)
          (push (overlay-get o 'maf-edit-sel) sels))
         (t
          (let ((v (math-read-expr text)))
            (if (eq (car-safe v) 'error)
                (push (cons o (if (zerop (maf-edit--string-net-depth text))
                                  (nth 2 v)
                                (concat (nth 2 v)
                                        " (unbalanced delimiters)")))
                      errors)
              (push (math-normalize v) vals)
              (push nil sels)))))))
    (if errors
        (let ((errors (nreverse errors)))
          (dolist (e errors) (maf-edit--flag-error (car e) (cdr e)))
          (goto-char (overlay-start (caar errors)))
          (user-error "maf-edit: cannot commit — %s" (cdar errors)))
      ;; Buffer top-to-bottom is deepest-first, the order
      ;; calc-pop-push-record-list pushes in.
      (setq vals (nreverse vals)
            sels (nreverse sels))
      (let ((snapshot (maf--point-snapshot)))
        ;; Turning the mode off restores the buffer and re-renders from
        ;; the unchanged stack — required before the pop-push, which
        ;; edits the buffer by entry heights the edited text no longer
        ;; matches.
        (maf-edit-mode -1)
        (calc-wrapper
         (calc-pop-push-record-list (calc-stack-size) "edit" vals 1 sels))
        (maf--point-restore snapshot)
        (message "maf-edit: committed %d entr%s"
                 (length vals) (if (= 1 (length vals)) "y" "ies"))))))

(defun maf-edit-discard ()
  "Leave maf-edit, discarding every edit; the stack is untouched."
  (interactive)
  (unless maf-edit-mode (user-error "maf-edit is not active"))
  (maf-edit-mode -1)
  (message "maf-edit: discarded"))

(provide 'maf-edit)
