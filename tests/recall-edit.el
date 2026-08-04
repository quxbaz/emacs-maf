;; Recalling inside a maf-edit session (modules/maf-recall.el): M-p / M-n
;; fill the entry point is in, the text they displace comes back as slot
;; 0, and at home they open an entry to fill.

(maf-step
  (progn (maf-use-recall-mode 1)
         (setq maf-recall--ring (list (cons "x + 1" nil)
                                      (cons "42" 42)
                                      (cons "a b" nil)))
         nil)

  ;; M-p fills a fresh entry with the newest item; pressing again walks
  ;; back through the ring, replacing rather than accumulating.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (progn (execute-kbd-macro (kbd "M-p M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "a b"))

  ;; The end of the ring stops with a message; the entry keeps the
  ;; oldest item rather than wrapping around to the newest.
  (progn (ignore-errors (execute-kbd-macro (kbd "M-p"))) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "a b"))

  ;; M-n walks back toward the newest.
  (progn (execute-kbd-macro (kbd "M-n M-n")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))

  ;; Committing a recalled entry is a commit like any other.
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))

  ;; Half-typed text is stashed as slot 0: M-n past the newest item
  ;; puts it back, so a recall never costs the user what they typed.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "zz") nil)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (progn (execute-kbd-macro (kbd "M-n")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "zz"))
  ;; The stash is all that half-typed text gets: only an entry with a
  ;; value behind it is banked in the ring, so fragments stay out.
  (cl-assert (not (assoc "zz" maf-recall--ring)))
  (call-interactively 'maf-edit-discard)

  ;; Typing over a recalled entry starts a fresh cycle: the typed text
  ;; becomes the new stash, and M-p again starts from the newest item.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro (kbd "M-p M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "42"))
  (progn (execute-kbd-macro "9") nil)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (progn (execute-kbd-macro (kbd "M-n")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "429"))
  (call-interactively 'maf-edit-discard)

  ;; An entry that came from the stack is overwritten like any other,
  ;; and the value it held enters the ring as the newest item — so the
  ;; first press swaps the entry for the item before it, not for what
  ;; it already holds.
  (progn (setq maf-recall--ring (list (cons "x + 1" nil)
                                      (cons "42" 42)))
         nil)
  (call-interactively 'maf-edit)
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "42"))
  (cl-assert (equal (mapcar #'car maf-recall--ring)
                    '("x + 1" "42")))
  ;; It went in with its value, not as text alone: the session had not
  ;; touched the entry, so what it took off the stack rides along.
  (cl-assert (cdr (assoc "x + 1" maf-recall--ring)))

  ;; M-n puts the displaced entry back, and it stays in the ring
  ;; afterwards — banking it is what makes the overwrite safe.
  (progn (execute-kbd-macro (kbd "M-n")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (cl-assert (equal (mapcar #'car maf-recall--ring)
                    '("x + 1" "42")))

  ;; Committing the overwrite replaces that entry on the stack, and the
  ;; displaced value is still a recall away.
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "42"))
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (call-interactively 'maf-edit-discard)

  ;; And it recalls out on the stack like anything else in the ring.
  (progn (goto-char (point-max)) nil)
  (execute-kbd-macro (kbd "M-p"))
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (progn (calc-pop (calc-stack-size)) nil)

  ;; --- At home inside a session ---

  ;; There is no entry at home to fill, so recall opens one at the
  ;; bottom and fills it: the same thing M-p means out on the stack.
  (maf-push "c")
  (call-interactively 'maf-edit)
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (= (length (maf-edit--overlays)) 2))
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))

  ;; The cycle then runs in the entry it opened, replacing rather than
  ;; opening another.
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (= (length (maf-edit--overlays)) 2))
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "42"))

  ;; Slot 0 of a cycle that opened its own entry is the empty text it
  ;; started as, so walking back past the newest item empties the entry
  ;; again — and committing then drops it, leaving the stack as it was.
  (progn (execute-kbd-macro (kbd "M-n M-n")) nil)
  (cl-assert (string-blank-p
              (maf-edit--entry-text (maf-recall--entry-at-point))))
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "c"))

  ;; Committing a filled one pushes it at the bottom, below the entries
  ;; already there.
  (call-interactively 'maf-edit)
  (progn (goto-char (point-max)) nil)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "c"))

  ;; M-n at home opens nothing: there is no cycle to walk back through,
  ;; and an empty entry left behind would be a surprise.
  (call-interactively 'maf-edit)
  (progn (goto-char (point-max)) nil)
  (cl-assert (eq :refused
                 (condition-case nil
                     (progn (execute-kbd-macro (kbd "M-n")) :moved)
                   (error :refused))))
  (cl-assert (= (length (maf-edit--overlays)) 2))
  (call-interactively 'maf-edit-discard))
