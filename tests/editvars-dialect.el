;; The maf-editvars input dialect: inside a maf-edit session a run of
;; letters is a product of one-letter factors (2xy is 2*x*y) and a
;; multi-letter identifier is written with a backslash (\cm). A name in
;; front of `(' is still a call, so xy(5) calls xy while \xy(5)
;; multiplies. A step passes when it raises no error.
;;
;; The contract has two halves that must agree. Typed text is
;; translated at commit; text loaded from the stack is translated the
;; other way as the session opens, so an expression edited in one place
;; keeps its meaning everywhere else — `maf-edit-commit' reparses a
;; whole entry as soon as any part of it changes, and an unquoted foo
;; left sitting in one would otherwise split.

(maf-step
  ;; The module is opt-in, so the test turns it on and the last step
  ;; puts it back. Its two directions are plain string functions and
  ;; are checked first, without a session in the way.
  (progn (setq maf-step--editvars-was maf-use-editvars-mode)
         (maf-use-editvars-mode 1)
         nil)
  (cl-assert (eq maf-edit-parse-text-function 'maf-editvars-parse-text))

  ;; The table from the design, read through calc so the assertion is
  ;; about meaning rather than about spelling.
  (progn
    (dolist (case '(("2xy"             . "2 x y")
                    ("2\\cm"           . "2 cm")
                    ("\\foo+x"         . "foo + x")
                    ("xy(5)"           . "xy(5)")
                    ("\\xy(5)"         . "xy 5")
                    ("map(\\sin,[1,2])" . "map(sin, [1, 2])")
                    ("abc"             . "a b c")))
      (cl-assert (string= (math-format-value
                           (math-read-expr (maf-editvars--split (car case)))
                           1000)
                          (cdr case))
                 t "%s" (car case)))
    nil)

  ;; The rule is uniform: no name is exempt for being one calc knows.
  ;; pi splits like anything else, and is quoted like anything else.
  (cl-assert (equal (math-read-expr (maf-editvars--split "pi"))
                    (math-read-expr "p*i")))
  (cl-assert (equal (math-read-expr (maf-editvars--split "\\pi"))
                    (math-read-expr "pi")))

  ;; Calc's own syntax that happens to contain letters is not touched:
  ;; a float exponent, a radix form, a name with a digit in it.
  (cl-assert (equal (math-read-expr (maf-editvars--split "1e5")) (math-read-expr "1e5")))
  (cl-assert (equal (math-read-expr (maf-editvars--split "16#ff")) 255))
  (cl-assert (equal (math-read-expr (maf-editvars--split "x1")) (math-read-expr "x1")))
  (cl-assert (equal (math-read-expr (maf-editvars--split "xy1")) (math-read-expr "xy1")))
  ;; `<' is the comparison operator, not the opening of a date form.
  (cl-assert (equal (math-read-expr (maf-editvars--split "ab<c"))
                    (math-read-expr "a*b<c")))

  ;; Quoting is the inverse: rendering any expression, quoting it, and
  ;; splitting it back gives the expression again. This is the property
  ;; the round trip through a session depends on.
  (progn
    (dolist (s '("foo+1" "cm*x" "2*pi*r" "xy" "sin(x)" "map(sin,[1,2])"
                 "x1+xy1" "1.5e3*cm" "sqrt(2)+alpha" "[cm,foo]" "a<b"
                 "x_1+foo" "cm*(x+1)" "foo(bar)"))
      (let ((v (math-read-expr s)))
        (cl-assert (equal v (math-read-expr
                             (maf-editvars--split
                              (maf-editvars--quote
                               (math-format-value v 1000)))))
                   t "%s" s)))
    nil)

  ;; A session opens on the dialect, not on calc's rendering: the
  ;; identifier the stack holds is shown quoted.
  (calc-pop (calc-stack-size))
  (maf-push "foo + 1")
  (call-interactively 'maf-edit)
  (cl-assert (string-match-p "\\\\foo \\+ 1"
                             (buffer-substring-no-properties (point-min) (point-max))))

  ;; An entry nobody touched still compares equal to what the session
  ;; recorded, so it keeps its value object and is never reparsed.
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full) 1000) "foo + 1"))

  ;; The half that fails without the load-time rewrite. Editing one end
  ;; of an entry reparses all of it, so the untouched foo passes through
  ;; the splitter — quoted, it survives; unquoted it would commit as
  ;; f*o*o.
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (call-interactively 'maf-edit)
  (progn (execute-kbd-macro "0") nil)     ; \foo + 1 => \foo + 10
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full) 1000) "foo + 10"))
  (calc-pop (calc-stack-size))

  ;; Freshly typed text takes the dialect: juxtaposed letters are
  ;; factors, and a quoted name is one variable.
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "5xy") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full) 1000) "5 x y"))
  (calc-pop (calc-stack-size))

  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "2\\cm") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full) 1000) "2 cm"))

  ;; Gold is commentary. The overlay says the quoted name is one the
  ;; unit table knows; nothing about the value above depended on it.
  (cl-assert (maf-editvars--unit-p "cm"))
  (cl-assert (maf-editvars--unit-p "km"))     ; prefixes count
  (cl-assert (not (maf-editvars--unit-p "foo")))
  (calc-pop (calc-stack-size))

  ;; A session paints the quoted spans, and takes the overlays back out
  ;; when it ends.
  (maf-push "foo + cm")
  (call-interactively 'maf-edit)
  (progn (setq maf-step--ovs
               (seq-filter (lambda (o) (overlay-get o 'maf-editvars))
                           (overlays-in (point-min) (point-max))))
         nil)
  (cl-assert (= 2 (length maf-step--ovs)))
  (cl-assert (equal (sort (mapcar (lambda (o) (overlay-get o 'face)) maf-step--ovs)
                          #'string<)
                    '(maf-editvars-quoted maf-editvars-unit)))
  (call-interactively 'maf-edit-discard)
  (cl-assert (null (seq-filter (lambda (o) (overlay-get o 'maf-editvars))
                               (overlays-in (point-min) (point-max)))))
  (calc-pop (calc-stack-size))

  ;; The mark is configurable, `\' being only the default — and it has
  ;; to be, since calc reads `\' as integer division: 5\b is idiv(5, b)
  ;; to calc and the quoted name b to the dialect. Under `~', which
  ;; calc does not read at all, the same session leaves that alone.
  (progn (setq maf-step--editvars-char maf-editvars-quote-char
               maf-editvars-quote-char ?~)
         nil)
  (cl-assert (equal (math-read-expr (maf-editvars--split "2~cm"))
                    (math-read-expr "2 cm")))
  (cl-assert (equal (math-read-expr (maf-editvars--split "2xy"))
                    (math-read-expr "2 x y")))
  ;; The old mark is now ordinary text, and reaches calc as the
  ;; operator it is.
  (cl-assert (equal (math-read-expr (maf-editvars--split "5\\b"))
                    (math-read-expr "5\\b")))
  ;; Quoting follows the setting, both as a string and in the buffer.
  (cl-assert (string= (maf-editvars--quote "foo + 1") "~foo + 1"))
  (calc-pop (calc-stack-size))
  (maf-push "foo + 1")
  (call-interactively 'maf-edit)
  (cl-assert (string-match-p "~foo \\+ 1"
                             (buffer-substring-no-properties (point-min) (point-max))))
  ;; And so does the highlighting, which builds its pattern from it.
  (cl-assert (= 1 (length (seq-filter (lambda (o) (overlay-get o 'maf-editvars))
                                      (overlays-in (point-min) (point-max))))))
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full) 1000) "foo + 1"))
  (calc-pop (calc-stack-size))

  ;; A character the scanner cannot tell from a name, or one that opens
  ;; a run whose letters are not identifiers, is refused — and the
  ;; dialect stands down rather than mangling the buffer.
  (cl-assert (not (maf-editvars-quote-char-valid-p ?x)))
  (cl-assert (not (maf-editvars-quote-char-valid-p ?5)))
  (cl-assert (not (maf-editvars-quote-char-valid-p ?\")))
  (cl-assert (not (maf-editvars-quote-char-valid-p ?<)))
  (cl-assert (maf-editvars-quote-char-valid-p ?@))
  (progn (setq maf-editvars-quote-char ?x) nil)
  (cl-assert (not (maf-editvars--applicable-p)))
  (cl-assert (string= (maf-editvars-parse-text "2xy") "2xy"))
  (progn (setq maf-editvars-quote-char maf-step--editvars-char) nil)
  (cl-assert (maf-editvars--applicable-p))

  ;; The dialect stands down in every language but Normal: the text
  ;; reaches the parser as written.
  (progn (calc-set-language 'tex) nil)
  (cl-assert (not (maf-editvars--applicable-p)))
  (cl-assert (string= (maf-editvars-parse-text "2xy") "2xy"))
  (progn (calc-set-language nil) nil)

  ;; Why that restriction is not about the mark, and does not lift when
  ;; the mark changes. The dialect rests on juxtaposition meaning
  ;; multiplication, which is a fact about the Normal language: calc's
  ;; Mathematica mode renders a call as `sin x' and groups 2xy the
  ;; other way, so the same text means something else there.
  (progn (calc-set-language 'math) nil)
  (cl-assert (string= (math-format-value (math-read-expr "sin(x)") 1000) "sin x"))
  (cl-assert (equal (math-read-expr "2x*y")
                    (math-read-expr "(2*x)*y")))
  (progn (calc-set-language nil) nil)
  (cl-assert (equal (math-read-expr "2x*y")
                    (math-read-expr "2*(x*y)")))
  ;; And two more languages calc itself round-trips cleanly, where this
  ;; module would not: C spells pi with an underscore whose PI would
  ;; split, and TeX writes a product with a word the default mark reads
  ;; as a quoted name.
  (progn (calc-set-language 'c) nil)
  (cl-assert (string-match-p "M_PI" (math-format-value (math-read-expr "pi") 1000)))
  (progn (calc-set-language 'tex) nil)
  (cl-assert (string-match-p "\\\\times"
                             (math-format-value (math-read-expr "cm*(x+1)") 1000)))
  (progn (calc-set-language nil) nil)
  (cl-assert (maf-editvars--applicable-p))

  ;; Off, entries are plain calc input again and the extension point is
  ;; back to its default — the module leaves nothing behind.
  (progn (maf-use-editvars-mode -1) nil)
  (cl-assert (eq maf-edit-parse-text-function 'identity))
  (cl-assert (string= (maf-editvars-parse-text "2xy") "2xy"))
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "xy") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full) 1000) "xy"))
  (calc-pop (calc-stack-size))

  ;; Restore whatever the module was before the test ran.
  (progn (maf-use-editvars-mode (if maf-step--editvars-was 1 -1)) nil))
