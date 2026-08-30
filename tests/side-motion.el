;; The paren keys cross a relation: `(' to the whole left side
;; (`maf-goto-left-side'), `)' to the whole right
;; (`maf-goto-right-side'); C-o crosses blind, to whichever side point
;; is not in (`maf-goto-other-side'). Every assertion below is about
;; where point lands, because point is the whole of maf's targeting: a
;; landing is only right if resolve names the side the motion
;; advertised there, which is what `maf-test--part-at-point' reads
;; back.
;;
;; Either key pressed from the side it already names crosses to the
;; other one, so a relation can be walked on one key; the cycle turns
;; on where point stands, not on which key put it there.
;;
;; The relation is the innermost one point sits in, so the checks run
;; over a bare equation, an ordered relation, and an equation nested in
;; a vector of them. Home is the one place the keys mean something
;; else: there is no entry to move within, and they keep the edit
;; module's blank-vector gesture there.

(defun maf-test--flat (expr)
  "EXPR in flat notation, with the selection machinery's encasing gone.
Flat rather than `math-format-value' so that one spelling serves every
step below: display notation is what the language renders, which for
the Big-language entry here runs over several lines."
  (math-format-flat-expr (maf--strip-encasing expr) 0))

(defun maf-test--part-at-point ()
  "The sub-formula point names, in flat notation."
  (let ((m (calc-locate-cursor-element (point))))
    (calc-prepare-selection m)
    (maf-test--flat (calc-find-selected-part))))

(maf-defcmd maf-square (expr _arg commit)
  "Square command."
  :arity unary
  :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-step
  ;; From a term on one side, one press names the whole other side —
  ;; the largest formula there is on it, which the climb out
  ;; (`maf-up-expression') would reach a level at a time. The landing
  ;; glyph is the side's own first: here the + each sum renders itself
  ;; by.
  (maf-push "6 x + 12 = 18 y + 6")
  (progn (calc-cursor-stack-index 1)
         (search-forward "y" (line-end-position))
         (backward-char 1))
  (cl-assert (string= (maf-test--part-at-point) "y"))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (cl-assert (eq (char-after) ?+))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  (cl-assert (eq (char-after) ?+))
  ;; Pressed again from the side it already names, the motion crosses
  ;; to the other side rather than standing still: the side is as far
  ;; out as that end goes, so one key walks the whole relation.
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  ;; `(' cycles the same way, and off a landing `)' made: the test is
  ;; where point stands, not the key that put it there.
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  ;; And point on the relation's own operator — where it names the
  ;; whole entry from inside the formula — still has two sides to go to.
  (progn (calc-cursor-stack-index 1)
         (search-forward "=" (line-end-position))
         (backward-char 1))
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12 = 18 * y + 6"))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (calc-pop (calc-stack-size))

  ;; The crossing names no side: from wherever point sits it lands on
  ;; the whole side point is not in, and pressed again it rocks back —
  ;; the blind way into the same walk.
  (maf-push "6 x + 12 = 18 y + 6")
  (progn (calc-cursor-stack-index 1)
         (search-forward "y" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-goto-other-side)
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  (cl-assert (eq (char-after) ?+))
  (call-interactively 'maf-goto-other-side)
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  (call-interactively 'maf-goto-other-side)
  (cl-assert (string= (maf-test--part-at-point) "6 * x + 12"))
  ;; From the relation's own operator, or the margins where point
  ;; names the whole entry, point is in neither side and the right one
  ;; is the landing.
  (progn (calc-cursor-stack-index 1)
         (search-forward "=" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-goto-other-side)
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  (progn (calc-cursor-stack-index 1) (beginning-of-line))
  (call-interactively 'maf-goto-other-side)
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  ;; No relation: the crossing signals like the named motions.
  (calc-pop (calc-stack-size))
  (maf-push "(a + b) (2 c - d)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "c" (line-end-position))
         (backward-char 1))
  (setq side-test-pos (point))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-goto-other-side) :ok)
                          (user-error :error))))
  (cl-assert (= (point) side-test-pos))
  (calc-pop (calc-stack-size))

  ;; All six relations, not just =; and a side that is a bare atom is
  ;; named by the atom itself.
  (maf-push "2 x - 3 < 7")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "7"))
  (cl-assert (eq (char-after) ?7))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "2 * x - 3"))
  (cl-assert (eq (char-after) ?-))
  (calc-pop (calc-stack-size))

  ;; The margins name the whole entry, and the entry's own relation is
  ;; the one crossed from there — so the keys work from the line-number
  ;; prefix and from the end of the line, not only from a term.
  (maf-push "y = (x + 3)^2")
  (progn (calc-cursor-stack-index 1) (beginning-of-line))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "y"))
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "(x + 3)^2"))
  ;; The power's parens belong to the term inside it, so the side's own
  ;; first glyph is the ^.
  (cl-assert (eq (char-after) ?^))
  (calc-pop (calc-stack-size))

  ;; The innermost relation, not the outermost formula: a term inside
  ;; one element of a vector of equations finds the equation it sits
  ;; in, and the vector around it is never the subject.
  (maf-push "[h = 0, p = -4, k = 0]")
  (progn (calc-cursor-stack-index 1)
         (search-forward "4" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "p"))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "-4"))
  ;; And the cycle crosses that same inner relation, not the vector
  ;; around it: the element's own two sides are what it alternates.
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "p"))
  ;; On the vector's own bracket there is no relation above point at
  ;; all — the vector is not one — so the motion signals and point
  ;; stands.
  (progn (calc-cursor-stack-index 1)
         (search-forward "[" (line-end-position))
         (backward-char 1))
  (setq side-test-pos (point))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-goto-left-side) :ok)
                          (user-error :error))))
  (cl-assert (= (point) side-test-pos))
  (calc-pop (calc-stack-size))

  ;; An entry that holds no relation has no side to reach: both keys
  ;; signal and leave point where it was.
  (maf-push "(a + b) (2 c - d)")
  (progn (calc-cursor-stack-index 1)
         (search-forward "c" (line-end-position))
         (backward-char 1))
  (setq side-test-pos (point))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-goto-left-side) :ok)
                          (user-error :error))))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-goto-right-side) :ok)
                          (user-error :error))))
  (cl-assert (= (point) side-test-pos))
  (calc-pop (calc-stack-size))

  ;; The promise the motion makes: what point names after it is what
  ;; the next command acts on. The square takes the whole left side —
  ;; not the term point started on, and not the entry.
  (maf-push "x + 1 = y")
  (progn (calc-cursor-stack-index 1)
         (search-forward "y" (line-end-position))
         (backward-char 1))
  (call-interactively 'maf-goto-left-side)
  (call-interactively 'maf-square)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "(x + 1)^2 = y"))
  (calc-pop (calc-stack-size))

  ;; With a selection up it is the selection, not point, that a command
  ;; resolves to — so the selection crosses along and stays what the
  ;; next command would act on.
  (maf-push "6 x + 12 = 18 y + 6")
  (progn (calc-cursor-stack-index 1)
         (search-forward "x" (line-end-position))
         (backward-char 1)
         (call-interactively 'calc-select-here))
  (cl-assert (string= (maf-test--flat (maf--sel-effective-expr)) "x"))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--flat (maf--sel-effective-expr)) "18 * y + 6"))
  ;; Point kept up with it: both name the same node.
  (cl-assert (string= (maf-test--part-at-point) "18 * y + 6"))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--flat (maf--sel-effective-expr)) "6 * x + 12"))
  (calc-clear-selections)
  (calc-pop (calc-stack-size))

  ;; Big language prints no parens and draws an entry over several
  ;; lines, so there is nothing for a text-scanning motion to walk. The
  ;; sides are still found: this left side's own glyph is its fraction
  ;; bar, on a line of its own between the numerator and denominator.
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (eq calc-language 'big))
  (maf-push "(a+b)/(c+d) = e")
  (progn (calc-cursor-stack-index 1)
         (search-forward "b" nil t)
         (backward-char 1))
  (call-interactively 'maf-goto-left-side)
  (cl-assert (string= (maf-test--part-at-point) "(a + b) / (c + d)"))
  (cl-assert (eq (char-after) ?-))
  (call-interactively 'maf-goto-right-side)
  (cl-assert (string= (maf-test--part-at-point) "e"))
  (calc-pop (calc-stack-size))
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (null calc-language))

  ;; Home is the one place the keys are not the motion: there is no
  ;; entry at point to move within, so they keep the meaning the edit
  ;; module gives them — a blank vector entry opened at the bottom.
  (maf-push "y = 2 x")
  (progn (calc-cursor-stack-index 0) (skip-chars-forward " "))
  (call-interactively 'maf-goto-right-side)
  (cl-assert maf-edit-mode)
  (cl-assert (eq (char-before) ?\[))
  (cl-assert (looking-at-p "\\]$"))
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 1))

  ;; The crossing's own home meaning is the one its key has always had
  ;; there: a fresh entry opened at the bottom
  ;; (`maf-edit-add-entry-above').
  (progn (calc-cursor-stack-index 0) (skip-chars-forward " "))
  (call-interactively 'maf-goto-other-side)
  (cl-assert maf-edit-mode)
  (cl-assert (eolp))
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (= (calc-stack-size) 1))

  ;; With that module off there is nothing to fall back to, and home
  ;; signals like any other place with no relation to cross.
  (setq side-test-edit maf-use-edit-mode)
  (maf-use-edit-mode -1)
  (progn (calc-cursor-stack-index 0) (skip-chars-forward " "))
  (cl-assert (eq :error (condition-case nil
                            (progn (call-interactively 'maf-goto-left-side) :ok)
                          (user-error :error))))
  (cl-assert (not maf-edit-mode))
  (when side-test-edit (maf-use-edit-mode 1))
  (cl-assert (eq (and maf-use-edit-mode t) (and side-test-edit t)))
  (calc-pop (calc-stack-size)))
