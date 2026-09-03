;; The map flag's axis keys: M r maps the next command over the rows of
;; a matrix and M c over its columns, each going to the command as the
;; vector it is. Behind the axis, : is the formula prompt and $ the
;; stack formula, mapped the same way — calc's V M _ and V M :, mapr
;; and mapc. Driven with real keys, as tests/map-flag.el drives M: the
;; flow through the two prefix keymaps is itself under test.

(defun maf-test-axis-top ()
  (maf--strip-encasing (calc-top 1 'full)))

(maf-step
  ;; The keys: r and c sit in the flag's own layer, : and $ in the
  ;; axis layer behind them.
  (cl-assert (eq (lookup-key maf--map-flag-keys "r") 'maf--map-flag-rows))
  (cl-assert (eq (lookup-key maf--map-flag-keys "c") 'maf--map-flag-cols))
  (cl-assert (eq (lookup-key maf--map-axis-keys ":") 'maf--map-axis-entry))
  (cl-assert (eq (lookup-key maf--map-axis-keys "$") 'maf--map-axis-stack))

  ;; A unary command per row: the mean of each row, one scalar apiece,
  ;; so the answer is the vector of row means. Integer means, so the
  ;; rendering is the same whatever the fraction mode.
  (maf-push "[[1, 3], [5, 7]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r u M"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[2, 6]"))
  (cl-assert (null maf-map-flag))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; Per column: the same command down the columns.
  (maf-push "[[1, 3], [5, 7]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c u M"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[3, 5]"))
  (calc-pop (calc-stack-size))

  ;; A command answering a vector per row gives the rows back in place;
  ;; per column, the columns come back in place — reversing each column
  ;; swaps the rows. Compared structurally: a matrix renders multi-line.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r v v"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 2 1) (vec 4 3))))
  (calc-pop (calc-stack-size))

  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c v v"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 3 4) (vec 1 2))))
  (calc-pop (calc-stack-size))

  ;; A binary command shares its argument across the runs: appended to
  ;; each row it lengthens the rows, to each column it adds a row.
  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "5")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r |"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 1 2 5) (vec 3 4 5))))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "5")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c |"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 1 2) (vec 3 4) (vec 5 5))))
  (calc-pop (calc-stack-size))

  ;; The axis chains with calc's own prefixes: I after M r reaches the
  ;; inverse variant, vconcatrev, still once per row.
  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "5")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r I |"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 5 1 2) (vec 5 3 4))))
  (cl-assert (null calc-inverse-flag))
  (calc-pop (calc-stack-size))

  ;; The formula prompt along the axis: each row, then each column, is
  ;; the $ the formula sees.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r : vsum($) RET"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[3, 7]"))
  (cl-assert (null maf-map-flag))
  (calc-pop (calc-stack-size))

  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c : vsum($) RET"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[4, 6]"))
  (calc-pop (calc-stack-size))

  ;; A formula answering a vector per column gives the columns back in
  ;; place: sorting each column of [[4, 1], [2, 3]] gives [[2, 1], [4, 3]].
  (maf-push "[[2, 1], [4, 3]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r : sort($) RET"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop (calc-stack-size))

  (maf-push "[[4, 1], [2, 3]]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c : sort($) RET"))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 2 1) (vec 4 3))))
  (calc-pop (calc-stack-size))

  ;; The stack formula along the axis, consumed as the binary arg it is.
  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "vsum(x)")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r $"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[3, 7]"))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  (maf-push "[[1, 2], [3, 4]]")
  (maf-push "vsum(x)")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c $"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[4, 6]"))
  (calc-pop (calc-stack-size))

  ;; A plain vector has no rows to speak of beyond its elements: under
  ;; either axis it maps elementwise, as calc's mapr and mapc read one.
  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r : x^2 RET"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[1, 4, 9]"))
  (calc-pop (calc-stack-size))

  (maf-push "[1, 2, 3]")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M c : x^2 RET"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "[1, 4, 9]"))
  (calc-pop (calc-stack-size))

  ;; A scalar is the degenerate map under an axis as under M: the
  ;; command runs once on the whole entry.
  (maf-push "x")
  (goto-char (point-max))
  (execute-kbd-macro (kbd "M r Q"))
  (cl-assert (string= (math-format-value (maf-test-axis-top)) "sqrt(x)"))
  (cl-assert (null maf-map-flag))
  (calc-pop (calc-stack-size))

  ;; $$ pairs elements and has no reading by rows or columns; the
  ;; refusal spends the flag and the stack stands.
  (maf-push "[[1, 2], [3, 4]]")
  (goto-char (point-max))
  (cl-assert (string-match-p
              "rows or columns"
              (condition-case err
                  (progn (execute-kbd-macro (kbd "M r : $$ + $ RET")) "")
                (user-error (error-message-string err)))))
  (cl-assert (null maf-map-flag))
  (cl-assert (= (calc-stack-size) 1))
  (calc-pop (calc-stack-size))

  ;; The flag-mechanics gestures each live in a single form, as in
  ;; tests/map-flag.el: the cockpit's own keys must not meet a pending
  ;; prefix.

  ;; After M r the flag names the axis and the axis layer is live; a
  ;; command with no reading of the flag drops both.
  (progn (execute-kbd-macro (kbd "M r"))
         (cl-assert (eq maf-map-flag 'rows))
         (cl-assert (eq overriding-terminal-local-map maf--map-axis-keys))
         (execute-kbd-macro (kbd "C-f"))
         (cl-assert (null maf-map-flag))
         (cl-assert (null overriding-terminal-local-map))
         (cl-assert (null (memq #'maf--map-flag-expire post-command-hook))))

  (progn (execute-kbd-macro (kbd "M c"))
         (cl-assert (eq maf-map-flag 'cols))
         (execute-kbd-macro (kbd "C-f"))
         (cl-assert (null maf-map-flag)))

  ;; C-g at the axis prompt abandons the gesture cleanly.
  (maf-push "[[1, 2], [3, 4]]")
  (progn (goto-char (point-max))
         (condition-case nil (execute-kbd-macro (kbd "M c : C-g")) (quit nil))
         (cl-assert (null maf-map-flag))
         (cl-assert (null overriding-terminal-local-map))
         (cl-assert (null (memq #'maf--map-flag-expire post-command-hook))))
  (cl-assert (equal (maf-test-axis-top) '(vec (vec 1 2) (vec 3 4))))
  (calc-pop (calc-stack-size)))
