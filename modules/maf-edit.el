;; -*- lexical-binding: t; -*-
;;
;; modules/edit.el
;;
;; maf-edit: wdired-style in-place editing of the calc stack, packaged
;; as the `edit' module. The module toggle only installs the entry
;; bindings (SPC / ` / C-o / "(") into `maf-mode-map';
;; the editing itself is the on-demand `maf-edit-mode' session below.
;; See `maf-modules'.
;;
;; `maf-edit' (SPC in maf-mode) turns the calc buffer into editable
;; plain text; the same key commits, so RET toggles edit/commit.
;; Each stack entry is tracked by an overlay; the text is the
;; interface. Newline gestures are the only structural operators:
;;
;;   newline at a balanced point      split into two entries
;;   newline inside open delimiters   continue the entry on a new line
;;   joining two entries' lines       merge them into one entry
;;
;; One key works on a whole entry rather than on its text: M-RET copies
;; the entry at point into the slot below it (`maf-edit-dup-entry'),
;; value object and all.
;;
;; Deleting delimiters never restructures — an unbalanced entry just
;; fails to parse at commit. An entry whose commas are its own is the
;; one shape commit completes rather than rejects: 1,2,3 becomes the
;; vector [1, 2, 3], calc having no other reading for a comma at the
;; top level. Level-number prefixes are machine-owned:
;; the cursor skips them, and a repair pass renumbers and re-stamps
;; them after every change; an entry whose text differs from what is
;; on the stack shows N* instead of N:, and a new entry not on the
;; stack yet shows N+. RET parses the buffer and commits it
;; back to the stack as one undoable operation; entries whose text is
;; untouched keep their value objects (display text can be lossy, so
;; they are never reparsed) and their selections. C-c C-k discards.
;;
;; None of the entry gestures run while a calc selection is active: a
;; selected entry is displayed as a dotted mask of itself, so there is
;; no full text to edit. Clear the selection (RET) and edit then.
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
(require 'maf-sel)

;; src/stack.el, loaded with the package core well before any edit
;; session; declared for the byte compiler.
(declare-function maf--yank-strip-levels "stack")
(declare-function maf-latex-to-calc "stack")

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function math-read-expr "calc-aent")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function maf-mode "maf")
(declare-function maf-hl-mode "maf-hl")

;; The module toggle installs its entry keys into this map, defined in
;; maf.el / bindings.el and current by the time the module is enabled.
(defvar maf-mode-map)

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
Set by `maf-edit--enter-for-add' (the quick-add gestures) before
entering; commit and discard both consult it, returning point to where
it was before the edit began instead of keeping its in-edit position.
`maf-edit-entry-at-home' stores a home snapshot here instead,
whose restore is a no-op: that gesture's landing is
`maf-edit--home-return's, not this one's.")

(defvar-local maf-edit--return-home nil
  "Non-nil when this edit session ends with point parked home.
Set by `maf-edit-entry-at-home', whose gesture is a trip home: the
session ends on the dot, commit and discard alike, rather than on the
entry that was typed or back where point started. A point snapshot
here rather than t names the place the gesture left, which is marked
once the session ends — the mark being what returns there.

The mark goes down at the end rather than before the session because
nothing set earlier survives to mean anything: the exit's
`calc-refresh' and the commit's pop-push both rewrite the entry lines
out from under a marker.")

(defvar-local maf-edit--from-home nil
  "Non-nil when `maf-edit' opened this session with point at home.
Set by the toggle alone, so the quick-add gestures — which each state
their own placement — are not affected. Consulted when the session
ends (`maf-edit--exit-placement'): a session opened at home is an
add-at-the-bottom gesture, and point goes back to the . line rather
than staying on the entry that was typed there.")

(defvar maf-edit--inhibit nil
  "Non-nil while maf-edit's own repair edits run, to skip the hooks.")

(defvar maf-edit-parse-text-function #'identity
  "Function mapping an entry's text to the text handed to the parser.
Called by `maf-edit-commit' on each entry whose text has changed, and
on nothing else: an untouched entry keeps its value object and is
never reparsed, so this never sees it. The default is `identity' —
the buffer text is calc's own input syntax.

The extension point for an input dialect: a module that lets entries
be typed in a syntax calc does not read sets this to the function
that translates it. Such a module owns both directions, and the other
one is `maf-edit-mode-on-hook', where the text a session starts with
is rewritten into the dialect. The two must agree, or an entry left
untouched will not compare equal to what a changed one parses back
to. See modules/maf-editvars.el, which does exactly this.")

(defvar maf-edit-transform-value-functions nil
  "Functions rewriting a reparsed entry's value before it commits.
Called in order, each on the previous one's result, on the parsed
value of every entry whose text has changed — and on nothing else: an
untouched entry keeps its value object, as it keeps its text. nil,
the default, commits the parse exactly as written.

The extension point for a module that owes calc a spelling: the
bare log(x) the log key writes — ln to calc's own reading — commits
as the log10(x) calc itself writes (see maf-editplus). A transform
must return a value stable under calc's own rendering — what it
returns is re-rendered, and an edit session started on it hands the
rendering back to this hook — or an entry could change under a commit
that never touched it.")

(defvar maf-edit-transform-text-functions nil
  "Functions rewriting a changed entry's text before it is parsed.
Called in order, each on the previous one's result, on the text of
every entry whose text has changed — and on nothing else: an
untouched entry keeps its value object and is never reparsed. nil,
the default, hands the buffer text straight on. Each runs before
`maf-edit-parse-text-function', so a dialect sees text already in the
notation calc reads.

The text-side counterpart of `maf-edit-transform-value-functions',
and the extension point for a spelling calc has no reading for at
all: a value transform can only rewrite something that parsed, so a
module whose notation is not calc\='s — U for the union calc writes ||
\(see maf-editplus) — has to reach the text. Confined to commit, so
what the session shows is what was typed.")

(defvar maf-edit-mode-map
  (let ((map (make-sparse-keymap)))
    ;; RET confirms; the newline gesture (split/continue) moves to
    ;; S-RET, indenting past the machine-owned prefix area.
    (define-key map (kbd "RET") #'maf-edit-commit)
    (define-key map (kbd "S-<return>") #'maf-edit-newline)
    ;; C-j is the same gesture on a terminal, which cannot deliver
    ;; Shift-Return at all: every wire format folds it back to plain
    ;; RET. It is also the newline key everywhere else in Emacs.
    (define-key map (kbd "C-j") #'maf-edit-newline)
    (define-key map (kbd "C-c C-k") #'maf-edit-discard)
    ;; The entry at point copies into the slot below it. The stack's
    ;; traveling duplicate (`maf-dup-go', reachable by name out there)
    ;; copies too, though its copy lands on top as calc convention has it. The GUI
    ;; event and the terminal form both.
    (define-key map (kbd "M-<return>") #'maf-edit-dup-entry)
    (define-key map (kbd "M-RET") #'maf-edit-dup-entry)
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
    ;; The fraction colon on an unmodified key, as in digit entry
    ;; (`maf-digit-colon'); the displaced semicolon moves one modifier
    ;; up, keeping matrix notation typeable.
    (define-key map (kbd ";") #'maf-edit-insert-colon)
    (define-key map (kbd "M-;") #'maf-edit-insert-semicolon)
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

(defun maf-edit-insert-colon (n)
  "Insert the fraction colon, N times, on the unmodified `;' key.
Fractions are common enough in an edited entry to deserve a key with
no modifier, so `;' types `:' here as it does in digit entry
\(`maf-digit-colon'): 3 ; 4 reads back as the fraction 3:4. A colon
whose operands are no fraction's commits as the quotient it meant —
1:x is 1/x (`maf-edit--colon-quotient')."
  (interactive "p")
  (self-insert-command n ?:))

(defun maf-edit-insert-semicolon (n)
  "Insert a literal semicolon, N times, on \\<maf-edit-mode-map>\\[maf-edit-insert-semicolon].
The character `;' itself gave up its key to the fraction colon
\(`maf-edit-insert-colon'), and it is still calc's row separator in
matrix notation — [1, 2; 3, 4] — so it keeps a key of its own here.
\\[quoted-insert] is not that key: pausing to read a character
re-locks the calc buffer under the editing session, and the insert
that follows fails on a read-only buffer."
  (interactive "p")
  (self-insert-command n ?\;))

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

(defun maf-edit--entry-at-point ()
  "The entry overlay covering point, or nil.
Nil means point is somewhere no entry covers: the home line, or a
blank line not yet adopted by the repair pass.

Entry overlays are rear-advancing and end just before the newline, so
`overlays-at' misses one when point rests at its very end — the usual
place to stand when a key wants the entry point is in. Hence the
widened scan and the explicit inclusive containment test."
  (seq-find
   (lambda (ov)
     (and (overlay-get ov 'maf-edit-entry)
          (<= (overlay-start ov) (point))
          (<= (point) (overlay-end ov))))
   (overlays-in (max (point-min) (1- (point)))
                (min (point-max) (1+ (point))))))

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

(defun maf-edit--nothing-p (text)
  "Non-nil when TEXT resolves to nothing and commits as no entry.
Blank text is the emptied entry; so is text of nothing but balanced
parentheses — the () deleting a group's contents leaves behind wraps
nothing, and resolves to it. Only parentheses count: [] and {} are
the empty vector, a value in its own right. Unbalanced parens stay
parse errors — the safe way to be wrong, as everywhere in maf-edit."
  (let ((d 0) (ok t))
    (dotimes (i (length text))
      (pcase (aref text i)
        (?\( (setq d (1+ d)))
        (?\) (if (zerop d) (setq ok nil) (setq d (1- d))))
        ((or ?\s ?\t ?\n ?\r))
        (_ (setq ok nil))))
    (and ok (zerop d))))

;;; Implicit vectors

(defun maf-edit--top-level-comma-p (text)
  "Non-nil when TEXT holds a comma with nothing enclosing it.
A comma inside delimiters belongs to whatever encloses it — an
argument list, a vector already written out, calc's complex pair
\(1,2) — and a comma inside a string literal is just text. Only a
comma at the top level is one nothing has claimed.

Any closer matches any opener, as everywhere else in maf-edit."
  (let ((i 0) (n (length text)) (d 0) (found nil))
    (while (and (not found) (< i n))
      (let ((c (aref text i)))
        (cond
         ;; A string's contents are not syntax. An unclosed quote eats
         ;; the rest of the text, which is the safe way to be wrong:
         ;; the entry is left alone and calc reports on it.
         ((eq c ?\")
          (setq i (1+ i))
          (while (and (< i n) (not (eq (aref text i) ?\")))
            (setq i (if (eq (aref text i) ?\\) (+ i 2) (1+ i)))))
         ((memq c '(?\( ?\[ ?\{)) (setq d (1+ d)))
         ((memq c '(?\) ?\] ?\})) (setq d (max 0 (1- d))))
         ((and (eq c ?,) (zerop d)) (setq found t))))
      (setq i (1+ i)))
    found))

(defun maf-edit--implicit-vector (text)
  "TEXT wrapped in brackets when a top-level comma makes it a vector.
Typing 1,2,3 means the vector — the brackets are punctuation calc
needs and the writer does not — so commit supplies them.

Never a change of meaning, only of outcome: calc has no reading for a
comma at the top level, so every text this touches is one that would
otherwise have failed to parse. Text that already parses is text this
leaves alone.

Whatever the commas separate comes along: [1,2],[3,4] is the matrix,
and x=1,y=2 the vector of both equations."
  (if (maf-edit--top-level-comma-p text)
      (concat "[" text "]")
    text))

(defun maf-edit--parse-text (text)
  "TEXT as `math-read-expr' should see it.
The whole input side of a commit in one place, in the order the
layers stand: `maf-edit-transform-text-functions' first, so a module
may rewrite a notation calc has no reading for; then the dialect\='s
own `maf-edit-parse-text-function'; then the brackets a top-level
comma earns (`maf-edit--implicit-vector'). Nothing here changes the
buffer — the session keeps showing what was typed."
  (maf-edit--implicit-vector
   (funcall maf-edit-parse-text-function
            (seq-reduce (lambda (s f) (funcall f s))
                        maf-edit-transform-text-functions
                        text))))

;;; Colon quotients

(defun maf-edit--string-regions (text)
  "String-literal spans of TEXT, as a list of (START . END) conses.
END is exclusive. An unclosed quote runs to the end of the text — the
same safe way to be wrong as in `maf-edit--top-level-comma-p': the
rest is treated as literal text rather than syntax."
  (let ((i 0) (n (length text)) (regions nil))
    (while (< i n)
      (if (not (eq (aref text i) ?\"))
          (setq i (1+ i))
        (let ((start i))
          (setq i (1+ i))
          (while (and (< i n) (not (eq (aref text i) ?\")))
            (setq i (if (eq (aref text i) ?\\) (+ i 2) (1+ i))))
          (setq i (min n (1+ i)))
          (push (cons start i) regions))))
    (nreverse regions)))

(defun maf-edit--colon-operand-back (text i)
  "Start of the operand ending just before index I in TEXT, or nil.
An atom — a run of name characters, with a number's own punctuation —
or a balanced group taken whole, together with the name run heading
it, so f(2) is one operand and not an argument list with a stray f
beside it. Nil when nothing usable ends there."
  (let ((j i))
    (when (and (> j 0) (memq (aref text (1- j)) '(?\) ?\] ?\})))
      (let ((depth 0))
        (while (and (> j 0) (not (and (zerop depth) (< j i))))
          (setq j (1- j))
          (pcase (aref text j)
            ((or ?\) ?\] ?\}) (setq depth (1+ depth)))
            ((or ?\( ?\[ ?\{) (setq depth (1- depth)))))
        (when (or (> depth 0) (= j i))
          (setq j nil))))
    (when j
      (while (and (> j 0)
                  (string-match-p "[[:alnum:]_.#]"
                                  (string (aref text (1- j)))))
        (setq j (1- j)))
      (and (< j i) j))))

(defun maf-edit--colon-operand-fwd (text i)
  "End of the operand starting at index I in TEXT, or nil.
The forward mirror of `maf-edit--colon-operand-back', plus one leading
sign — calc's fraction never takes one, so 1:-2 was refused anyway and
the quotient reading is the only one there is. A name run keeps the
group that follows it, so sqrt(2) is one operand. Nil when nothing
usable starts there, an unclosed group included."
  (let ((n (length text)) (j i))
    (when (and (< j n) (memq (aref text j) '(?- ?+)))
      (setq j (1+ j)))
    (while (and (< j n)
                (string-match-p "[[:alnum:]_.#]" (string (aref text j))))
      (setq j (1+ j)))
    (if (and (< j n) (memq (aref text j) '(?\( ?\[ ?\{)))
        (let ((depth 0) (end nil))
          (while (and (< j n) (not end))
            (pcase (aref text j)
              ((or ?\( ?\[ ?\{) (setq depth (1+ depth)))
              ((or ?\) ?\] ?\}) (setq depth (1- depth))
               (when (zerop depth) (setq end (1+ j)))))
            (setq j (1+ j)))
          end)
      (and (> j i)
           (not (and (= j (1+ i)) (memq (aref text i) '(?- ?+))))
           j))))

(defun maf-edit--colon-eligible (text i)
  "The operand bounds around the colon at I, when it can be a quotient.
A cons of the left operand's start and the right operand's end, or
nil. Half of `::' or `:=' is punctuation, not a fraction gone wrong;
a colon between two runs of digits is the fraction calc already
reads, mixed numbers (1:2:3) included, and is left to it."
  (and (not (and (> i 0) (eq (aref text (1- i)) ?:)))
       (not (memq (and (< (1+ i) (length text)) (aref text (1+ i)))
                  '(?: ?=)))
       (let ((start (maf-edit--colon-operand-back text i))
             (end (maf-edit--colon-operand-fwd text (1+ i))))
         (and start end
              (not (and (string-match-p "\\`[0-9]+\\'"
                                        (substring text start i))
                        (string-match-p "\\`[0-9]+\\'"
                                        (substring text (1+ i) end))))
              (cons start end)))))

(defun maf-edit--colon-quotient (text)
  "TEXT with each colon no fraction can claim rewritten as a quotient.
Nil when there is nothing to rewrite. Calc's colon spells an exact
fraction and takes nothing but integers — 1:x is a syntax error, when
the writer plainly meant the quotient — so each such colon becomes a
slash, parenthesized to keep the fraction's tight grip: x^2:y is
x^(2/y), the grouping the colon promised, not (x^2)/y.

Only for text already refused: the caller retries with this reading
after `math-read-expr' fails, so a fraction that parses — and any
other text that means something as written — is never reread. A colon
between two runs of digits is such a fraction and stays, mixed
numbers (1:2:3) included; half of `::' or `:=' stays; a colon inside
a string literal is just text; and a colon with no operand on either
side is left for the error message to point at."
  (let ((rewrote nil)
        (again t))
    (while again
      (setq again nil)
      (let ((strings (maf-edit--string-regions text))
            (i (length text)))
        (while (and (not again) (> i 0))
          (setq i (1- i))
          (when (and (eq (aref text i) ?:)
                     (not (seq-find (lambda (r)
                                      (and (>= i (car r)) (< i (cdr r))))
                                    strings)))
            (let ((bounds (maf-edit--colon-eligible text i)))
              (when bounds
                (setq text (concat (substring text 0 (car bounds))
                                   "("
                                   (substring text (car bounds) i)
                                   "/"
                                   (substring text (1+ i) (cdr bounds))
                                   ")"
                                   (substring text (cdr bounds)))
                      rewrote t
                      ;; An operand can hold colons of its own —
                      ;; f(a:b):x — now at shifted indices: rescan the
                      ;; rewritten text rather than walk on by them.
                      again t)))))))
    (and rewrote text)))

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
  ;; rear-nonsticky: a char typed inside the dot must not inherit
  ;; maf-edit-dot, or the healing salvage below deletes it as one of
  ;; the dot's own characters — swallowing the first keypress of an
  ;; edit session entered with point on the dot.
  (propertize "    ." 'maf-edit-dot t 'rear-nonsticky t)
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

(defun maf-edit--yank-transform (text)
  "Strip stack level prefixes from TEXT as it yanks into the session.
The strip `maf-yank' gives the stack itself (`maf--yank-strip-levels')
runs here at insertion time, on `yank-transform-functions', so the
prefixes never appear in the buffer: a stack quoted in notes pastes as
its entries alone, one per line, ready to commit. LaTeX pastes as the
formula it typesets, the same reading `maf-yank' gives the stack
\(`maf-latex-to-calc')."
  (maf-latex-to-calc (maf--yank-strip-levels text)))

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
with the stack untouched — discard semantics. It is unavailable under
the Big display language, whose multi-line entries it cannot edit, and
while any selection is active, since calc renders a selected entry as a
dotted mask of itself rather than in full. To keep the edits, use
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

(defun maf-edit--newline-key ()
  "Key label for the newline gesture, faced as `substitute-command-keys' does.
That function would name C-j: bound last, it comes first in the
keymap, and it is only the terminal stand-in for the S-RET the
banner is there to teach.  RET is spelled the short way, so the
gesture built on it is too."
  (let* ((keys (where-is-internal #'maf-edit-newline maf-edit-mode-map))
         (desc (cond ((member [S-return] keys) "S-RET")
                     (keys (key-description (car keys)))
                     (t "M-x maf-edit-newline"))))
    (propertize desc 'face 'help-key-binding 'font-lock-face 'help-key-binding)))

(defun maf-edit--header-line ()
  "Header line shown while editing: a badge plus the exit gestures.
Built with `substitute-command-keys' so rebinding the gestures in
`maf-edit-mode-map' keeps the banner accurate; the newline gesture
goes through `maf-edit--newline-key' for the same reason."
  (concat
   (propertize " maf-edit " 'face '(:inherit warning :inverse-video t))
   (substitute-command-keys " \\<maf-edit-mode-map>\\[maf-edit-commit] commit")
   " · " (maf-edit--newline-key) " newline"
   (substitute-command-keys
    " · \\<maf-edit-mode-map>\\[maf-edit-discard] discard")))

(defun maf-edit--enter ()
  "Make the calc buffer editable: the body of turning `maf-edit-mode' on."
  (unless (derived-mode-p 'calc-mode)
    (user-error "maf-edit only works in a calc buffer"))
  (unless calc-line-numbering
    (user-error "maf-edit requires calc-line-numbering"))
  ;; The Big display language renders entries across multiple lines,
  ;; which maf-edit's one-entry-per-line model cannot handle.
  (when (eq calc-language 'big)
    (user-error "maf-edit does not work in the Big display language"))
  ;; A selected entry is not rendered in full: calc replaces every
  ;; unselected character with a dot (`math-comp-highlight-string'), so
  ;; the text maf-edit would hand over for editing is a mask, and
  ;; editing it into something parsable commits the selected part alone
  ;; — the rest of the formula silently dropped. Refusing is also the
  ;; right answer for the common case: SPC pressed while drilled into a
  ;; sub-formula is a fumble, not a request to edit.
  ;;
  ;; Keyed to the display (`maf--sel-any-shown-p'), not to whether the
  ;; selection has any effect: with `calc-use-selections' nil calc masks
  ;; the entry all the same, and drops the * marker that would have
  ;; warned about it.
  (when (maf--sel-any-shown-p)
    (user-error
     "%s" (substitute-command-keys
           (concat
            "maf-edit does not run with a selection active — "
            ;; RET only clears while the selection is effective;
            ;; otherwise it is the duplicate, and naming it here would
            ;; send the user off to grow their stack.
            (if (maf--sel-any-p)
                "\\<maf-mode-map>\\[maf-dup-or-clear-selections] clears it"
              "\\[maf-clear-selections] clears it")))))
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
          ;; rear-nonsticky as in `maf-edit--dot-string': a char typed
          ;; mid-dot must not inherit maf-edit-dot, or healing deletes it.
          (add-text-properties (point) (line-end-position)
                               '(maf-edit-dot t rear-nonsticky t)))
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
      (add-hook 'yank-transform-functions #'maf-edit--yank-transform nil t)
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

(defun maf-edit--at-stack-entry-p ()
  "Non-nil when point is inside an entry that came from the stack.
An entry overlay carries `maf-edit-val' only when it was adopted at
entry, so this separates work on an entry that was already there from
work on one the session opened."
  (seq-some (lambda (o)
              (and (overlay-get o 'maf-edit-val)
                   (>= (point) (overlay-start o))
                   (<= (point) (overlay-end o))))
            (maf-edit--overlays)))

(defun maf-edit--exit-placement ()
  "Where point should go when this session ends.
Either a point snapshot for `maf--point-restore' or the symbol `home'
for the . line itself; `maf-edit--place-point' applies it. Must be
read while the session still stands — the overlays it consults are
gone once the mode is off.

Three placements, in order. A quick-add session returns to the point
it stashed (`maf-edit--return'). A session `maf-edit' opened at home
goes back home: opening there is the gesture for adding at the bottom,
and the next SPC should start the next entry rather than land on the
one just committed. Anything else keeps its in-edit position —
including a home-opened session whose point ended up inside an entry
that came from the stack, the user having gone off to work on that
entry, which is what the plain session is for."
  (cond (maf-edit--return)
        ((and maf-edit--from-home (not (maf-edit--at-stack-entry-p))) 'home)
        (t (maf-edit--point-snapshot))))

(defun maf-edit--place-point (placement)
  "Put point where PLACEMENT (`maf-edit--exit-placement') asks.
Home is placed outright rather than left to `maf--point-restore',
whose home affinity is a no-op on the assumption that the stack
rewrite already parked point there — true after the commit's push, not
after the plain refresh a discard leaves behind. No mark is dropped:
the session opened at home, so there is no journey to offer a way back
from."
  (if (eq placement 'home)
      (progn (calc-cursor-stack-index 0)
             ;; The dot sits past the line-number margin when numbering
             ;; is on, at the line's start when it is off.
             (skip-chars-forward " "))
    (maf--point-restore placement)))

(defun maf-edit--home-return (spec)
  "Finish a home-landing quick-add gesture, SPEC as `maf-edit--return-home'.
Point is parked on the dot — where calc parks it after every command,
and where `maf-go-home' lands — rather than left wherever the
re-render put it. A SPEC that is a point snapshot also gets a silent
mark at the place the gesture left, so a single `pop-to-mark-command'
\(or `maf-go-home' pressed on the dot) returns there. Call this on the
re-rendered stack, never before; nil is a no-op."
  (when spec
    (when (consp spec)
      (save-excursion
        (maf--point-restore spec)
        (maf--mark-before-home)))
    (calc-cursor-stack-index 0)
    ;; The dot sits past the line-number margin when numbering is on,
    ;; at the line's start when it is off — as in `maf-go-home'.
    (skip-chars-forward " ")))

(defun maf-edit--exit ()
  "Restore the calc buffer: the body of turning `maf-edit-mode' off.
Drops all editing state and re-renders from the (untouched) stack —
discard semantics; `maf-edit-commit' parses before getting here and
pushes after. Point lands where `maf-edit--exit-placement' says: the
in-edit position, the pre-edit one a quick-add session stashed, or
home for a session opened there; a home-landing quick-add
\(`maf-edit--return-home') then parks it on the dot and marks where it
left."
  (let ((placement (maf-edit--exit-placement))
        (homespec maf-edit--return-home))
    (setq maf-edit--return nil
          maf-edit--from-home nil
          maf-edit--return-home nil)
    (remove-hook 'after-change-functions #'maf-edit--after-change t)
    (remove-hook 'post-command-hook #'maf-edit--post-command t)
    (remove-hook 'yank-transform-functions #'maf-edit--yank-transform t)
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
    (when (plist-get maf-edit--saved :maf-mode) (maf-mode 1))
    ;; Restore the highlighter to its pre-edit state, an independent
    ;; module now (not dragged along by maf-mode). Only after the
    ;; refresh: enabling maf-hl-mode runs its update immediately, and it
    ;; must see the re-rendered stack, never the edited text, whose
    ;; positions no longer match calc-stack.
    (maf-hl-mode (if (plist-get maf-edit--saved :hl) 1 -1))
    (setq maf-edit--saved nil)
    (maf-edit--place-point placement)
    (maf-edit--home-return homespec)))

(defun maf-edit ()
  "Toggle in-place editing of the calc stack.
Off: enter `maf-edit-mode' — the stack becomes plain editable text.
On: commit — parse the buffer back to the stack (`maf-edit-commit').

Pressed at home the session is remembered as opened there
\(`maf-edit--from-home'), so the entry typed onto the . line commits
with point back at home — ready for the next one. The flag is recorded
after entering, the way `maf-edit--enter-for-add' stashes its return
point, but read before: once the session is running the text no longer
has to match the stack the home test asks about."
  (interactive)
  (if maf-edit-mode
      (maf-edit-commit)
    (let ((home (maf--at-home-p)))
      (maf-edit-mode 1)
      (setq maf-edit--from-home home))))

(defun maf-edit--enter-for-add ()
  "Enter maf-edit for a quick-add gesture, stashing the return point.
The pre-edit point snapshot goes into `maf-edit--return', so commit
and discard alike return point to where it was before the gesture."
  (when maf-edit-mode
    (user-error "maf-edit is already active"))
  (let ((snapshot (maf--point-snapshot)))
    (maf-edit-mode 1)
    (setq maf-edit--return snapshot)))

(defun maf-edit--open-at-dot ()
  "Open a blank entry at the bottom of a running session; return its overlay.
Point lands on the new entry's content column, ready to type. The
opening gesture of the quick-add commands, separated from entering the
session so a command already inside one can add an entry at home too."
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
    (prog1 (maf-edit--make-entry bol (+ bol maf-edit--prefix-width))
      (maf-edit--repair)
      (goto-char (+ bol (maf-edit--leading-prefix-run bol))))))

(defun maf-edit--open-line-above (bol)
  "Open a blank entry line just above the entry line starting at BOL.
Point lands on the new entry's content column, ready to type; the new
entry's overlay is returned. The counterpart of
`maf-edit--open-at-dot' for a line that already belongs to an entry:
the newline lands inside that entry's overlay — entry overlays advance
at the rear, not the front — so the overlay is re-walled onto the line
it still owns before the blank line becomes an entry of its own."
  (let ((maf-edit--inhibit t)
        (inhibit-modification-hooks t)
        (below (seq-find (lambda (o) (= (overlay-start o) bol))
                         (maf-edit--overlays))))
    (goto-char bol)
    (insert "\n")
    (when below (move-overlay below (1+ bol) (overlay-end below)))
    (goto-char bol)
    ;; As in `maf-edit--open-at-dot': the machine-owned run keeps the
    ;; zero-length entry out of `maf-edit--drop-empty's reach until the
    ;; repair renumbers it.
    (insert maf-edit--pad-string)
    (prog1 (maf-edit--make-entry bol (+ bol maf-edit--prefix-width))
      (maf-edit--repair)
      (goto-char (+ bol (maf-edit--leading-prefix-run bol))))))

(defun maf-edit-entry-at-home ()
  "Enter maf-edit on the entry at stack level 1, landing point home.

  2:  a|+ b         2:  a + b
  1:  12       =>   1:  123
                        .|

The bottom entry — level 1, the one nearest home — opens for editing
with point at the end of its text, ready to extend or correct it, from
wherever point stood. On an empty stack there is nothing to edit, so a
blank entry opens at the bottom instead and the gesture is the quick
add it used to be throughout.

The session is a trip home: when it ends point lands on the dot, below
the committed entry, and the place it left is marked. A single
\\[pop-to-mark-command] returns to it, as does \\[maf-go-home], which
bounces back to the mark when pressed at home. Pressed at home there
is nothing to mark and nothing to return from.

Discarding lands home too — the trip out happened either way, and the
mark is still the way back."
  (interactive)
  (when maf-edit-mode
    (user-error "maf-edit is already active"))
  ;; Read the stack before entering: inside a session the buffer is
  ;; plain text, and the empty case is the one that has no entry to
  ;; open on.
  (let ((emptyp (zerop (calc-stack-size)))
        ;; t rather than nil at home: the session still lands on the
        ;; dot, there is just no journey to mark.
        (origin (if (maf--at-home-p) t (maf--point-snapshot))))
    (maf-edit-mode 1)
    ;; A home snapshot makes the exit's point restore a no-op, leaving
    ;; the landing to `maf-edit--home-return' rather than to the
    ;; position point held inside the edited text.
    (setq maf-edit--return (list (cons :affinity 'home))
          maf-edit--return-home origin)
    (if emptyp
        (maf-edit--open-at-dot)
      ;; Entry overlays come back in buffer order and level 1 renders
      ;; last, just above the dot, so the final one is the entry this
      ;; gesture opens on. Its end is where the text stops, the
      ;; newline excluded — the same column a freshly opened blank
      ;; entry leaves point on.
      (goto-char (overlay-end (car (last (maf-edit--overlays))))))))

(defun maf-edit-add-entry-below ()
  "Enter maf-edit with a fresh entry opened below the entry at point.

  2:  a + b|        3:  a + b
  1:  c        =>   2+  |
                    1:  c

The new entry's blank line opens directly below the entry at point's
line and the levels renumber around it, so typing and committing
inserts mid-stack. At home, or on an empty stack, it opens at the
bottom. Unlike `maf-edit-add-vector', when the session ends point
stays with the edited text — after a commit it rests on the new
entry — rather than returning to where it was before this command ran."
  (interactive)
  (let ((m (max (calc-locate-cursor-element (point)) 1))
        (emptyp (zerop (calc-stack-size))))
    (when maf-edit-mode
      (user-error "maf-edit is already active"))
    (maf-edit-mode 1)
    (if emptyp
        ;; Nothing to sit below: open the blank entry at the dot, the
        ;; same place the bottom of the stack would be.
        (maf-edit--open-at-dot)
      ;; End of entry M's last line: the character before the next
      ;; index line's start. From there the newline gesture opens the
      ;; blank entry through the classify/repair machinery, exactly as
      ;; a hand-typed newline would.
      (goto-char (1- (save-excursion (calc-cursor-stack-index (1- m))
                                     (point))))
      (maf-edit-newline))))

(defun maf-edit-add-entry-above ()
  "Enter maf-edit with a fresh entry opened above the entry at point.

  2:  a + b|        3+  |
  1:  c        =>   2:  a + b
                    1:  c

The new entry's blank line opens directly above the entry at point's
line and the levels renumber around it, so typing and committing
inserts mid-stack. At home, or on an empty stack, it opens at the
bottom — the dot's line is the one it opens above. Point stays with
the edited text when the session ends: after a commit it rests on the
new entry.

The upward twin of `maf-edit-add-entry-below', which opens the blank
line on the other side of the same entry."
  (interactive)
  (when maf-edit-mode
    (user-error "maf-edit is already active"))
  ;; The level is read before the session's re-render, which entry
  ;; positions do not survive; the level index does.
  (let ((m (calc-locate-cursor-element (point))))
    (maf-edit-mode 1)
    (if (or (<= m 0) (zerop (calc-stack-size)))
        ;; Home, or an empty stack: nothing to sit above but the dot,
        ;; which is where the bottom of the stack is.
        (maf-edit--open-at-dot)
      (maf-edit--open-line-above
       (save-excursion (calc-cursor-stack-index m) (point))))))

(defun maf-edit-add-vector ()
  "Enter maf-edit with a fresh vector entry started at the bottom.

  1:  a + b        1:  a + b
      .        =>  1+  [|]
                       .

A blank entry opened at home, pre-filled with an empty pair of
brackets and point between them, so the elements are all that is left
to type. One key for a shape whose closing bracket is a nuisance to
reach — and unlike typing the bracket into an edit session, it also
opens the session.

Committed untouched it pushes the empty vector []; \\<maf-edit-mode-map>\\[maf-edit-discard] backs out
instead. Unlike `maf-edit-add-entry-below', point returns to where it
was before the command when the session ends.

In the native layout the key reaches this command from home alone —
`maf-goto-left-side' owns it on an entry, where the vector would have
nothing to do with what point is on — and in the calc layout from
anywhere."
  (interactive)
  (maf-edit--enter-for-add)
  (maf-edit--open-at-dot)
  ;; Inserted as one literal string rather than typed through
  ;; `electric-pair-mode': the pair is what is wanted, and going
  ;; through the electric path would depend on the user's own
  ;; `electric-pair-inhibit-predicate'.
  (insert "[]")
  (backward-char))

;;; Duplicating an entry

(defun maf-edit-dup-entry (&optional n)
  "Duplicate the entry at point, placing the copy directly below it.

  3:  a + b       4:  a + b
  2:  c|      =>  3:  c
  1:  d           2:  c|
                  1:  d

The entry is copied whole, however many lines it renders on, and the
copy carries the value the original holds rather than a re-reading of
its text: a number whose display is lossy — a rounded float, a fixed
notation — duplicates exactly, and the copy shows the plain N: of an
entry that matches the stack. An entry already edited copies as the
text it now has, both showing N* as before.

Point travels to the copy, keeping its place within the entry. On the
home line there is no entry to copy, so the bottom one is duplicated
and point stays home. An active region is never consulted, and a
numeric prefix argument makes N copies.

  1:  [ [ 1, 2 ]        2:  [ [ 1, 2 ]
        [ 3, 4 ] ]  =>        [ 3, 4 ] ]     (a matrix copies whole)
                        1:  [ [ 1, 2 ]
                              [ 3, 4 ] ]

The in-session sibling of `maf-dup-go' out in the stack —
though there the copy lands on top, as calc convention has it,
while a session's natural slot is right below the source. Both work on
the entry, never on the screen line: a
line-based duplicate would cut a matrix across its rows, and would
have to read every copy back from whatever the display shows."
  (interactive "p")
  (unless maf-edit-mode
    (user-error "maf-edit is not active"))
  (let* ((o (or (maf-edit--entry-at-point)
                ;; Home, or a blank line: the bottom entry is the one to
                ;; copy, as it is the subject of the same key at home out
                ;; in the stack.
                (car (last (maf-edit--overlays)))))
         ;; Point's offset into the entry, measured before the insert
         ;; and replayed against the copy — the two render identically,
         ;; prefix run included. Nil when point is on no entry at all,
         ;; which is where it stays.
         (offset (when (and o (>= (point) (overlay-start o))
                            (<= (point) (overlay-end o)))
                   (- (point) (overlay-start o))))
         (copy nil))
    (unless o
      (user-error "No entry to duplicate"))
    ;; The surgery moves point to do its inserting; an excursion hands it
    ;; back, which is the whole answer for a point that was never on the
    ;; entry — home stays home, the copy going in above it. A point that
    ;; was on the entry is placed on the copy below, once the repair has
    ;; settled the text it lands in.
    (save-excursion
      (let ((maf-edit--inhibit t)
            (inhibit-modification-hooks t)
            (text (buffer-substring (overlay-start o) (overlay-end o))))
        (maf-edit--clear-errors)
        (dotimes (_ (max 1 (or n 1)))
          (let ((start (overlay-start o))
                (end (overlay-end o)))
            (goto-char end)
            ;; The newline lands inside the source overlay, which advances
            ;; at the rear; re-wall it onto the lines it still owns before
            ;; the copy below becomes an entry of its own. Inserting at
            ;; the next line's beginning instead — where a line-based
            ;; duplicate puts its copy — would land inside the
            ;; *neighbour's* overlay, whose value object the copy would
            ;; then carry off.
            (insert "\n")
            (move-overlay o start end)
            (let ((bol (point)))
              (insert text)
              ;; The value and the text it was rendered from, so commit
              ;; passes the object through untouched. The selection is not
              ;; copied: it points into the entry it was made in.
              (setq copy (maf-edit--make-entry bol (point)
                                               (overlay-get o 'maf-edit-val)
                                               nil
                                               (overlay-get o 'maf-edit-text))))))
        (maf-edit--repair)))
    (when offset
      (goto-char (min (+ (overlay-start copy) offset) (overlay-end copy))))
    (maf-edit--snap-point-out-of-run)))

(defun maf-edit-commit ()
  "Parse the edited buffer and commit it to the stack, leaving maf-edit.
Entries whose text is untouched keep their value objects and
selections; changed or new text is parsed in the current input modes
and committed exactly as written, never simplified — 1 + 2 + x stays
1 + 2 + x. The exceptions are deliberate and both belong to modules:
`maf-edit-transform-text-functions' rewrites the text before it is
parsed, and `maf-edit-transform-value-functions' maps each reparsed
value, so a module can commit a spelling calc prefers over the one
the session wanted visible (`maf-edit--parse-text').

An entry emptied to blank commits as deleted, and so does one left
holding nothing but empty parentheses: () wraps nothing and resolves
to it (`maf-edit--nothing-p').

An entry whose commas are its own — 1,2,3 — commits as the vector
[1, 2, 3]: the brackets are punctuation calc wants and the writer does
not, so commit supplies them (`maf-edit--implicit-vector'). Only a
comma at the top level counts, so an argument list and a vector
already written out are untouched.

A colon calc refuses commits as a quotient: the fraction colon takes
nothing but integers, so 1:x is a syntax error where the writer
plainly meant 1/x, and commit retries it as one
\(`maf-edit--colon-quotient'). Only an entry that failed to parse is
retried, so 1:2 stays the exact fraction it is.

If any entry fails to parse the commit is blocked: the offenders are
underlined and editing continues, with point sent to the first
offender — unless it is already inside one, where it stays put and
that entry's error is the one reported. The whole commit is one undo
group.

Point lands where `maf-edit--exit-placement' says — with the edited
text, at the pre-edit spot a quick-add gesture stashed, or home for a
session `maf-edit' opened there."
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
         ((maf-edit--nothing-p text))   ; emptied entry (or bare ()): deleted
         ((and (overlay-get o 'maf-edit-val)
               (equal text (overlay-get o 'maf-edit-text)))
          (push (overlay-get o 'maf-edit-val) vals)
          (push (overlay-get o 'maf-edit-sel) sels))
         (t
          (let ((v (math-read-expr (maf-edit--parse-text text))))
            ;; A colon calc refused gets a second reading as a quotient
            ;; (`maf-edit--colon-quotient') — only ever for text already
            ;; refused whole, so nothing that parses is reread. A retry
            ;; that fails too changes nothing, and the error reported is
            ;; the original text's own.
            (when (eq (car-safe v) 'error)
              (let ((again (maf-edit--colon-quotient text)))
                (when again
                  (let ((v2 (math-read-expr (maf-edit--parse-text again))))
                    (unless (eq (car-safe v2) 'error)
                      (setq v v2))))))
            (if (eq (car-safe v) 'error)
                (push (cons o (if (zerop (maf-edit--string-net-depth text))
                                  (nth 2 v)
                                (concat (nth 2 v)
                                        " (unbalanced delimiters)")))
                      errors)
              ;; Raw, not normalized: the user's text commits exactly
              ;; as written; even 1 + 2 must survive unfolded. The
              ;; transform hook is the one deliberate exception.
              (push (seq-reduce (lambda (val f) (funcall f val))
                                maf-edit-transform-value-functions v)
                    vals)
              (push nil sels)))))))
    (if errors
        (let* ((errors (nreverse errors))
               ;; Point inside an offender is already at the problem —
               ;; typically mid-typing, on the very entry that failed to
               ;; parse. Sending it to the entry's first column there
               ;; would only cost the user their place.
               (here (seq-find (lambda (e)
                                 (let ((o (car e)))
                                   (and (>= (point) (overlay-start o))
                                        (<= (point) (overlay-end o)))))
                               errors)))
          (dolist (e errors) (maf-edit--flag-error (car e) (cdr e)))
          (unless here
            (goto-char (overlay-start (caar errors)))
            ;; Land on the first content column: the overlay starts at
            ;; the machine-owned prefix, which point may not occupy.
            (maf-edit-move-beginning-of-line 1))
          (user-error "maf-edit: cannot commit — %s"
                      (cdr (or here (car errors)))))
      ;; Buffer top-to-bottom is deepest-first, the order
      ;; calc-pop-push-record-list pushes in.
      (setq vals (nreverse vals)
            sels (nreverse sels))
      ;; Where point lands, read before the mode exit consumes the
      ;; session state it rests on. A home-landing quick-add is taken
      ;; away from the exit rather than read alongside: the pop-push
      ;; below replaces every entry line, so both the dot the exit
      ;; would park on and the marker it would set are stale by the
      ;; time the user sees the stack. It happens down here instead,
      ;; once the stack they are left looking at is drawn.
      (let ((placement (maf-edit--exit-placement))
            (homespec maf-edit--return-home))
        (setq maf-edit--return-home nil)
        ;; Turning the mode off restores the buffer and re-renders from
        ;; the unchanged stack — required before the pop-push, which
        ;; edits the buffer by entry heights the edited text no longer
        ;; matches.
        (maf-edit-mode -1)
        (calc-wrapper
         (calc-pop-push-record-list (calc-stack-size) "edit" vals 1 sels))
        (maf-edit--place-point placement)
        (maf-edit--home-return homespec)
        (message "maf-edit: committed %d entr%s"
                 (length vals) (if (= 1 (length vals)) "y" "ies"))))))

(defun maf-edit-discard ()
  "Leave maf-edit, discarding every edit; the stack is untouched."
  (interactive)
  (unless maf-edit-mode (user-error "maf-edit is not active"))
  (maf-edit-mode -1)
  (message "maf-edit: discarded"))

;;; The module

(define-minor-mode maf-use-edit-mode
  "Edit Calc stack entries as ordinary text.

With this mode on:

  SPC  Edit the entry at point.
  `    Go to the bottom of the stack and add an entry there.
  C-o  Add an entry above the one at point. Pressed at home in the
       native layout, where the key is otherwise the relation
       crossing; anywhere on the stack in the calc layout.
  (    Add an empty vector at the bottom of the stack. Pressed at home
       in the native layout, where the parens are otherwise the
       relation motions; anywhere on the stack in the calc layout.

While editing, change formulas directly in the Calc buffer. For
example, change x+1 to x+2 without deleting and re-entering the stack
item. RET saves all edits; C-c C-k discards them. S-RET splits one
entry into two, and deleting the newline between two entries joins
them.

In-place editing is unavailable in Big display and while a Calc
selection is active. Turning this mode off removes its entry keys but
does not change the stack."
  :global t
  :group 'maf
  ;; The keys are declared below; the toggle only recompiles them in
  ;; or out (see core/maf-bindings.el).
  (maf-bindings--refresh))

;; The vector-add's "(" and the entry-add's C-o are calc-profile keys
;; alone: in native (and in vim, by derivation) the parens are the
;; relation motions `maf-goto-left-side' and `maf-goto-right-side' and
;; C-o is the crossing `maf-goto-other-side' (src/bindings.el), which
;; hand the keys back to these commands at home — the one place there
;; is no entry to move within. Declaring them here for those profiles
;; too would be a second owner on the keys, which the compiler refuses
;; outright rather than resolving by precedence.
(maf-bindings-module-keys 'maf-edit 'maf-use-edit-mode
  '(((calc native vim) "SPC" maf-edit)
    ((calc native vim) "`" maf-edit-entry-at-home)
    ((calc) "C-o" maf-edit-add-entry-above)
    ((calc) "(" maf-edit-add-vector)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-edit #'maf-use-edit-mode
                       "Edit the stack in place as plain text.

Press SPC to edit the entry at point, then RET to save it. For
example, change x+1 to x+2 directly on the stack. S-RET splits an
entry; deleting the newline between two entries joins them."
                       "SPC, `, C-o and \"(\" (at home)" "Editing"))

(provide 'maf-edit)
