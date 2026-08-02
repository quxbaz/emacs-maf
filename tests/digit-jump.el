;;; Tests for maf-digit-jump -- j in digit entry sends point to entry #.

(defvar maf-test--origin nil
  "Buffer position a jump left, for the mark checks.")

(maf-step
  ;; calc-wrapper's epilogue renumbers the display; raw pushes would
  ;; leave every entry rendered as level 1.
  (calc-wrapper (maf-push "a") (maf-push "b") (maf-push "c") (maf-push "d"))

  ;; --- The jump ---

  ;; From home: point lands on the entry the number names, at its EOL —
  ;; the margin, where the next command takes the whole entry. Nothing
  ;; is pushed: the number was an address, not a value.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "3 j"))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (eolp))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "b"))

  ;; The keys that commit are untouched beside it: RET still pushes,
  ;; point homing after it.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "7 RET"))
  (cl-assert (= (calc-stack-size) 5))
  (cl-assert (= (calc-top 1 'full) 7))
  (cl-assert (maf--at-home-p))
  (calc-pop 1)

  ;; Level 0 is home, as it is in calc's own stack indexing: point lands
  ;; on the dot.
  (execute-kbd-macro (kbd "0 j"))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))

  ;; A level past the top of the stack lands on the top entry, as a jump
  ;; past the end of a buffer lands on its last line.
  (execute-kbd-macro (kbd "9 9 j"))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))

  ;; The digits accumulate into one number rather than jumping once
  ;; apiece, and the wider line-number margin of a stack past 9 is no
  ;; obstacle. Pushed 1 through 12, so level 11 holds 2.
  (calc-wrapper (calc-pop (calc-stack-size))
                (dotimes (i 12) (maf-push (number-to-string (1+ i)))))
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "1 1 j"))
  (cl-assert (= (calc-locate-cursor-element (point)) 11))
  ;; Stripped: the selection machinery encases the atoms of whatever
  ;; entry point lands on, this one included.
  (cl-assert (equal (maf--strip-encasing (calc-top 11 'full)) 2))
  (cl-assert (eolp))

  ;; --- The mark left behind ---

  ;; The place the jump left is marked, so C-u C-SPC returns to it.
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (setq maf-test--origin (point))
         (setq mark-ring nil) (set-mark nil) nil)
  (execute-kbd-macro (kbd "4 j"))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))
  (cl-assert (= (mark t) maf-test--origin))
  (call-interactively 'pop-to-mark-command)
  (cl-assert (= (point) maf-test--origin))

  ;; Home is never marked: it is one keystroke away already.
  (progn (goto-char (point-max)) (setq mark-ring nil) (set-mark nil) nil)
  (execute-kbd-macro (kbd "2 j"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (null (mark t)))

  ;; --- From a sub-formula ---

  ;; The contextual entry path commits nothing either: the formula point
  ;; stood on is untouched — not multiplied by the number typed, as the
  ;; SPC beside this key would have — and the spot it left is marked as
  ;; from any other position.
  (calc-wrapper (calc-pop (calc-stack-size))
                (maf-push "a") (maf-push "b") (maf-push "x + 3"))
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1)
         (setq maf-test--origin (point))
         (setq mark-ring nil) (set-mark nil) nil)
  (execute-kbd-macro (kbd "3 j"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 3"))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (= (mark t) maf-test--origin))

  ;; --- The landing is an entry target ---

  ;; What the jump leaves is a position the next command resolves: 5 +
  ;; on it adds to the whole entry it named, and the arg push folds into
  ;; that command's undo group as it does from any other margin.
  (calc-wrapper (calc-pop (calc-stack-size))
                (maf-push "a + b") (maf-push "c"))
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "2 j 5 +"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b + 5"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))

  ;; --- Where the key stays calc's own ---

  ;; Inside a radix-prefixed entry the number is plainly a value — a
  ;; stack level is not written in base 16 — and from base 20 up `j' is
  ;; a digit in its own right: 20#j is 19, pushed, not a jump to 20.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "2 0 # j RET"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (= (calc-top 1 'full) 19))
  (cl-assert (maf--at-home-p))
  (calc-pop 1)

  ;; While an incomplete object is being entered, half a vector is no
  ;; place to jump from: `j' is calc's own there, ending the entry as an
  ;; element and re-dispatching as the prefix it is out in the stack (j l
  ;; here). The vector is still open and point never travelled.
  (progn (goto-char (point-max)) nil)
  (ignore-errors (execute-kbd-macro (kbd "[ 1 SPC 3 j l")))
  (cl-assert (maf--incomplete-entry-p))
  (cl-assert (maf--at-home-p))
  (execute-kbd-macro (kbd "]"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 3]"))
  (calc-pop 1)

  ;; `calc-digit-map' is calc's own map, so a key installed there fires
  ;; in every calc digit entry; with the mode off `j' must behave as it
  ;; does in plain calc — a command-key termination, pushing the number
  ;; and re-dispatching j, with no jump anywhere.
  (unwind-protect
      (progn (maf-mode -1)
             (goto-char (point-max))
             (ignore-errors (execute-kbd-macro (kbd "2 j"))))
    (maf-mode 1))
  (cl-assert maf-mode)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (= (calc-top 1 'full) 2))
  (calc-pop (calc-stack-size)))
