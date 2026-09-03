;; The module details (? in *maf-modules*, `maf-module--details') carry
;; a Configuration section: the module's own defcustoms with their live
;; values, found by the module's name prefix or declared on the
;; `maf-module-options' property when they do not share it.

(defvar maf-module-test--samples nil
  "maf-plot-samples on entry, restored at the end.")

(maf-step
  ;; Found by prefix, sorted, and only the module's own: the mode's
  ;; hook is customizable too and is left out.
  (cl-assert (memq 'maf-plot-samples (maf-module--options 'maf-plot)))
  (cl-assert (memq 'maf-plot-gnuplot-program (maf-module--options 'maf-plot)))
  (cl-assert (not (seq-some (lambda (s) (string-suffix-p "-hook" (symbol-name s)))
                            (maf-module--options 'maf-plot))))
  (cl-assert (let ((names (mapcar #'symbol-name (maf-module--options 'maf-plot))))
               (equal names (sort (copy-sequence names) #'string<))))
  ;; Declared by property where the prefix cannot find them.
  (cl-assert (equal (maf-module--options 'maf-persist)
                    '(maf-stack-directory maf-stack-save-interval
                      maf-stack-session-name)))
  ;; A module with no options has no section, rather than an empty one.
  (cl-assert (null (maf-module--options 'maf-hl)))
  (cl-assert (null (maf-module--options-section 'maf-hl)))
  (cl-assert (not (string-match-p "Configuration"
                                  (maf-module--details 'maf-hl))))

  ;; The section comes last, after the mode docstring, each option on a
  ;; line with its value and its docstring's first line.
  (cl-assert (let ((text (substring-no-properties (maf-module--details 'maf-plot))))
               (and (string-match-p "Configuration" text)
                    (< (string-match "^maf-use-plot-mode$" text)
                       (string-match "Configuration" text))
                    (not (string-match-p "\n\n[^ ]" (substring text (string-match "^maf-plot-samples" text))))
                    (string-match-p
                     (concat "\n\nmaf-plot-samples  "
                             (regexp-quote (prin1-to-string maf-plot-samples))
                             "\n  Sample points")
                     text))))
  ;; The name wears the variable-name colour, and a blank line
  ;; separates the entries.
  (cl-assert (eq (get-text-property 0 'face (maf-module--option-line 'maf-plot-samples))
                 'font-lock-variable-name-face))
  (cl-assert (string-match-p "\n  [^\n]*\n\nmaf-plot-"
                             (substring-no-properties (maf-module--options-section 'maf-plot))))

  ;; The value wears the row colours: `dial-value' on its standard
  ;; value, `dial-changed' once set away from it.
  (progn (setq maf-module-test--samples maf-plot-samples) nil)
  (cl-assert (let* ((line (maf-module--option-line 'maf-plot-samples))
                    (at (string-match (prin1-to-string maf-plot-samples) line)))
               (eq (get-text-property at 'face line) 'dial-value)))
  (progn (setq maf-plot-samples (1+ maf-module-test--samples)) nil)
  (cl-assert (let* ((line (maf-module--option-line 'maf-plot-samples))
                    (at (string-match (prin1-to-string maf-plot-samples) line)))
               (eq (get-text-property at 'face line) 'dial-changed)))
  (progn (setq maf-plot-samples maf-module-test--samples) nil)

  ;; A command's details in *maf-keys* end with the same section: its
  ;; targeting policy first, then its defcustoms by the naming rule.
  ;; A plain variable wears no colour, having no standard value.
  (cl-assert (equal (maf-keys--options 'mafcmd-abs)
                    '(mafcmd-abs-targets maf-abs-assume-real)))
  (cl-assert (equal (maf-keys--options 'maf-browse-variables)
                    '(maf-browse-variables-exclude)))
  (cl-assert (null (maf-keys--options 'maf-undo)))
  (cl-assert (let ((text (substring-no-properties
                          (maf-keys--detail '(mafcmd-abs "A") 80))))
               (and (string-match-p "Configuration" text)
                    (string-match-p "\n\nmafcmd-abs-targets  " text)
                    (string-match-p "\n\nmaf-abs-assume-real  " text))))
  (cl-assert (null (get-text-property
                    (1+ (length "mafcmd-abs-targets  "))
                    'face (maf-module--option-line 'mafcmd-abs-targets))))
  (cl-assert (not (string-match-p "Configuration"
                                  (maf-keys--detail '(maf-undo "U") 80))))

  ;; A long value is cut to one line; a string keeps its quotes.
  (cl-assert (<= (length (maf-module--option-value (number-sequence 1 100))) 60))
  (cl-assert (string= (maf-module--option-value "gnuplot") "\"gnuplot\"")))
