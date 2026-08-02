;; K reaching a maf command whose key is not a plain character.
;;
;; Calc's fancy prefix (K, I, H, O) installs `calc-fancy-prefix-map' as the
;; overriding map, so the key after K runs `calc-fancy-prefix-other-key'
;; instead of its own binding. That function clears the flags for anything it
;; does not count as a calc command -- every control character below SPC, and
;; every event that is not an integer at all, which is every function key. So
;; K reached maf commands bound to plain characters (K *) and nothing else:
;; mafcmd-let on C-c C-c and mafcmd-toggle-op on S-<up> both ran with the flag
;; already cleared.
;;
;; `maf--fancy-prefix-keep' spares the keys that open a command marked
;; `maf-command' -- what `maf-defcmd' stamps on every command it defines,
;; since their commit path reads the resolve-time :keep snapshot. A prefix
;; like C-c cannot be decided on the spot: it is shared with ordinary global
;; commands, so it is let through provisionally and
;; `maf--fancy-prefix-decide' settles it from `this-command' once the whole
;; sequence resolves.
;;
;; These take real keys through `execute-kbd-macro' -- `call-interactively'
;; bypasses the keymap path the whole mechanism lives in, so it cannot see
;; any of this. tests/dup.el covers the K RET case from the same angle.

(maf-step
  ;; C-c C-c without K: ordinary binary command, both operands consumed.
  (calc-pop (calc-stack-size))
  (calc-push (math-read-expr "2 x"))
  (calc-push (math-read-expr "x = 3"))
  (progn (goto-char (point-max)) (execute-kbd-macro (kbd "C-c C-c")) nil)
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6"))

  ;; K C-c C-c: the operands stay and the result is pushed on top, which is
  ;; what the command's docstring promises for keep-args.
  (calc-pop (calc-stack-size))
  (calc-push (math-read-expr "2 x"))
  (calc-push (math-read-expr "x = 3"))
  (progn (goto-char (point-max)) (execute-kbd-macro (kbd "K C-c C-c")) nil)
  (cl-assert (= (calc-stack-size) 3))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "6"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "x = 3"))
  (cl-assert (string= (math-format-value (calc-top 3 'full)) "2 x"))
  (cl-assert (not calc-keep-args-flag))  ; consumed, not leaked
  (cl-assert (not (memq #'maf--fancy-prefix-decide pre-command-hook)))

  ;; A function key reaches its marked command too -- S-<up> is
  ;; mafcmd-toggle-op, and the event is a symbol, which calc's test rejects
  ;; just as firmly as a control character.
  (calc-pop (calc-stack-size))
  (calc-push (math-read-expr "a + b"))
  (progn (goto-char (point-max)) (execute-kbd-macro (kbd "K S-<up>")) nil)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "a - b"))
  (cl-assert (string= (math-format-value (calc-top 2 'full)) "a + b"))
  (cl-assert (not calc-keep-args-flag))

  ;; The prefix is shared. An unmarked command reached through the same C-c
  ;; must not receive the flag, and must not be left holding it -- deciding
  ;; at C-c rather than at the leaf would hand keep-args to whatever followed.
  (calc-pop (calc-stack-size))
  (calc-push 3)
  (calc-push 2)
  (progn
    (defvar maf-test--saw 'unset)
    (defun maf-test--unmarked () (interactive) (setq maf-test--saw calc-keep-args-flag))
    (define-key maf-mode-map (kbd "C-c z") #'maf-test--unmarked)
    (goto-char (point-max))
    (execute-kbd-macro (kbd "K C-c z"))
    (define-key maf-mode-map (kbd "C-c z") nil)
    nil)
  (cl-assert (null maf-test--saw))        ; ran without the flag
  (cl-assert (not calc-keep-args-flag))   ; and nothing leaked past it
  (cl-assert (not (memq #'maf--fancy-prefix-decide pre-command-hook)))

  ;; Aborting mid-sequence unwinds the same way: the one-shot hook removes
  ;; itself before it inspects anything, so a quit cannot strand it.
  (calc-pop (calc-stack-size))
  (calc-push 3)
  (calc-push 2)
  (progn (goto-char (point-max))
         (ignore-errors (execute-kbd-macro (kbd "K C-c C-g")))
         nil)
  (cl-assert (= (calc-stack-size) 2))
  (cl-assert (not calc-keep-args-flag))
  (cl-assert (not (memq #'maf--fancy-prefix-decide pre-command-hook)))

  ;; The mark is on the commands that read the flag, not on everything maf
  ;; binds: a plain stack command keeps calc's own behavior.
  (cl-assert (get 'mafcmd-let 'maf-command))
  (cl-assert (get 'mafcmd-toggle-op 'maf-command))
  (cl-assert (get 'maf-dup-or-clear-selections 'maf-command))
  (cl-assert (null (get 'maf-swap-up 'maf-command))))
