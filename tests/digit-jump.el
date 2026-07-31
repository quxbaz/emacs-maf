;;; Tests for maf-digit-jump -- SPC in digit entry sends point to entry #.

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
  (execute-kbd-macro (kbd "3 SPC"))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (= (calc-locate-cursor-element (point)) 3))
  (cl-assert (eolp))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "b"))

  ;; RET is what SPC was, and now the only key that pushes: the entry
  ;; still commits as a value there, point homing after it.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "7 RET"))
  (cl-assert (= (calc-stack-size) 5))
  (cl-assert (= (calc-top 1 'full) 7))
  (cl-assert (maf--at-home-p))
  (calc-pop 1)

  ;; Level 0 is home, as it is in calc's own stack indexing: point lands
  ;; on the dot.
  (execute-kbd-macro (kbd "0 SPC"))
  (cl-assert (maf--at-home-p))
  (cl-assert (looking-at "\\.$"))

  ;; A level past the top of the stack lands on the top entry, as a jump
  ;; past the end of a buffer lands on its last line.
  (execute-kbd-macro (kbd "9 9 SPC"))
  (cl-assert (= (calc-stack-size) 4))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))

  ;; The digits accumulate into one number rather than jumping once
  ;; apiece, and the wider line-number margin of a stack past 9 is no
  ;; obstacle. Pushed 1 through 12, so level 11 holds 2.
  (calc-wrapper (calc-pop (calc-stack-size))
                (dotimes (i 12) (maf-push (number-to-string (1+ i)))))
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "1 1 SPC"))
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
  (execute-kbd-macro (kbd "4 SPC"))
  (cl-assert (= (calc-locate-cursor-element (point)) 4))
  (cl-assert (= (mark t) maf-test--origin))
  (call-interactively 'pop-to-mark-command)
  (cl-assert (= (point) maf-test--origin))

  ;; Home is never marked: it is one keystroke away already.
  (progn (goto-char (point-max)) (setq mark-ring nil) (set-mark nil) nil)
  (execute-kbd-macro (kbd "2 SPC"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))
  (cl-assert (null (mark t)))

  ;; --- From a sub-formula ---

  ;; The contextual entry path commits nothing either: the formula point
  ;; stood on is untouched — not multiplied by the number typed — and
  ;; the spot it left is marked as from any other position.
  (calc-wrapper (calc-pop (calc-stack-size))
                (maf-push "a") (maf-push "b") (maf-push "x + 3"))
  (progn (goto-char (point-min)) (search-forward "x") (backward-char 1)
         (setq maf-test--origin (point))
         (setq mark-ring nil) (set-mark nil) nil)
  (execute-kbd-macro (kbd "3 SPC"))
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
  (execute-kbd-macro (kbd "2 SPC 5 +"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b + 5"))
  (execute-kbd-macro (kbd "U"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))

  ;; --- Where the key stays calc's own ---

  ;; Inside a radix-prefixed entry the number is plainly a value — a
  ;; stack level is not written in base 16 — so SPC is the push it
  ;; always was, point homing after it.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "1 6 # f f SPC"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (= (calc-top 1 'full) 255))
  (cl-assert (maf--at-home-p))
  (calc-pop 1)

  ;; While an incomplete object is being entered SPC is calc's element
  ;; separator, so a vector stays typeable — and half a vector is no
  ;; place to jump from in any case.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "[ 1 SPC 2 ]"))
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "[1, 2]"))
  (cl-assert (maf--at-home-p))
  (calc-pop 1)

  ;; `calc-digit-map' is calc's own map, so a key installed there fires
  ;; in every calc digit entry; with the mode off SPC must behave as it
  ;; does in plain calc — the unshifted twin of RET, pushing the number
  ;; and homing point.
  (unwind-protect
      (progn (maf-mode -1)
             (goto-char (point-max))
             (execute-kbd-macro (kbd "2 SPC")))
    (maf-mode 1))
  (cl-assert maf-mode)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (= (calc-top 1 'full) 2))
  (calc-pop (calc-stack-size)))
