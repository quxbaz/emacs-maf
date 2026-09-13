;; mafcmd-convert-units: the units prompts are driven with real keys, so
;; each case queues its input and fires the command in a single form.

(maf-step
  ;; Home: the top entry converts to the typed units.
  (maf-push "3 m")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "9.84251968504 ft"))
  (calc-pop (calc-stack-size))

  ;; A vector converts element by element.
  (maf-push "[1 m, 2 m]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[3.28083989501 ft, 6.56167979003 ft]"))
  (calc-pop (calc-stack-size))

  ;; An element whose units do not fit the target stands untouched, and
  ;; a unit in the third element is seen (calc's own test looks at two).
  (maf-push "[1 m, 2 s, 3 m]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[3.28083989501 ft, 2 s, 9.84251968504 ft]"))
  (calc-pop (calc-stack-size))

  ;; A units system name converts every quantity to its base units.
  (maf-push "[3 ft, 2 lb]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "si\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[0.9144 m, 0.90718474 kg]"))
  (calc-pop (calc-stack-size))

  ;; A unitless subject is asked its old units first, and the answer is
  ;; a pure number — for each element of a vector alike.
  (maf-push "3")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "m\rft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "9.84251968504"))
  (calc-pop (calc-stack-size))
  (maf-push "[1, 2]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "m\rft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[3.28083989501, 6.56167979003]"))
  (calc-pop (calc-stack-size))

  ;; An exact quantity stays exact when its conversion is, whatever
  ;; the mode; a fraction stays a fraction; a float stays a float.
  (maf-push "[1 cm, 2 cm, 1 m]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "mm\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[10 mm, 20 mm, 1000 mm]"))
  (calc-pop (calc-stack-size))
  (maf-push "[1:3 m, 1.5 cm]")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "mm\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1000:3 mm, 15. mm]"))
  (calc-pop (calc-stack-size))

  ;; With the option off, calc's own arithmetic decides the form.
  (maf-push "[1 cm, 2 cm, 1 m]")
  (goto-char (point-max))
  (progn (let ((maf-convert-units-exact nil))
           (setq unread-command-events (listify-key-sequence "mm\r"))
           (call-interactively 'mafcmd-convert-units)))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[10. mm, 20. mm, 1000 mm]"))
  (calc-pop (calc-stack-size))

  ;; A sum of like quantities combines before converting, as calc's
  ;; conversion combines it.
  (maf-push "3 m + 2 in")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "10.0091863517 ft"))
  (calc-pop (calc-stack-size))

  ;; Subexpr: point on the 3 of 3 m widens to the quantity, and so does
  ;; point on its unit name; the other term stands.
  (maf-push "3 m + 2 s")
  (progn (calc-cursor-stack-index 1) (search-forward "3") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "9.84251968504 ft + 2 s"))
  (calc-pop (calc-stack-size))
  (maf-push "[1 m, 2 m]")
  (progn (calc-cursor-stack-index 1) (search-forward "2 m") (backward-char 1))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "[1 m, 6.56167979003 ft]"))
  (calc-pop (calc-stack-size))

  ;; Equation: each side converts; a side with no units stands.
  (maf-push "x = 3 m")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "ft\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "x = 9.84251968504 ft"))
  (calc-pop (calc-stack-size))

  ;; The prompt defaults to the units a quantity of the kind last went
  ;; to: RET alone takes ft.
  (maf-push "5 m")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "\r"))
         (call-interactively 'mafcmd-convert-units))
  (cl-assert (string= (math-format-value (calc-top 1 'full))
                      "16.4041994751 ft"))
  (calc-pop (calc-stack-size))

  ;; Units none of the subject's quantities fit are refused before
  ;; anything is committed; so is input naming no unit.
  (maf-push "3 m")
  (goto-char (point-max))
  (progn (setq unread-command-events (listify-key-sequence "s\r"))
         (cl-assert (condition-case nil
                        (progn (call-interactively 'mafcmd-convert-units) nil)
                      (user-error t))))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "3 m"))
  (progn (setq unread-command-events (listify-key-sequence "bogus\r"))
         (cl-assert (condition-case nil
                        (progn (call-interactively 'mafcmd-convert-units) nil)
                      (user-error t))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size)))
