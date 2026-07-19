;; -*- lexical-binding: t; -*-
;;
;; edit.el
;;
;; maf-edit: wdired-style in-place editing of the calc stack.
;;
;; `maf-edit' (RET in maf-mode) turns the calc buffer into editable
;; plain text; the same key commits, so RET toggles edit/commit.
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
;; on the stack shows N* instead of N:, and a new entry not on the
;; stack yet shows N+. RET parses the buffer and commits it
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
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function maf-mode "maf")
(declare-function maf-hl-mode "maf-hl")

(defvar-local maf-edit--dot nil
  "Overlay tracking the home (dot) line during maf-edit.")

(defvar-local maf-edit--saved nil
  "Plist of buffer state saved at maf-edit entry, restored at exit.")

(defvar-local maf-edit--errors nil
  "Error overlays from the last failed commit; cleared on any change.")

(defvar-local maf-edit--pending-repair nil
  "Non-nil when a repair was deferred while undo replayed changes.")

(defvar-local maf-edit--return nil
  "Point snapshot to restore when this edit session ends, or nil.
Set by `maf-edit-add-entry' (the quick-add gesture) before entering;
commit and discard both consult it, returning point to where it was
before the edit began instead of keeping its in-edit position.")

(defvar maf-edit--inhibit nil
  "Non-nil while maf-edit's own repair edits run, to skip the hooks.")

(defvar maf-edit-mode-map
  (let ((map (make-sparse-keymap)))
    ;; RET confirms; the newline gesture (split/continue) moves to
    ;; S-RET, indenting past the machine-owned prefix area.
    (define-key map (kbd "RET") #'maf-edit-commit)
    (define-key map (kbd "S-<return>") #'maf-edit-newline)
    (define-key map (kbd "C-c C-k") #'maf-edit-discard)
    ;; Line-start motion treats the machine-owned prefix/pad as column
    ;; zero. Direct keys beat visual-line-mode's remaps; the remaps
    ;; catch custom bindings of the same commands.
    (define-key map (kbd "C-a") #'maf-edit-move-beginning-of-line)
    (define-key map (kbd "M-m") #'maf-edit-back-to-indentation)
    (define-key map [remap move-beginning-of-line]
                #'maf-edit-move-beginning-of-line)
    (define-key map [remap beginning-of-visual-line]
                #'maf-edit-move-beginning-of-line)
    (define-key map [remap back-to-indentation]
                #'maf-edit-back-to-indentation)
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

(defun maf-edit--prefix-string (n &optional state)
  "Canonical propertized prefix for level N, in calc's own format.
STATE picks the separator: nil for an entry matching the stack (:),
`dirty' for one whose text no longer matches (*), `new' for one not
on the stack at all (+). Editing text back to its original clears
the dirty flag, since dirtiness is text equality, not a touched bit."
  (propertize
   (let ((sep (pcase state ('dirty "*") ('new "+") (_ ":"))))
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

(defun maf-edit-move-beginning-of-line (arg)
  "Move to the first character after the line's prefix or pad.
The machine-owned run is column zero as far as the cursor is
concerned; plain `move-beginning-of-line' (or its visual-line remap)
targets the real column 0, an intangible position, and gets bounced
to the previous line. ARG behaves as in `move-beginning-of-line'."
  (interactive "^p")
  (unless (or (null arg) (= arg 1))
    (forward-line (1- arg)))
  (let ((bol (line-beginning-position)))
    (goto-char (+ bol (maf-edit--leading-prefix-run bol)))))

(defun maf-edit-back-to-indentation ()
  "Move to the line's first non-whitespace character after the prefix."
  (interactive "^")
  (maf-edit-move-beginning-of-line 1)
  (skip-chars-forward " \t" (line-end-position)))

(defun maf-edit-newline ()
  "Newline gesture (split or continue), landing on the first content column.
Plain `newline' leaves point at the real column 0, inside the
machine-owned prefix area. The repair pass stamps split tails and
continuation lines on its own; a fresh blank line is not yet an
entry, so it becomes one here — its numbered prefix stamps
immediately and the levels above shift up, exactly as they will once
it holds text. Point then lands after the line's prefix run."
  (interactive)
  (newline)
  (let ((bol (line-beginning-position)))
    (when (< bol (overlay-start maf-edit--dot))
      (when (zerop (maf-edit--leading-prefix-run bol))
        (let ((maf-edit--inhibit t)
              (inhibit-modification-hooks t))
          ;; A temporary machine-owned run keeps the fresh zero-length
          ;; entry out of `maf-edit--drop-empty's reach; the repair
          ;; then renumbers it into a properly stamped line (or merges
          ;; it up, when the line continues an open entry).
          (save-excursion (goto-char bol) (insert maf-edit--pad-string))
          (maf-edit--make-entry bol (+ bol maf-edit--prefix-width))
          (maf-edit--repair)))
      (goto-char (+ bol (maf-edit--leading-prefix-run bol))))))

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
                 ;; Content + our own marker property; foreign props
                 ;; (fontified etc.) must not fail the check, or every
                 ;; repair re-walls the dot and floods the undo history.
                 (string= (buffer-substring-no-properties
                           (overlay-start o) (overlay-end o))
                          "    .")
                 (get-text-property (overlay-start o) 'maf-edit-dot)
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
         (have (buffer-substring-no-properties
                bol (min (+ bol maf-edit--prefix-width) eol))))
    ;; Content + our own marker property; foreign props (fontified
    ;; etc.) must not fail the check, or every repair re-stamps every
    ;; line and floods the undo history.
    (unless (and (string= have (substring-no-properties want))
                 (get-text-property bol 'maf-edit-prefix))
      ;; Insert the new run before deleting the old one. The reverse
      ;; order relocates every marker sitting on the first content
      ;; column down to bol — point-preserving wrappers around an edit
      ;; (kill-region's extraction, save-excursion in a command) then
      ;; restore point into the front-sticky run, and redisplay bounces
      ;; it to the previous line. Insert-then-delete keeps those
      ;; markers on the content.
      (save-excursion
        (goto-char bol)
        (insert want)
        (maf-edit--strip-prefix (point) (line-end-position))
        (skip-chars-forward " " (min (line-end-position)
                                     (+ (point) maf-edit--prefix-width)))
        (delete-region (+ bol (length want)) (point))))))

(defun maf-edit--snap-point-out-of-run ()
  "Move point to the first content column when it sits in the prefix run.
Point exactly on a line's first content column collapses to BOL when
the repair re-stamps the run under it — `save-excursion' markers do
not advance past an insertion at their position — and redisplay would
bounce a point inside the front-sticky run to the previous line.
Called after every repair, outside any excursion, so the snap holds."
  (let* ((bol (line-beginning-position))
         (run (maf-edit--leading-prefix-run bol)))
    (when (< (- (point) bol) run)
      (goto-char (+ bol run)))))

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
            ;; New when not on the stack at all; dirty when the text
            ;; no longer matches the stack entry.
            (cond ((not (overlay-get o 'maf-edit-val)) 'new)
                  ((not (equal (maf-edit--entry-text o)
                               (overlay-get o 'maf-edit-text)))
                   'dirty))))
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
    (if undo-in-progress
        ;; primitive-undo replays a change group one record at a time,
        ;; firing this hook on every half-restored state. Repairing
        ;; those misreads them as gestures (a mid-restore prefix looks
        ;; like a join) and records the "fixes" into the history being
        ;; replayed. Defer: one repair after the command, when the
        ;; buffer is a complete earlier canonical state again.
        (setq maf-edit--pending-repair t)
      (let ((maf-edit--inhibit t)
            (inhibit-modification-hooks t))
        (maf-edit--clear-errors)
        (when (> end beg) (maf-edit--classify-newlines beg end))
        (maf-edit--repair)
        (maf-edit--snap-point-out-of-run)))))

(defun maf-edit--derive-splits ()
  "Split entries at balanced newlines, re-deriving structure from text.
Live editing decides split vs continuation at the moment a newline is
inserted; text restored wholesale by undo skipped those moments. The
rule is a pure function of the text — a newline inside open delimiters
continues, at balanced depth it splits — and every canonical state
already satisfies it, so the derivation is exact for undone states."
  (let ((os (maf-edit--overlays)))
    (while os
      (let* ((o (car os))
             (nl (save-excursion
                   (goto-char (overlay-start o))
                   (catch 'found
                     (while (search-forward "\n" (overlay-end o) t)
                       (when (zerop (maf-edit--depth (overlay-start o)
                                                     (1- (point))))
                         (throw 'found (1- (point)))))
                     nil))))
        (if (not nl)
            (setq os (cdr os))
          (let ((end (overlay-end o))
                tail)
            (move-overlay o (overlay-start o) nl)
            (when (< (1+ nl) end)
              (setq tail (maf-edit--make-entry (1+ nl) end)))
            ;; keep scanning from the tail: it may hold more newlines
            (setq os (if tail (cons tail (cdr os)) (cdr os)))))))))

(defun maf-edit--post-command ()
  "Run the repair deferred by `maf-edit--after-change' during undo.
Also re-derives entry splits (`maf-edit--derive-splits'), since the
insertion-time newline classification never saw the restored text."
  (when maf-edit--pending-repair
    (setq maf-edit--pending-repair nil)
    (let ((maf-edit--inhibit t)
          (inhibit-modification-hooks t))
      (maf-edit--clear-errors)
      (maf-edit--derive-splits)
      (maf-edit--repair)
      (maf-edit--snap-point-out-of-run))))

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

(defun maf-edit--header-line ()
  "Header line shown while editing: a badge plus the exit gestures.
Built with `substitute-command-keys' so rebinding the gestures in
`maf-edit-mode-map' keeps the banner accurate."
  (concat
   (propertize " maf-edit " 'face '(:inherit warning :inverse-video t))
   (substitute-command-keys
    (concat " \\<maf-edit-mode-map>\\[maf-edit-commit] commit"
            " · \\[maf-edit-newline] newline"
            " · \\[maf-edit-discard] discard"))))

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
                  :electric electric-indent-mode
                  :pair electric-pair-mode
                  :header header-line-format))
      ;; Typed delimiters arrive as pairs; unbalanced states are still
      ;; reachable by deletion, and commit diagnoses them.
      (electric-pair-local-mode 1)
      ;; The visual indicator that the buffer is in edit state.
      (setq header-line-format (maf-edit--header-line))
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
            buffer-undo-list nil
            maf-edit--pending-repair nil)
      (add-hook 'after-change-functions #'maf-edit--after-change nil t)
      (add-hook 'post-command-hook #'maf-edit--post-command nil t)
      (maf--point-restore snapshot)
      (message (substitute-command-keys
                "maf-edit: editing stack — \\<maf-edit-mode-map>\\[maf-edit-commit] commits, \\[maf-edit-discard] discards"))))

(defun maf-edit--point-snapshot ()
  "Capture point in the edited buffer, as `maf--point-snapshot' does.
That function's affinities resolve point against calc-stack, which the
edited text no longer reflects — on a grown stack an entry line
misfiles as home and the restore no-ops. Here home is point on or
below the dot overlay's line, and the prefix test reads the
machine-owned text property."
  `((:pos      . ,(point))
    (:line     . ,(line-number-at-pos))
    (:col      . ,(current-column))
    (:affinity . ,(cond ((>= (point)
                             (save-excursion
                               (goto-char (overlay-start maf-edit--dot))
                               (line-beginning-position)))
                         'home)
                        ((eolp) 'eol)
                        ((get-text-property (point) 'maf-edit-prefix)
                         'bol)))))

(defun maf-edit--exit ()
  "Restore the calc buffer: the body of turning `maf-edit-mode' off.
Drops all editing state and re-renders from the (untouched) stack —
discard semantics; `maf-edit-commit' parses before getting here and
pushes after. A quick-add session (`maf-edit--return') restores the
pre-edit point instead of the in-edit one."
  (let ((snapshot (or maf-edit--return (maf-edit--point-snapshot))))
    (setq maf-edit--return nil)
    (remove-hook 'after-change-functions #'maf-edit--after-change t)
    (remove-hook 'post-command-hook #'maf-edit--post-command t)
    (setq maf-edit--pending-repair nil)
    (maf-edit--clear-errors)
    (mapc #'delete-overlay (maf-edit--overlays))
    (when maf-edit--dot
      (delete-overlay maf-edit--dot)
      (setq maf-edit--dot nil))
    (use-local-map (plist-get maf-edit--saved :map))
    (unless (plist-get maf-edit--saved :visual) (visual-line-mode -1))
    (cursor-intangible-mode -1)
    (electric-indent-local-mode (if (plist-get maf-edit--saved :electric) 1 -1))
    (electric-pair-local-mode (if (plist-get maf-edit--saved :pair) 1 -1))
    (setq header-line-format (plist-get maf-edit--saved :header)
          buffer-undo-list (plist-get maf-edit--saved :undo)
          buffer-read-only t)
    (calc-refresh)
    ;; Re-enable only after the refresh: enabling maf-hl-mode runs its
    ;; update immediately, and it must see the re-rendered stack, never
    ;; the edited text, whose positions no longer match calc-stack.
    (when (plist-get maf-edit--saved :maf-mode) (maf-mode 1))
    ;; Unconditional: re-enabling maf-mode drags maf-hl-mode on with
    ;; it, so a manually-off highlighter must be re-asserted off.
    (maf-hl-mode (if (plist-get maf-edit--saved :hl) 1 -1))
    (setq maf-edit--saved nil)
    (maf--point-restore snapshot)))

(defun maf-edit ()
  "Toggle in-place editing of the calc stack.
Off: enter `maf-edit-mode' — the stack becomes plain editable text.
On: commit — parse the buffer back to the stack (`maf-edit-commit')."
  (interactive)
  (if maf-edit-mode
      (maf-edit-commit)
    (maf-edit-mode 1)))

(defun maf-edit--enter-for-add ()
  "Enter maf-edit for a quick-add gesture, stashing the return point.
The pre-edit point snapshot goes into `maf-edit--return', so commit
and discard alike return point to where it was before the gesture."
  (when maf-edit-mode
    (user-error "maf-edit is already active"))
  (let ((snapshot (maf--point-snapshot)))
    (maf-edit-mode 1)
    (setq maf-edit--return snapshot)))

(defun maf-edit-add-entry ()
  "Enter maf-edit with a fresh entry started at the bottom of the stack.
The new entry opens as a blank numbered line just above the dot, point
on its content column, ready to type — from anywhere, including an
empty stack. When the session ends, commit and discard alike, point
returns to where it was before this command ran instead of staying in
the edited text."
  (interactive)
  (maf-edit--enter-for-add)
  (goto-char (overlay-start maf-edit--dot))
  (let ((maf-edit--inhibit t)
        (inhibit-modification-hooks t)
        (bol (point)))
    ;; Open a fresh line just above the dot and make it an entry, the
    ;; way `maf-edit-newline' does for a balanced newline: a temporary
    ;; machine-owned run keeps the zero-length entry out of
    ;; `maf-edit--drop-empty's reach until the repair renumbers it.
    ;; (Insertion at the dot's start lands inside the dot overlay;
    ;; `maf-edit--heal-dot' re-walls it. Entry overlays have no such
    ;; healing, which is why `maf-edit-add-entry-below' rides the
    ;; newline gesture instead.)
    (insert "\n")
    (goto-char bol)
    (insert maf-edit--pad-string)
    (maf-edit--make-entry bol (+ bol maf-edit--prefix-width))
    (maf-edit--repair)
    (goto-char (+ bol (maf-edit--leading-prefix-run bol)))))

(defun maf-edit-add-entry-below ()
  "Enter maf-edit with a fresh entry opened below the entry at point.

  2:  a + b|        3:  a + b
  1:  c        =>   2+  |
                    1:  c

The new entry's blank line opens directly below the entry at point's
line and the levels renumber around it, so typing and committing
inserts mid-stack. At home, or on an empty stack, it opens at the
bottom — `maf-edit-add-entry's opening gesture. Unlike that command,
when the session ends point stays with the edited text — after a
commit it rests on the new entry — rather than returning to where it
was before this command ran."
  (interactive)
  (let ((m (max (calc-locate-cursor-element (point)) 1)))
    (if (zerop (calc-stack-size))
        (progn
          (maf-edit-add-entry)
          ;; This gesture keeps point with the edited text: drop the
          ;; return snapshot the delegated opener stashed.
          (setq maf-edit--return nil))
      (when maf-edit-mode
        (user-error "maf-edit is already active"))
      (maf-edit-mode 1)
      ;; End of entry M's last line: the character before the next
      ;; index line's start. From there the newline gesture opens the
      ;; blank entry through the classify/repair machinery, exactly as
      ;; a hand-typed newline would.
      (goto-char (1- (save-excursion (calc-cursor-stack-index (1- m))
                                     (point))))
      (maf-edit-newline))))

(defun maf-edit-commit ()
  "Parse the edited buffer and commit it to the stack, leaving maf-edit.
Entries whose text is untouched keep their value objects and
selections; changed or new text is parsed in the current input modes
and committed exactly as written, never simplified — 1 + 2 + x stays
1 + 2 + x. If any entry fails to parse the commit is blocked: the
offenders are underlined, point goes to the first, and editing
continues. The whole commit is one undo group."
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
              ;; Raw, not normalized: the user's text commits exactly
              ;; as written; even 1 + 2 must survive unfolded.
              (push v vals)
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
      ;; A quick-add session restores the pre-edit point; read it
      ;; before the mode exit consumes it.
      (let ((snapshot (or maf-edit--return (maf-edit--point-snapshot))))
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
