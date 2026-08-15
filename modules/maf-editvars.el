;; -*- lexical-binding: t; -*-
;;
;; modules/maf-editvars.el
;;
;; maf-editvars: handwritten-style algebra inside a maf-edit session.
;; An input dialect, not a change to calc — the stack, the trail and
;; every other buffer keep calc's own syntax; only the text of an edit
;; session is read this way, and only while this module is on.
;;
;; Calc reads a run of letters as one variable: xy is the variable xy,
;; and a product has to be written x y or x*y. On paper it is the other
;; way round — 5xy is three factors — so an expression typed the way it
;; is written comes out meaning something else, silently, and looks
;; right on the stack afterwards. This module inverts the rule:
;;
;;   2xy              2*x*y          letters are separate factors
;;   \cm              cm             a mark quotes one identifier
;;   2\cm             2*cm
;;   \foo+x           foo+x
;;   xy(5)            the function xy, called on 5
;;   \xy(5)           xy*5           the variable xy, times 5
;;   map(\sin,[1,2])  sin passed by name, not called
;;
;; The rule is uniform and takes no account of what anything means:
;; every run of letters splits, whether or not calc knows the name, so
;; \pi and \cm are quoted exactly as \foo is. That is the point. An
;; earlier design left "known" names — calc's 171 units, its constants,
;; whatever the user had stored — unsplit, which made the meaning of a
;; run of letters depend on a table nobody has read (lx is lux, mu is
;; the micron, me is the electron mass) and on mutable state, so that
;; storing into xy would quietly change what 5xy meant. Quoting is
;; explicit, visible in the text, and stable.
;;
;; A run is a *letter* run: a name with a digit in it is one identifier
;; already and needs no quoting, so x1 and xy1 pass through untouched.
;; A name directly in front of `(' is a function call and is left
;; alone; the space in calc's own rendering of a product (cm x, and
;; cm*(x + 1) with the operator explicit) is what keeps the two apart.
;;
;; Both directions are this module's, because a session that only
;; translated one way would corrupt what it loaded. `maf-edit-commit'
;; reparses a whole entry as soon as any part of it changes, so an
;; untouched foo sitting in an entry edited elsewhere would split; the
;; text a session starts with is therefore rewritten into the dialect
;; up front (every multi-letter identifier quoted), and an entry that
;; is never touched still compares equal and keeps its value object.
;;
;; Quoted names are highlighted: `maf-editvars-quoted' for an ordinary
;; one, and `maf-editvars-unit' — gold — when the quoted name is one
;; calc's unit table knows. The colour is commentary only. Nothing about
;; what an entry means depends on it, which is the difference between
;; this and the version where the colour was load-bearing.
;;
;; The quoting mark is `maf-editvars-quote-char', and `\' is only its
;; default. That default reads well — it is what TeX uses, so \pi is
;; already familiar — but calc reads `\' as integer division, so a
;; session that wants both wants another character. Calc leaves `@',
;; `~' and `` ` `` unread, and any of them will serve.
;;
;; Restricted to the Normal language, and not merely because the
;; default mark is TeX's escape — changing the mark does not lift the
;; restriction. What the dialect rests on is that juxtaposition means
;; multiplication, and that is a fact about the Normal language alone.
;; Calc's Mathematica mode renders sin(x) as `sin x' and foo(bar) as
;; `foo bar': there juxtaposition is function application, and 2xy
;; parses as (2 x) y rather than 2 (x y). Other languages break the
;; translation in their own ways — C spells pi as M_PI, whose PI this
;; module would split; TeX writes products with \times, which the
;; default mark would read as a quoted name. In any language but
;; Normal the module stands down and entries are read as calc would
;; read them.
;;
;; The module toggle is `maf-use-editvars-mode', registered as
;; `maf-editvars' (see `maf-modules') and enabled by default. It does
;; change what typed text means, but only inside maf-edit sessions and
;; only in the Normal language; a session that wants calc's plain
;; reading back drops it from `maf-modules'.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'calc)
(require 'maf-edit)          ; the session this module extends
(require 'maf-conf "conf")   ; the `maf' customize group

(declare-function math-check-unit-name "calc-units")

;; The module toggle, defined by the `define-minor-mode' at the end of
;; the file; the applicability test above it reads the variable.
(defvar maf-use-editvars-mode)

;;; The quoting character

(defcustom maf-editvars-quote-char ?\\
  "Character that quotes the identifier following it, as in \\=\\cm.
Written directly in front of a run of letters, it holds the run
together as one name where it would otherwise split into factors.

The default reads well — it is TeX's own escape, and TeX is how most
people have written \\=\\pi before — but it is not free: calc reads `\\='
as integer division, so `5\\=\\b' is idiv(5, b) to calc and the quoted
name b here. The dialect wins inside an edit session, which is the
point of a dialect, but anyone who uses integer division in one will
want a different character. Calc leaves `@', `~' and `\\=`' unread, and
any of them can be this.

Must not be a letter or a digit: those are what identifiers are made
of, and the scanner could not tell the mark from the name. It should
also not be one of the characters calc uses to open something whose
letters are not identifiers — `\"' (a string) or `<' (a date form) —
since the mark is recognised before those and would shadow them.
`maf-editvars-quote-char-valid-p' is the test, and the module refuses
to translate under a character that fails it rather than mangling the
buffer."
  :type 'character
  :group 'maf)

(defun maf-editvars-quote-char-valid-p (&optional char)
  "Non-nil when CHAR can serve as `maf-editvars-quote-char'.
Defaults to the current setting. See that variable for what rules a
character out."
  (let ((c (or char maf-editvars-quote-char)))
    (and (characterp c)
         (not (maf-editvars--alnum-p c))
         (not (memq c '(?\" ?<))))))

(defun maf-editvars--quote-string ()
  "The quoting character as a one-character string."
  (char-to-string maf-editvars-quote-char))

;;; Faces

(defface maf-editvars-quoted
  '((t :inherit font-lock-variable-name-face))
  "Face for a quoted identifier in a maf-edit session.
Marks the spans this module is holding together as one name, so that
what will split and what will not is visible in the text rather than
remembered."
  :group 'maf)

(defface maf-editvars-unit
  '((((background light)) :foreground "#8a6d00")
    (((background dark))  :foreground "#d7b13d"))
  "Face for a quoted identifier calc's unit table knows — gold.
Supplemental only: quoting is what makes cm one name, and the colour
merely says that this particular name is also a unit. An unrecognised
name is quoted just as effectively and wears `maf-editvars-quoted'."
  :group 'maf)

;;; Reading the text

;; The scanner below walks a line of entry text once and classifies it
;; into four kinds of token, whose strings concatenate back to the
;; input. Everything that is not an identifier this module has an
;; opinion about — numbers, strings, operators, delimiters — is `raw'
;; and is copied through untouched, which is what keeps the dialect
;; out of the parts of calc's syntax that happen to contain letters:
;; 1e5, 16#ff, a date form.

(defun maf-editvars--digit-p (c)
  "Non-nil when C is an ASCII digit."
  (and c (<= ?0 c) (<= c ?9)))

(defun maf-editvars--letter-p (c)
  "Non-nil when C is an ASCII letter."
  (and c (or (and (<= ?a c) (<= c ?z))
             (and (<= ?A c) (<= c ?Z)))))

(defun maf-editvars--alnum-p (c)
  "Non-nil when C can appear inside an identifier after its first character."
  (or (maf-editvars--letter-p c) (maf-editvars--digit-p c)))

(defun maf-editvars--word-end (text i)
  "Index in TEXT just past the identifier starting at I.
I must be the index of a letter. Digits are taken in after the first
character, so x1 is one identifier."
  (let ((n (length text)))
    (while (and (< i n) (maf-editvars--alnum-p (aref text i)))
      (setq i (1+ i)))
    i))

(defun maf-editvars--string-end (text i)
  "Index in TEXT just past the string literal opening at I.
Returns the length of TEXT for a string that is never closed — the
rest of the line is then copied through untouched, which is the safe
way to be wrong: calc reads it, this module does not rewrite it. An
unclosed quote is also how an hms form (1@ 2' 3\") looks to this
scanner, and leaving one alone is right for the same reason."
  (let ((n (length text)))
    (setq i (1+ i))
    (while (and (< i n) (not (eq (aref text i) ?\")))
      (setq i (if (eq (aref text i) ?\\) (+ i 2) (1+ i))))
    (min n (1+ i))))

(defconst maf-editvars--date-re "\\`<[-+0-9:.,/ A-Za-z]*>"
  "A date form, as much of one as this scanner needs to recognise.
Calc's date forms carry month and day names — <Aug 4, 2026> — which
must not be split. `<' is also the less-than operator, and a<b must
not be swallowed, so the run only counts as a date when it closes and
holds a digit and nothing that would be an operator inside it.")

(defun maf-editvars--date-end (text i)
  "Index in TEXT just past the date form starting at I, or nil.
Nil means the `<' at I is the comparison operator."
  (let ((tail (substring text i)))
    (when (string-match maf-editvars--date-re tail)
      (let ((end (match-end 0)))
        (and (string-match-p "[0-9]" (substring tail 0 end))
             (+ i end))))))

(defun maf-editvars--number-end (text i)
  "Index in TEXT just past the number starting at I.
I must be the index of a digit. Covers what calc's number syntax can
put letters into and this module must therefore not touch: a radix
form (16#ff), and a float exponent (1e5, 1.5e-3). The `.' of an
interval (1..2) is not taken, needing a digit after it."
  (let ((n (length text)))
    (while (and (< i n) (maf-editvars--digit-p (aref text i)))
      (setq i (1+ i)))
    (if (and (< i n) (eq (aref text i) ?#))
        ;; Radix: the "digits" after the # are alphanumeric.
        (progn
          (setq i (1+ i))
          (while (and (< i n)
                      (or (maf-editvars--alnum-p (aref text i))
                          (eq (aref text i) ?.)))
            (setq i (1+ i))))
      (when (and (< (1+ i) n)
                 (eq (aref text i) ?.)
                 (maf-editvars--digit-p (aref text (1+ i))))
        (setq i (1+ i))
        (while (and (< i n) (maf-editvars--digit-p (aref text i)))
          (setq i (1+ i))))
      (when (and (< i n) (memq (aref text i) '(?e ?E)))
        (let ((j (1+ i)))
          (when (and (< j n) (memq (aref text j) '(?+ ?-)))
            (setq j (1+ j)))
          (when (and (< j n) (maf-editvars--digit-p (aref text j)))
            (setq i (1+ j))
            (while (and (< i n) (maf-editvars--digit-p (aref text i)))
              (setq i (1+ i)))))))
    i))

(defun maf-editvars--pure-letters-p (s)
  "Non-nil when S is two or more letters and nothing else.
The runs this module splits. One letter is already one factor, and a
run with a digit in it (x1) is an identifier calc and the dialect
spell the same way, so neither needs quoting."
  (and (> (length s) 1) (string-match-p "\\`[A-Za-z]+\\'" s)))

(defun maf-editvars--scan (text)
  "TEXT as a list of tokens, each a cons of a kind and a string.

  raw     copied through untouched
  word    a run of two or more letters, to be split or quoted
  call    unused as a token; a name in front of `(' stays raw
  quoted  the name from a marked identifier, without its mark

The strings concatenate back to TEXT for `raw' and `word'; a `quoted'
token has lost its `maf-editvars-quote-char', which is the one place
the two directions are not symmetric.

The mark is recognised before anything else, so that a session under
a character calc reads as an operator still quotes with it — which is
the whole point of the setting. That is also why the character may
not be one that opens a run whose letters are not identifiers; see
`maf-editvars-quote-char-valid-p'."
  (let ((i 0) (n (length text)) (raw 0) (out '())
        (mark maf-editvars-quote-char))
    (cl-flet ((flush (to)
                (when (> to raw)
                  (push (cons 'raw (substring text raw to)) out))))
      (while (< i n)
        (let ((c (aref text i)))
          (cond
           ;; A marked name — one identifier, however many letters.
           ((and (eq c mark)
                 (< (1+ i) n)
                 (maf-editvars--letter-p (aref text (1+ i))))
            (let ((end (maf-editvars--word-end text (1+ i))))
              (flush i)
              (push (cons 'quoted (substring text (1+ i) end)) out)
              (setq i end raw end)))
           ;; Opaque runs: their letters are not identifiers.
           ((eq c ?\") (setq i (maf-editvars--string-end text i)))
           ((and (eq c ?<) (maf-editvars--date-end text i))
            (setq i (maf-editvars--date-end text i)))
           ((maf-editvars--digit-p c)
            (setq i (maf-editvars--number-end text i)))
           ((maf-editvars--letter-p c)
            (let* ((end (maf-editvars--word-end text i))
                   (s (substring text i end)))
              ;; A name directly in front of `(' is a call, and calls
              ;; are calc's own syntax in either dialect. Anything else
              ;; that is not a plain letter run stays raw too.
              (when (and (maf-editvars--pure-letters-p s)
                         (not (and (< end n) (eq (aref text end) ?\())))
                (flush i)
                (push (cons 'word s) out)
                (setq raw end))
              (setq i end)))
           (t (setq i (1+ i))))))
      (flush n))
    (nreverse out)))

;;; The two directions

(defun maf-editvars--call-follows-p (tokens)
  "Non-nil when TOKENS opens with an argument list.
What tells \\=\\xy(5) — the variable xy times 5 — from xy(5), the call.
A quoted name can never be the head of a call, so the parenthesis
after one is a factor, and the product has to be made explicit: calc
reads even `foo (5)', space and all, as a call."
  (let ((s (cdr (car tokens))))
    (and s (string-match-p "\\`[ \t]*(" s))))

(defun maf-editvars--split (text)
  "TEXT in this module's dialect, rewritten as calc input.
Letter runs become explicit products, and quoted names lose their
mark and are padded apart from their neighbours so that the
identifier survives the join: `2\\=\\cm' has to reach calc as `2 cm'
and not as `2cm'... which happens to read the same, where `\\=\\cm\\=\\cm'
would not."
  (let ((tokens (maf-editvars--scan text))
        (out '()))
    (while tokens
      (let ((tok (pop tokens)))
        (push (pcase (car tok)
                ('word (mapconcat #'string (string-to-list (cdr tok)) "*"))
                ('quoted
                 (if (maf-editvars--call-follows-p tokens)
                     (concat (cdr tok) "*")
                   (concat " " (cdr tok) " ")))
                (_ (cdr tok)))
              out)))
    (apply #'concat (nreverse out))))

(defun maf-editvars--quote-offsets (text)
  "Offsets into TEXT at which a mark quotes an identifier.
Quoting only ever inserts, never rewrites, so the whole of the
load-time translation can be expressed as these positions — which is
what lets the buffer version leave point where it was: a mark put in
ahead of point carries point along with the text it belongs to,
where replacing a line wholesale would strand it at the margin.

Offsets are in ascending order; insert from the end to keep the
earlier ones valid."
  (let ((i 0) (out '()))
    (dolist (tok (maf-editvars--scan text))
      (pcase (car tok)
        ('word (push i out) (setq i (+ i (length (cdr tok)))))
        ;; A quoted token's string has lost its mark, but the mark is
        ;; still there in TEXT.
        ('quoted (setq i (+ i 1 (length (cdr tok)))))
        (_ (setq i (+ i (length (cdr tok)))))))
    (nreverse out)))

(defun maf-editvars--quote (text)
  "TEXT in calc's syntax, rewritten into this module's dialect.
Every identifier that would otherwise split is quoted, so that text
loaded from the stack means the same thing after a round trip through
an edit session — including the parts of an entry the user never
touched, which `maf-edit-commit' reparses along with the rest as soon
as anything in that entry changes."
  (let ((out text)
        (mark (maf-editvars--quote-string)))
    (dolist (off (reverse (maf-editvars--quote-offsets text)))
      (setq out (concat (substring out 0 off) mark (substring out off))))
    out))

(defun maf-editvars--applicable-p ()
  "Non-nil when the dialect applies to the current buffer.
The Normal language only, and changing `maf-editvars-quote-char' does
not lift that: the dialect rests on juxtaposition meaning
multiplication, which is true of the Normal language and not of the
others — calc's Mathematica mode reads `sin x' as a function call.

A quoting character the scanner cannot work with also stands the
dialect down, rather than letting it mangle the buffer — see
`maf-editvars-quote-char-valid-p'."
  (and maf-use-editvars-mode
       (null calc-language)
       (maf-editvars-quote-char-valid-p)))

(defun maf-editvars-parse-text (text)
  "`maf-edit-parse-text-function' for the dialect.
Passes TEXT through untouched wherever the dialect does not apply, so
that the same global setting is harmless in a TeX-language buffer."
  (if (maf-editvars--applicable-p) (maf-editvars--split text) text))

(defun maf-editvars-quote-name (name)
  "NAME written so that an entry reads it as the one identifier it is.
Marked with `maf-editvars-quote-char' where the dialect applies and a
run of letters would otherwise split, and returned untouched
everywhere else — the dialect off, another language, a name calc and
the dialect already spell alike.

For anything that types a name into an entry on the user's behalf.
Text a person types they can quote themselves, and text loaded from
the stack goes through `maf-editvars--quote'; a key that writes `pi'
has neither route, and unquoted it would mean the product p i."
  (if (and (maf-editvars--applicable-p)
           (maf-editvars--pure-letters-p name))
      (concat (maf-editvars--quote-string) name)
    name))

;;; Rewriting a session's text on entry

(defun maf-editvars--quote-entry (o)
  "Rewrite entry overlay O's text into the dialect, line by line.
Per line rather than per entry: a multi-line entry is a matrix or a
vector whose layout is structural, and joining it into one line to
translate it would flatten that.

Marks are inserted in place rather than the line being replaced, so
that point — already restored to where the session should open —
travels with its own text instead of collapsing to the start of the
entry. Plain `insert', so that nothing inherits the text properties
marking the level-number prefix machine-owned."
  (let ((mark (maf-editvars--quote-string)))
    (save-excursion
      (goto-char (overlay-start o))
      (while (< (point) (overlay-end o))
        (let* ((bol (line-beginning-position))
               (beg (+ bol (maf-edit--leading-prefix-run bol)))
               (end (min (line-end-position) (overlay-end o))))
          (when (< beg end)
            (dolist (off (reverse (maf-editvars--quote-offsets
                                   (buffer-substring-no-properties beg end))))
              (save-excursion
                (goto-char (+ beg off))
                (insert mark)))))
        (forward-line 1)))))

(defun maf-editvars--enter ()
  "Rewrite the whole session into the dialect, on `maf-edit-mode-on-hook'.
Runs with maf-edit's own repair machinery inhibited, as its internal
edits do, and re-records each entry's original text afterwards: the
untouched-entry test in `maf-edit-commit' compares against that
string, so it has to be the dialect text the user is now looking at,
not calc's rendering of a moment ago."
  (when (maf-editvars--applicable-p)
    (let ((maf-edit--inhibit t)
          (inhibit-modification-hooks t)
          (inhibit-read-only t))
      (dolist (o (maf-edit--overlays))
        (maf-editvars--quote-entry o))
      (dolist (o (maf-edit--overlays))
        (overlay-put o 'maf-edit-text (maf-edit--entry-text o))))
    (maf-editvars--fontify)
    (add-hook 'post-command-hook #'maf-editvars--fontify nil t)))

(defun maf-editvars--exit ()
  "Drop the dialect's display state, on `maf-edit-mode-off-hook'."
  (remove-hook 'post-command-hook #'maf-editvars--fontify t)
  (maf-editvars--unfontify))

;;; Highlighting

(defun maf-editvars--unit-p (name)
  "Non-nil when NAME is a unit calc's table knows, prefixes included.
Asked of calc rather than answered from a list here, so that a unit
the user has defined (\\[calc-define-unit]) counts too."
  (and (require 'calc-units nil t)
       (condition-case nil
           (and (math-check-unit-name
                 (list 'var (intern name) (intern (concat "var-" name))))
                t)
         (error nil))))

(defun maf-editvars--unfontify ()
  "Remove this module's highlighting from the buffer."
  (remove-overlays (point-min) (point-max) 'maf-editvars t))

(defun maf-editvars--fontify ()
  "Highlight the quoted identifiers in every entry of the session.
Rebuilt from scratch on each pass: the spans are short, there are as
many as there are entries, and a session's text changes under nearly
every key. Overlays rather than text properties, so that nothing this
adds can reach `maf-edit--entry-text' or the undo list."
  (when (and maf-edit-mode (maf-editvars--applicable-p))
    (maf-editvars--unfontify)
    (save-excursion
      (dolist (o (maf-edit--overlays))
        (goto-char (overlay-start o))
        (while (re-search-forward (concat (regexp-quote
                                           (maf-editvars--quote-string))
                                          "\\([A-Za-z][A-Za-z0-9]*\\)")
                                  (overlay-end o) t)
          (let ((ov (make-overlay (match-beginning 0) (match-end 0))))
            (overlay-put ov 'maf-editvars t)
            (overlay-put ov 'evaporate t)
            (overlay-put ov 'face
                         (if (maf-editvars--unit-p (match-string 1))
                             'maf-editvars-unit
                           'maf-editvars-quoted))))))))

;;; The module

(define-minor-mode maf-use-editvars-mode
  "Global minor mode reading maf-edit entries as handwritten algebra.
Enabled, and in a Normal-language calc buffer, a run of letters typed
in a maf-edit session is a product of one-letter factors — 2xy is
2*x*y — and a multi-letter identifier is written with a mark in front
of it: \\=\\cm, \\=\\pi, \\=\\foo. A name in front of `(' is still a function
call, so xy(5) calls xy while \\=\\xy(5) multiplies by 5.

The rule applies to every letter run alike, with no exemption for
names calc happens to know: \\=\\pi is quoted exactly as \\=\\foo is. Quoted
names are coloured — gold for one the unit table recognises — but the
colour only reports what the mark already decided.

The mark is `maf-editvars-quote-char'. It defaults to `\\=\\', which calc
also reads as integer division; a session that needs both should set
it to one of the characters calc leaves unread.

The text a session starts with is rewritten into the dialect as the
session opens, so an expression loaded from the stack survives being
edited and committed. Disabled, and in every language but Normal,
entries are read as plain calc input and nothing here applies.

This is the `maf-editvars' module (see `maf-modules'), one of the
defaults. It affects maf-edit sessions only — the stack, the trail,
and algebraic entry at calc's own prompt are untouched."
  :global t
  :group 'maf
  (if maf-use-editvars-mode
      (progn
        (setq maf-edit-parse-text-function #'maf-editvars-parse-text)
        (add-hook 'maf-edit-mode-on-hook #'maf-editvars--enter)
        (add-hook 'maf-edit-mode-off-hook #'maf-editvars--exit))
    (setq maf-edit-parse-text-function #'identity)
    (remove-hook 'maf-edit-mode-on-hook #'maf-editvars--enter)
    (remove-hook 'maf-edit-mode-off-hook #'maf-editvars--exit)))

;; Register with the module system when it is present; the mode above
;; works on its own without it.
(when (require 'maf-module nil t)
  (maf-register-module 'maf-editvars #'maf-use-editvars-mode
                       "Read maf-edit text the way algebra is written by hand.

Calc reads a run of letters as one variable, so xy is a single name.
Here every run splits into factors — 2xy is 2*x*y — and a backslash
quotes one identifier whole: \\cm is the unit, \\xy the variable. An
input dialect for edit sessions; the stack keeps calc's own syntax."))

(provide 'maf-editvars)
