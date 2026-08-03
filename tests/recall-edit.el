;; Recalling inside a maf-edit session (modules/maf-recall.el): M-p / M-n
;; fill the new entry point is in, the displaced text comes back as slot
;; 0, and an entry that came from the stack refuses the gesture.

(maf-step
  (progn (maf-use-recall-mode 1)
         (setq maf-recall--ring (list (cons "x + 1" nil)
                                      (cons "42" 42)
                                      (cons "a b" nil)))
         nil)

  ;; M-p fills a fresh entry with the newest item; pressing again walks
  ;; back through the ring, replacing rather than accumulating.
  (call-interactively 'maf-edit-add-entry)
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
  (call-interactively 'maf-edit-add-entry)
  (progn (execute-kbd-macro "zz") nil)
  (progn (execute-kbd-macro (kbd "M-p")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (progn (execute-kbd-macro (kbd "M-n")) nil)
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "zz"))
  (call-interactively 'maf-edit-discard)

  ;; Typing over a recalled entry starts a fresh cycle: the typed text
  ;; becomes the new stash, and M-p again starts from the newest item.
  (call-interactively 'maf-edit-add-entry)
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

  ;; An entry that came from the stack refuses the gesture: recall
  ;; fills new entries, it does not overwrite existing ones.
  (call-interactively 'maf-edit)
  (progn (calc-cursor-stack-index 1) (end-of-line) nil)
  (cl-assert (eq :refused
                 (condition-case nil
                     (progn (execute-kbd-macro (kbd "M-p")) :recalled)
                   (error :refused))))
  (cl-assert (string= (maf-edit--entry-text (maf-recall--entry-at-point))
                      "x + 1"))
  (call-interactively 'maf-edit-discard)
  (cl-assert (= (calc-stack-size) 1)))
