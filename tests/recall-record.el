;; What feeds the recall ring on the maf-edit path (modules/maf-recall.el).
;; The rule: only entries started from empty, and only when the commit
;; goes through. Everything else — an edit of an existing entry, a
;; discard, a commit that would not parse — leaves the ring alone.

(maf-step
  (progn (maf-use-recall-mode 1) (setq maf-recall--ring nil) nil)

  ;; A bare entry typed from nothing is recorded on commit.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "x + 1") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("x + 1")))
  (cl-assert (= (calc-stack-size) 1))

  ;; Editing an entry that came from the stack is a modification, not a
  ;; new entry: the ring does not move.
  (call-interactively 'maf-edit)
  (progn (calc-cursor-stack-index 1) (end-of-line)
         (execute-kbd-macro " + 2") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "x + 1 + 2"))
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("x + 1")))

  ;; Discarding means it: text typed and thrown away is not recorded.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "zz") nil)
  (call-interactively 'maf-edit-discard)
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("x + 1")))

  ;; A commit that cannot parse records nothing either — it signals and
  ;; leaves the session standing, so the recording never runs.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "1 +") nil)
  (progn (ignore-errors (call-interactively 'maf-edit-commit)) nil)
  (cl-assert maf-edit-mode)
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("x + 1")))
  (call-interactively 'maf-edit-discard)

  ;; Several new entries in one session are recorded bottom-most last,
  ;; so the ring reads newest-first in the order they were added.
  (progn (calc-pop (calc-stack-size)) nil)
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a") nil)
  (progn (call-interactively 'maf-edit-newline)
         (execute-kbd-macro "b") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("b" "a" "x + 1")))

  ;; Re-typing an entry moves it to the front instead of duplicating.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "a") nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("a" "b" "x + 1")))

  ;; An entry emptied during the session is deleted, not recorded.
  (call-interactively 'maf-edit-add-entry-below)
  (progn (execute-kbd-macro "q") nil)
  (progn (execute-kbd-macro (kbd "DEL")) nil)
  (call-interactively 'maf-edit-commit)
  (cl-assert (equal (mapcar #'car maf-recall--ring) '("a" "b" "x + 1"))))
