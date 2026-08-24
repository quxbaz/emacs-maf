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

  ;; The log: one line per state, oldest at the top, the current one
  ;; marked and wearing the current face. Each line carries its state's
  ;; index, and point rests on the current line. The header line counts
  ;; the position, oldest to newest, matching the layout.
  (with-current-buffer (maf-history--buffer)
    (maf-history--render t)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "  entry\n▸ mult\n"))
    (cl-assert (equal header-line-format "maf-history  2/2"))
    (cl-assert (= (line-number-at-pos) 2))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 0))
    (cl-assert (eq (get-text-property (point) 'face) 'maf-history-current))
    (progn (goto-char (point-min)))
    (cl-assert (= (get-text-property (point) 'maf-history-index) 1))
    (cl-assert (null (get-text-property (point) 'face))))

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
      (cl-assert (string-match-p "n/p/j/k step" legend))
      (cl-assert (string-match-p "RET insert" legend))
      (cl-assert (string-match-p "o/h/l switch" legend))
      (cl-assert (not (string-match-p "calc" legend)))))

  ;; Selecting the older state re-renders both: the marker moves, and
  ;; the stack follows. The oldest state has no reference to diff
  ;; against, so nothing in it is highlighted.
  (progn (setq maf-history--index 1) (maf-history--render t))
  (with-current-buffer (maf-history--buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "▸ entry\n  mult\n"))
    (cl-assert (= (line-number-at-pos) 1))
    (cl-assert (equal header-line-format "maf-history  1/2")))
  (with-current-buffer (maf-history--stack-buffer)
    (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                      "1:  5\n"))
    (progn (goto-char (point-min)))
    (cl-assert (null (get-text-property (point) 'face))))

  ;; An empty stack renders as its placeholder, and an empty log leaves
  ;; the counter off the header and says so in both windows.
  (progn (setq maf-history--states (list (list nil "del") (list (list 5) nil))
               maf-history--index 0)
         (maf-history--render t))
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
