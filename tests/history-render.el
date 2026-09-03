(maf-step
  ;; Unnamed states read as "entry": a plain entry (nil) and calc's
  ;; "..." continuation prefix alike.
  (cl-assert (equal (maf-history--label '((1) nil)) "entry"))
  (cl-assert (equal (maf-history--label '((1) "...")) "entry"))
  (cl-assert (equal (maf-history--label '((1) "fctr")) "fctr"))

  ;; The browser is two buffers on one selection. Stash the session's
  ;; log, render a made-up one into a scratch pair, and put it back at
  ;; the end.
  (setq maf--history-render-stash (list maf-history--states maf-history--index)
        maf-history--states (list (list (list 7 5) "mult")
                                  (list (list 5) nil))
        maf-history--index 0)

  ;; The log: one line per state, newest at the top, each prefixed by a
  ;; change marker — `+' added, `-' removed, `~' changed in place, `·'
  ;; for the oldest, which has nothing to diff against. The current
  ;; state is marked and wears the current face. Each line carries its
  ;; state's index, and point rests on the current line.
  (with-current-buffer (maf-history--buffer)
    (maf-history--render t)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "▸ + mult\n  · entry\n"))
    (cl-assert (equal header-line-format "maf-history  2/2"))
    (cl-assert (= (line-number-at-pos) 1))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 0))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-current))
    ;; The marker keeps its own colour under the current state's face,
    ;; which is appended rather than layered over it.
    (progn (search-forward "+") (backward-char 1))
    (cl-assert (equal (get-text-property (point) 'face)
                      '(maf-history-added maf-history-current)))
    (progn (goto-char (point-min)) (forward-line 1))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 1))
    (cl-assert (null (get-text-property (point) 'face)))
    ;; The oldest state has no reference, so it takes the neutral marker.
    (progn (search-forward "·") (backward-char 1))
    (cl-assert (eq (get-text-property (point) 'face) 'shadow)))

  ;; The stack beside it: the selected state's whole stack, deepest
  ;; first, the entry this step produced highlighted and the one
  ;; carried over from before it not. Every line carries its entry's
  ;; value, so RET works anywhere on the row. Point lands on the
  ;; top-of-stack entry, the likeliest RET target.
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "2:  5\n1:  7\n"))
    (cl-assert (looking-at-p "1:  7"))
    (cl-assert (bolp))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-changed))
    (cl-assert (equal (get-text-property (point) 'maf-history-value) 7))
    (progn (goto-char (point-min)))
    (cl-assert (null (get-text-property (point) 'face)))
    (cl-assert (equal (get-text-property (point) 'maf-history-value) 5))
    ;; The legend heads this window, naming the keys it actually uses:
    ;; the step keys mean the same in both windows, and RET inserts
    ;; here (in the log it crosses over instead).
    (let ((legend (substring-no-properties (format-mode-line header-line-format))))
      ;; n/p name the motion control; j/k do the same but stay off the
      ;; legend rather than spend the width on a second pair. In this
      ;; window they move between entries, in the log between states —
      ;; the control names both, so the legend is true either way.
      (cl-assert (string-match-p "n/p move" legend))
      (cl-assert (not (string-match-p "j/k" legend)))
      (cl-assert (string-match-p "RET insert" legend))
      ;; TAB crosses between the windows too, by naming the side it
      ;; leads to rather than toggling, so it joins o/t on the control.
      (cl-assert (string-match-p "TAB/o/t switch" legend))
      ;; Clearing the whole log is on the legend beside the D that
      ;; deletes one state, chord and all: the key is what keeps a wipe
      ;; out of fingerslip range, so it is the part worth showing.
      (cl-assert (string-match-p "C-M-k clear" legend))
      (cl-assert (not (string-match-p "calc" legend)))))

  ;; Selecting the older state re-renders both: the marker moves, and
  ;; the stack follows. The oldest state has no reference to diff
  ;; against, so nothing in it is highlighted.
  (progn (setq maf-history--index 1) (maf-history--render t))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "  + mult\n▸ · entry\n"))
    (cl-assert (= (line-number-at-pos) 2))
    (cl-assert (equal header-line-format "maf-history  1/2")))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "1:  5\n"))
    (progn (goto-char (point-min)))
    (cl-assert (null (get-text-property (point) 'face))))

  ;; Duplicating an entry reads as `dupe' and still marks as an addition.
  ;; The copy it added is highlighted even though the state before it
  ;; held that same value — which entry the step produced is a matter of
  ;; position, not of membership — and the copy nearest the top is the
  ;; one taken, the end calc pushes to.
  (progn (setq maf-history--states (list (list (list 5 5 3) "dupe")
                                         (list (list 5 3) "mult")
                                         (list (list 3) nil))
               maf-history--index 0)
         (maf-history--render t))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "▸ + dupe\n  + mult\n  · entry\n")))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "3:  3\n2:  5\n1:  5\n"))
    ;; Top of stack: the copy, highlighted.
    (cl-assert (looking-at-p "1:  5"))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-changed))
    ;; The 5 below it is the original, carried over.
    (progn (goto-char (point-min)) (forward-line 1))
    (cl-assert (looking-at-p "2:  5"))
    (cl-assert (null (get-text-property (point) 'face))))

  ;; A state's third slot is the command the change landed under, and
  ;; the log echoes it after the label, parenthesised. The label leads —
  ;; it names the operation — and the command names the code that ran,
  ;; which a trail prefix like "mul" does not say.
  (progn (setq maf-history--states
               (list (list (list 12) "mul" 'mafcmd-mul)
                     (list (list 4 3) "entry" 'calcDigit-nondigit)
                     (list (list 3) "undo" 'undo)
                     (list (list 9) "solo"))
               maf-history--index 0)
         (maf-history--render t))
  (with-current-buffer (maf-history--buffer)
    ;; A label that is already the command's name says it once; a state
    ;; with no command recorded has no echo to give.
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      (concat "▸ - mul (mafcmd-mul)\n"
                              "  + entry (calcDigit-nondigit)\n"
                              "  ~ undo\n"
                              "  · solo\n")))
    ;; The echo is shadowed, so the label still carries the line.
    (progn (goto-char (point-min)) (search-forward "(mafcmd-mul") (backward-char 1))
    (cl-assert (equal (get-text-property (point) 'face)
                      '(shadow maf-history-current)))
    ;; It is part of the row, so point anywhere along it still names the
    ;; state -- the whole line carries the index.
    (cl-assert (= (get-text-property (point) 'maf-history-index) 0)))

  ;; ? opens the help of the command a row names, so a name read off the
  ;; log leads to what it does. Point picks the row, which is why the
  ;; row and not the selection is what it reads.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "?"))
                 'maf-history-describe-command))
  ;; w is the same reading without a shifted key, and the stack window
  ;; inherits both.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "w"))
                 'maf-history-describe-command))
  (cl-assert (eq (lookup-key maf-history-stack-mode-map (kbd "w"))
                 'maf-history-describe-command))
  ;; h now names the left window (see tests/history.el); the mode's own
  ;; help is on C-h m rather than the h `special-mode' puts it on.
  (cl-assert (eq (lookup-key maf-history-mode-map (kbd "h")) 'maf-history-focus-log))
  (with-current-buffer (maf-history--buffer)
    (progn (goto-char (point-min)) (forward-line 1))
    (cl-assert (eq (nth 2 (maf-history--state-at-point)) 'calcDigit-nondigit))
    (save-window-excursion (call-interactively 'maf-history-describe-command))
    (cl-assert (string-match-p "calcDigit-nondigit"
                               (with-current-buffer "*Help*" (buffer-string))))
    ;; The oldest row here recorded no command, so there is nothing to
    ;; describe and it says so rather than describing the wrong thing.
    (progn (goto-char (point-min)) (forward-line 3))
    (cl-assert (null (nth 2 (maf-history--state-at-point))))
    (cl-assert (not (ignore-errors
                      (call-interactively 'maf-history-describe-command) t))))
  ;; Off a log row -- the stack window has none -- it falls back to the
  ;; state the browser has selected, which is the one that window shows.
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (eq (nth 2 (maf-history--state-at-point)) 'mafcmd-mul)))

  ;; A state before an emptied stack is still a state to diff against, so
  ;; the first entry after one is highlighted rather than left plain.
  (progn (setq maf-history--states (list (list (list 7) "new")
                                         (list nil "del"))
               maf-history--index 0)
         (maf-history--render t))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "1:  7\n"))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-changed)))

  ;; An empty stack renders as its placeholder, and an empty log leaves
  ;; the counter off the header and says so in both windows.
  (progn (setq maf-history--states (list (list nil "del") (list (list 5) nil))
               maf-history--index 0)
         (maf-history--render t))
  (with-current-buffer (maf-history--buffer)
    ;; Emptying the stack is a removal, and takes the `-' marker.
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "▸ - del\n  · entry\n"))
    (progn (goto-char (point-min)) (search-forward "-") (backward-char 1))
    (cl-assert (equal (get-text-property (point) 'face)
                      '(maf-history-removed maf-history-current))))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (string-match-p "(empty stack)"
                               (buffer-substring-no-properties (point-min) (point-max)))))
  (progn (setq maf-history--states nil maf-history--index 0)
         (maf-history--render t))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (equal header-line-format "maf-history"))
    (cl-assert (string-match-p "(no states yet)"
                               (buffer-substring-no-properties (point-min) (point-max)))))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (string-match-p "(no states yet)"
                               (buffer-substring-no-properties (point-min) (point-max)))))

  ;; Put the session's log back and re-render the browser over it.
  (progn
    (setq maf-history--states (nth 0 maf--history-render-stash)
          maf-history--index (nth 1 maf--history-render-stash))
    (maf-history--render t)))
