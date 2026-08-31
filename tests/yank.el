;; maf-yank: digit-grouped numbers come in whole; everything else is
;; calc-yank as before.
;;
;; The command reads the kill ring, so each case seeds it with
;; `kill-new' and yanks onto an empty stack.

(maf-step
  ;; A number with digit-group commas is one number, not three
  ;; comma-separated entries.
  (progn (kill-new "1,234,567")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1)) "1234567"))
  (calc-pop (calc-stack-size))

  ;; Grouping composes with a decimal part.
  (progn (kill-new "1,234.56")
         (call-interactively 'maf-yank))
  (cl-assert (string= (math-format-value (calc-top 1)) "1234.56"))
  (calc-pop (calc-stack-size))

  ;; A leading sign stays on the number.
  (progn (kill-new "-1,234")
         (call-interactively 'maf-yank))
  (cl-assert (string= (math-format-value (calc-top 1)) "-1234"))
  (calc-pop (calc-stack-size))

  ;; Groups after the first must be exactly three digits: "12,34" is
  ;; not a grouped number, so it yanks as the two values calc reads.
  (progn (kill-new "12,34")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "12"))
  (cl-assert (string= (math-format-value (calc-top 1)) "34"))
  (calc-pop (calc-stack-size))

  ;; A space after the comma marks a list, not grouping.
  (progn (kill-new "1, 234")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (calc-pop (calc-stack-size))

  ;; Each line of a multi-line yank is judged on its own: a copied
  ;; spreadsheet column arrives one entry per line.
  (progn (kill-new "1,234\n5,678\n")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "1234"))
  (cl-assert (string= (math-format-value (calc-top 1)) "5678"))
  (calc-pop (calc-stack-size))

  ;; Stack level prefixes are dropped: text swept off a stack display
  ;; yanks as the entries themselves. The number is discarded, never
  ;; read — lines push in the order they appear.
  (progn (kill-new "2:  [x = 6, x = 0]\n1:  [y = 5, y = 2]\n")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "[x = 6, x = 0]"))
  (cl-assert (string= (math-format-value (calc-top 1)) "[y = 5, y = 2]"))
  (calc-pop (calc-stack-size))

  ;; Indented prefixes strip too — the shape a stack quoted in notes
  ;; arrives in.
  (progn (kill-new "    2:  [x = 6, x = 0]\n    1:  [y = 5, y = 2]\n")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2)) "[x = 6, x = 0]"))
  (cl-assert (string= (math-format-value (calc-top 1)) "[y = 5, y = 2]"))
  (calc-pop (calc-stack-size))

  ;; The prefix needs the whitespace calc writes after the colon: a
  ;; fraction line is 1:2 with none, and yanks as the fraction.
  (progn (kill-new "1:2")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1)) "1:2"))
  (calc-pop (calc-stack-size))

  ;; Ordinary yanks are untouched: a vector's commas are calc syntax.
  (progn (kill-new "[1, 2]")
         (call-interactively 'maf-yank))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1)) "[1, 2]"))
  (calc-pop (calc-stack-size))

  ;; A formula yanks as calc-yank always did.
  (progn (kill-new "a + b")
         (call-interactively 'maf-yank))
  (cl-assert (string= (math-format-value (calc-top 1)) "a + b"))
  (calc-pop (calc-stack-size))

  ;; The radix prefix still reaches calc-yank-internal: C-u 6 C-y reads
  ;; the kill as hex.
  (progn (kill-new "ff")
         (let ((current-prefix-arg 6))
           (call-interactively 'maf-yank)))
  (cl-assert (string= (math-format-value (calc-top 1)) "255"))
  (calc-pop (calc-stack-size)))
