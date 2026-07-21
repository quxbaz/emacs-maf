(maf-step
  ;; A maf-edit commit (this-command `maf-edit-commit') is labeled by
  ;; what it did to the stack — "edit" for an in-place change, "new" for
  ;; an added entry — not by its blanket "edit"/"..." trail prefix, which
  ;; can't tell the two apart.
  (calc-eval "5" 'push)
  (calc-eval "10" 'push)
  (setq maf-timeline--states nil
        maf-timeline--last-raw (mapcar #'car (nthcdr calc-stack-top calc-stack)))

  ;; In-place edit: replace the top (10 → 20).
  (calc-pop-stack 1)
  (calc-eval "20" 'push)
  (let ((this-command 'maf-edit-commit)) (maf-timeline--capture))
  (cl-assert (equal (nth 1 (car maf-timeline--states)) "edit"))

  ;; Add a new entry on top.
  (calc-eval "30" 'push)
  (let ((this-command 'maf-edit-commit)) (maf-timeline--capture))
  (cl-assert (equal (nth 1 (car maf-timeline--states)) "new"))

  (calc-pop (calc-stack-size)))
