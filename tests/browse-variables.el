;;; Tests for maf-browse-variables -- the annotated variable recall.
;;
;; The command reads its choice from `completing-read'. `maf-with-choice'
;; stands in for the picking and keeps the two pieces the prompt would
;; otherwise take to the grave: the candidates it offered, and the
;; annotation function that decides what is shown beside each name.

(defvar mafstep--annotate nil "Annotation function the last prompt was given.")
(defvar mafstep--candidates nil "Candidates the last prompt offered, in order.")

(defmacro maf-with-choice (name &rest body)
  "Run BODY with the variable prompt answered by NAME.
NAME is the name without the `var-' prefix, exactly as the command's
own `completing-read' would have returned it."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'completing-read)
              (lambda (_prompt table &rest _)
                (setq mafstep--annotate (plist-get completion-extra-properties
                                                   :annotation-function)
                      mafstep--candidates (all-completions "" table))
                ,name)))
     ,@body))

(defun mafstep--annotation (name)
  "The last prompt's annotation for NAME, with the padding trimmed off."
  (string-trim (funcall mafstep--annotate name)))

(maf-step

  ;; --- The listing ---

  ;; Calc's constants are on the list. Not hiding them is the
  ;; difference from the legacy command, which excluded them all.
  (let ((names (maf--variable-names)))
    (cl-assert (member "pi" names))
    (cl-assert (member "e" names))
    (cl-assert (member "gamma" names)))

  ;; A stored variable joins them; unsetting it takes it back off. A
  ;; `var-' symbol bound to nil is unset as far as calc is concerned.
  (setq var-mafTest (math-read-expr "a + 1"))
  (cl-assert (member "mafTest" (maf--variable-names)))
  (setq var-mafTest nil)
  (cl-assert (not (member "mafTest" (maf--variable-names))))
  (makunbound 'var-mafTest)

  ;; --- The exclusions ---

  ;; The three defaults: the formula library, which maf-formulas has
  ;; its own browser for; calc's rewrite-rule sets, which calc reads
  ;; where they sit rather than off a stack; and its settings.
  (setq var-eq-mafTest (math-read-expr "a = b"))
  (setq var-mafTestRules (math-read-expr "[a := b]"))
  (cl-assert (not (member "eq-mafTest" (maf--variable-names))))
  (cl-assert (not (member "mafTestRules" (maf--variable-names))))
  (cl-assert (not (member "CommuteRules" (maf--variable-names))))
  (cl-assert (not (member "Modes" (maf--variable-names))))
  (cl-assert (not (member "Decls" (maf--variable-names))))
  (cl-assert (not (member "Holidays" (maf--variable-names))))

  ;; The list is the option's, not the command's: emptying it offers
  ;; everything, and a regexp of one's own excludes by any rule.
  (let ((maf-browse-variables-exclude nil))
    (cl-assert (member "eq-mafTest" (maf--variable-names)))
    (cl-assert (member "CommuteRules" (maf--variable-names)))
    (cl-assert (member "Modes" (maf--variable-names))))
  (let ((maf-browse-variables-exclude '("\\`maf")))
    (cl-assert (not (member "mafTestRules" (maf--variable-names))))
    (cl-assert (member "eq-mafTest" (maf--variable-names)))
    (cl-assert (member "pi" (maf--variable-names))))
  (makunbound 'var-eq-mafTest)
  (makunbound 'var-mafTestRules)

  ;; --- The grouping ---

  ;; The user's names come first, calc's after, each group
  ;; alphabetical. A name calc does not claim is the user's, whatever
  ;; it looks like.
  (setq var-mafTest (math-read-expr "a + 1"))
  (setq var-aardvark 1)
  (let* ((names (maf--variable-names))
         (mine (seq-take-while (lambda (n) (not (maf--calc-own-variable-p n)))
                               names))
         (calcs (seq-drop names (length mine))))
    (cl-assert (member "aardvark" mine))
    (cl-assert (member "mafTest" mine))
    (cl-assert (equal mine (sort (copy-sequence mine) #'string<)))
    (cl-assert (seq-every-p #'maf--calc-own-variable-p calcs))
    (cl-assert (equal calcs (sort (copy-sequence calcs) #'string<)))
    ;; mafTest sorts after e, so its coming first is the grouping and
    ;; not one alphabetical run that happens to look like it.
    (cl-assert (member "e" calcs))
    (cl-assert (< (seq-position names "mafTest") (seq-position names "e")))
    (cl-assert (not (equal names (sort (copy-sequence names) #'string<)))))
  (makunbound 'var-aardvark)

  ;; The quick registers are the user's, though calc defines them: what
  ;; they hold is what was stored in them.
  (cl-assert (not (maf--calc-own-variable-p "q1")))
  (cl-assert (maf--calc-own-variable-p "pi"))
  (cl-assert (maf--calc-own-variable-p "EvalRules"))
  (makunbound 'var-mafTest)

  ;; --- The annotations ---

  ;; A special constant is shown as the number recalling it lands, not
  ;; as the (special-const (math-pi)) form the symbol actually holds.
  (cl-assert (string-prefix-p "3.14159" (maf--variable-value-string "pi")))
  (cl-assert (string-prefix-p "2.71828" (maf--variable-value-string "e")))
  (cl-assert (string= (maf--variable-value-string "Decls") "[]"))

  ;; Rendering is independent of the listing: a name the option keeps
  ;; out still renders if asked, and a rewrite-rule set renders parsed
  ;; — until first use the symbol holds the function that builds it,
  ;; which would otherwise show as the bare name `calc-CommuteRules'.
  (let ((str (maf--variable-value-string "CommuteRules")))
    (cl-assert (string-prefix-p "[" str))
    (cl-assert (not (string-match-p "calc-CommuteRules" str))))

  ;; One line always, whatever the value's shape: no newline survives,
  ;; and neither does the padding a multi-line composition came with.
  (setq var-mafTest (math-read-expr "[[1, 2], [3, 4]]"))
  (cl-assert (string= (maf--variable-value-string "mafTest") "[[1, 2], [3, 4]]"))
  (cl-assert (not (string-match-p "\n" (maf--variable-value-string "mafTest"))))

  ;; Contents that no longer parse annotate as nothing rather than
  ;; signal; the variable stays on the list, and recalling it is what
  ;; reports the problem.
  (setq var-mafTest "1 +* 2")
  (cl-assert (member "mafTest" (maf--variable-names)))
  (cl-assert (null (maf--variable-value-string "mafTest")))
  (makunbound 'var-mafTest)

  ;; --- The prompt ---

  ;; The candidates the prompt offers are the listing plus the divider,
  ;; sitting on the boundary between the two groups.
  (setq var-mafTest (math-read-expr "a + 1"))
  (maf-with-choice "mafTest" (maf-browse-variables))
  (let* ((names (maf--variable-names))
         (rule (seq-find (lambda (c) (not (member c names)))
                         mafstep--candidates))
         (i (seq-position mafstep--candidates rule)))
    (cl-assert (= (length mafstep--candidates) (1+ (length names))))
    (cl-assert (equal (remove rule mafstep--candidates) names))
    (cl-assert (string-match-p "\\`─+\\'" rule))
    (cl-assert (not (maf--calc-own-variable-p (nth (1- i) mafstep--candidates))))
    (cl-assert (maf--calc-own-variable-p (nth (1+ i) mafstep--candidates)))
    ;; The divider is labelled, not annotated with a value, and
    ;; choosing it is refused rather than recalled.
    (cl-assert (string= (mafstep--annotation rule) "calc vars"))
    (cl-assert (eq 'error (condition-case nil
                              (maf-with-choice rule (maf-browse-variables))
                            (error 'error)))))

  ;; With one group empty there is no boundary, so no divider: every
  ;; candidate is a name.
  (let ((maf--calc-own-variables nil))
    (maf-with-choice "mafTest" (maf-browse-variables))
    (cl-assert (equal mafstep--candidates (maf--variable-names))))
  (calc-pop (calc-stack-size))

  ;; The annotation function shows each name's value beside it.
  (maf-with-choice "mafTest" (maf-browse-variables))
  (cl-assert (string= (mafstep--annotation "mafTest") "a + 1"))
  (cl-assert (string-prefix-p "3.14159" (mafstep--annotation "pi")))

  ;; --- The recall ---

  ;; The chosen variable is pushed as a new entry.
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a + 1"))
  (calc-pop (calc-stack-size))

  ;; A value too wide for the line is truncated, not wrapped: the name
  ;; column plus the annotation together stay within the frame.
  (setq var-mafWide
        (math-read-expr (concat "[" (mapconcat #'number-to-string
                                               (number-sequence 1 400) ",")
                                "]")))
  (cl-assert (> (length (maf--variable-value-string "mafWide")) (frame-width)))
  (maf-with-choice "mafTest" (maf-browse-variables))
  (cl-assert (<= (length (funcall mafstep--annotate "mafWide")) (frame-width)))
  (makunbound 'var-mafWide)
  (calc-pop (calc-stack-size))

  ;; Simplification is off, so what was stored is what lands. Calc's
  ;; own s r would give 2 x here.
  (setq var-mafTest (math-read-expr "x + x"))
  (maf-with-choice "mafTest" (maf-browse-variables))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + x"))
  (calc-pop (calc-stack-size))

  ;; Recalling a constant lands its value, the same as calc's s r pi.
  (maf-with-choice "pi" (maf-browse-variables))
  (cl-assert (string-prefix-p "3.14159" (math-format-value (calc-top 1 'full))))
  (calc-pop (calc-stack-size))

  ;; --- Point ---

  ;; The push parks point at home, as calc's own recall does, so the
  ;; spot the user was on goes on the mark ring to come back to.
  (setq var-mafTest (math-read-expr "a + 1"))
  (maf-push "11")
  (maf-push "22")
  (goto-char (point-min))
  (let ((origin (point)))
    (maf-with-choice "mafTest" (maf-browse-variables))
    (cl-assert (maf--at-home-p))
    (cl-assert (= (marker-position (mark-marker)) origin)))
  (calc-pop (calc-stack-size))

  ;; Recalling from home leaves the mark alone: there is no spot to
  ;; come back to, and the previous one should survive.
  (let ((before (marker-position (mark-marker))))
    (maf-with-choice "mafTest" (maf-browse-variables))
    (cl-assert (= (marker-position (mark-marker)) before)))
  (calc-pop (calc-stack-size))

  ;; A name with no value behind it is not a candidate, and choosing it
  ;; anyway (which the require-match prompt would not allow) is calc's
  ;; error to report.
  (makunbound 'var-mafTest)
  (cl-assert (not (member "mafTest" (maf--variable-names))))
  (cl-assert (eq 'error
                 (condition-case nil
                     (maf-with-choice "mafTest" (maf-browse-variables))
                   (error 'error))))
  (cl-assert (= (calc-stack-size) 0)))
