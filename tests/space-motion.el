;; maf-forward-space (S-SPC): point hops onto the next space between
;; the parts of a formula, on the stack and inside a maf-edit session
;; alike. The contract: every inter-term space is a stop, a run of
;; spaces is one stop (its first), furniture never is — the line-number
;; margin, a line's leading indentation (the home line, Big language
;; layout), and a session's machine-owned prefix — a numeric prefix
;; counts gaps (backward when negative), and past the last gap the
;; motion signals rather than moving. A step passes when it raises no
;; error.

(maf-step
  ;; Two entries, so the motion has a margin to cross between them.
  (calc-wrapper (maf-push "1 + sqrt(x y)") (maf-push "6 x + 12"))

  ;; Every space of the entry is a stop, in order, driven by the real
  ;; key so the binding is exercised and not just the command.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " \\+ sqrt"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " sqrt"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " y)$"))

  ;; Crossing into the entry below steps over the line-number margin:
  ;; its padding is furniture, and the first stop is the entry's own
  ;; first gap.
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " x \\+ 12"))
  (cl-assert (= (calc-locate-cursor-element (point)) 1))
  (progn (execute-kbd-macro (kbd "S-SPC")) (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " 12$"))

  ;; Past the last gap there is nowhere to go: the home line's leading
  ;; spaces are indentation, not a gap, so the motion signals.
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-space) 'moved)
                   (user-error 'signalled))))

  ;; Backward retraces the same stops, margin and all.
  (let ((current-prefix-arg -1)) (call-interactively 'maf-forward-space))
  (cl-assert (looking-at " \\+ 12"))
  (let ((current-prefix-arg -1)) (call-interactively 'maf-forward-space))
  (cl-assert (looking-at " x \\+ 12"))
  (let ((current-prefix-arg -2)) (call-interactively 'maf-forward-space))
  (cl-assert (looking-at " sqrt"))
  (cl-assert (= (calc-locate-cursor-element (point)) 2))

  ;; A positive prefix moves that many gaps at once, and before the
  ;; first gap the backward motion signals in turn.
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (let ((current-prefix-arg 3)) (call-interactively 'maf-forward-space))
  (cl-assert (looking-at " y)$"))
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (let ((current-prefix-arg -1))
                              (call-interactively 'maf-forward-space))
                            'moved)
                   (user-error 'signalled))))
  (calc-pop (calc-stack-size))

  ;; Big language: the drawing's own spaces are what there is to walk.
  ;; A line's leading layout indentation is furniture, so the fraction
  ;; bar's line and the radical's overbar line — leading spaces and no
  ;; gap — are crossed without a stop.
  (maf-push "(a + 1) / sqrt(b 2)")
  (call-interactively 'maf-toggle-big-language)
  (cl-assert (eq calc-language 'big))
  (goto-char (point-min))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " \\+ 1$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " 1$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " b 2$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " 2$"))
  (cl-assert (eq 'signalled
                 (condition-case nil
                     (progn (call-interactively 'maf-forward-space) 'moved)
                   (user-error 'signalled))))
  (call-interactively 'maf-toggle-big-language)
  (calc-pop (calc-stack-size))

  ;; Inside a maf-edit session the key lives in maf-edit's own map,
  ;; installed by the editplus module — maf-mode is off for the
  ;; duration, so the stack binding cannot be the one that answers.
  (cl-assert (eq (lookup-key maf-edit-mode-map (kbd "S-SPC"))
                 'maf-forward-space))
  (calc-wrapper (maf-push "1 + 2 x") (maf-push "y - 4"))
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (call-interactively 'maf-edit)
  (cl-assert maf-edit-mode)

  ;; The walk over the editable text: the machine-owned prefix is
  ;; furniture by its text property, and the motion crosses into the
  ;; entry below just as on the rendered stack.
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " \\+ 2 x$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " x$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " - 4$"))

  ;; A run of spaces — typed mid-edit — is one gap and one stop, its
  ;; first space, and backward from past it lands on the same place.
  (progn (goto-char (point-min)) (search-forward "+ 2")
         (backward-char 2) (insert " ") nil)
  (progn (goto-char (point-min)) (call-interactively 'maf-beginning-of-entry))
  (progn (execute-kbd-macro (kbd "S-SPC")) (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at "  2 x$"))
  (progn (execute-kbd-macro (kbd "S-SPC")) nil)
  (cl-assert (looking-at " x$"))
  (let ((current-prefix-arg -1)) (call-interactively 'maf-forward-space))
  (cl-assert (looking-at "  2 x$"))

  ;; The motion never edited anything: the session discards back to the
  ;; stack it opened on.
  (call-interactively 'maf-edit-discard)
  (cl-assert (not maf-edit-mode))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "1 + 2 x"))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y - 4"))
  (calc-pop (calc-stack-size)))
