(maf-step
  (maf-use-formulas-mode 1)
  (get-buffer-create maf-formulas--detail-buffer)

  (with-current-buffer (get-buffer-create "*maf-formulas*")
    (maf-formulas-mode)
    (maf-formulas--render)
    ;; The menu lands on a formula line, grouped by category, with the
    ;; formula shown beside the title.
    (cl-assert (get-text-property (point) 'maf-formula))
    (cl-assert (string-match-p "=" (buffer-substring (line-beginning-position)
                                                     (line-end-position))))

    ;; The detail pane (a separate buffer) follows point.
    (maf-formulas--update-detail)
    (with-current-buffer maf-formulas--detail-buffer
      (cl-assert (> (buffer-size) 0)))

    ;; Groups are separated by a blank line.
    (setq maf-formulas--query "volume")
    (maf-formulas--render)
    (cl-assert (string-match-p "\n\n" (buffer-string)))

    ;; The filter narrows the list.
    (cl-assert (string-match-p "Volume of sphere" (buffer-string)))
    (cl-assert (not (string-match-p "triangle" (buffer-string))))
    (setq maf-formulas--query "")
    (maf-formulas--render))

  ;; Every formula is registered as a calc var-eq-<name>.
  (cl-assert (boundp 'var-eq-volume-of-sphere))

  ;; RET pushes the formula's equation onto the stack.
  (calc-pop (calc-stack-size))
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (search-forward "Volume of sphere")
    (beginning-of-line)
    (cl-letf (((symbol-function 'maf-formulas-quit) (lambda (&rest _) nil)))
      (maf-formulas-insert)))
  (cl-assert (string-match-p "V = " (math-format-value (calc-top-n 1))))
  (calc-pop (calc-stack-size)))
