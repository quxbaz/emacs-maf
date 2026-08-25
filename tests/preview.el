(maf-step
  (maf-use-preview-mode 1)
  (calc-normal-language)
  (calc-push '(/ (var a var-a) (var b var-b)))
  (calc-refresh)

  ;; The active entry renders in 2D Big form for the preview, while the
  ;; stack itself stays in the one-line normal display.
  (progn (goto-char (point-min)) (search-forward "a / b") (backward-char 3))
  (cl-assert (equal (maf-preview--render) "a\n-\nb"))
  (cl-assert (string-match-p "a / b" (buffer-substring-no-properties
                                      (point-min) (point-max))))

  ;; The preview shows the entry as it stands on the stack, not what calc
  ;; would make of it: an unsimplified formula previews unsimplified,
  ;; matching its stack line (`calc-top', not the normalizing
  ;; `calc-top-n', which would preview this one as "5 a").
  (progn (calc-push '(+ (* 2 (var a var-a)) (* 3 (var a var-a))))
         (calc-refresh)
         (goto-char (point-min)) (search-forward "2 a + 3 a") (backward-char 3))
  (cl-assert (equal (maf-preview--render) "2 a + 3 a"))
  (progn (calc-pop 1) (calc-refresh)
         (goto-char (point-min)) (search-forward "a / b") (backward-char 3))

  ;; Long vectors are always abbreviated in the preview, whatever the
  ;; buffer's `v .' setting: a full 100-element vector would make the
  ;; panel taller than the window.
  (progn (calc-push (cons 'vec (number-sequence 1 100)))
         (calc-refresh)
         (goto-char (point-min)) (search-forward "[1, 2, 3") (backward-char 3))
  (let ((calc-full-vectors t))
    (cl-assert (equal (maf-preview--render) "[1, 2, 3, ..., 100]")))
  (progn (calc-pop 1) (calc-refresh)
         (goto-char (point-min)) (search-forward "a / b") (backward-char 3))

  ;; The rendered entry is laid out as a bordered, titled panel whose
  ;; rows are all one width — what both backends put on screen.
  (cl-assert (equal (maf-preview--panel-rows "a\n-\nb" 40 10)
                    '("┌─PREVIEW──┐"
                      "│ a        │"
                      "│ -        │"
                      "│ b        │"
                      "└──────────┘")))

  ;; The panel is clipped to the room it is given, in both directions,
  ;; with an ellipsis for what was cut — and refused outright when even
  ;; the title would not fit.
  (cl-assert (equal (maf-preview--panel-rows "abcdefghijklmnopqrst" 16 10)
                    '("┌─PREVIEW──────┐"
                      "│ abcdefghijk… │"
                      "└──────────────┘")))
  (cl-assert (equal (maf-preview--panel-rows "1\n2\n3\n4" 40 5)
                    '("┌─PREVIEW──┐"
                      "│ 1        │"
                      "│ 2        │"
                      "│ …        │"
                      "└──────────┘")))
  (cl-assert (null (maf-preview--panel-rows "x" 11 10)))

  ;; Without a child frame — on a text terminal, or with no posframe —
  ;; that panel is drawn inside the window itself. It lives entirely in
  ;; overlay strings anchored below the window's first line, so it stays
  ;; at the top of the view rather than following the entry, and the
  ;; buffer's own text is left alone.
  (when (not (maf-preview--posframe-p))
    (maf-preview--update)
    (let ((drawn (mapconcat (lambda (ov)
                              (or (overlay-get ov 'display)
                                  (overlay-get ov 'after-string)
                                  ""))
                            ;; Pushed as they are drawn, so the topmost
                            ;; row of the panel is the last one.
                            (reverse maf-preview--overlays)
                            "\n")))
      (cl-assert (string-match-p "PREVIEW" drawn))
      (cl-assert (string-match-p "│ a" drawn))
      (cl-assert (not (string-match-p "PREVIEW" (buffer-substring-no-properties
                                                 (point-min) (point-max)))))
      (cl-assert (= (line-number-at-pos
                     (overlay-start (car (last maf-preview--overlays))))
                    (1+ (line-number-at-pos (window-start))))))

    ;; Turning the mode off takes the panel down with it.
    (maf-preview-mode -1)
    (cl-assert (null maf-preview--overlays))
    (maf-preview-mode 1))

  ;; Nothing to preview while the whole buffer is already in Big display.
  (calc-big-language)
  (cl-assert (null (maf-preview--render)))
  (calc-normal-language)
  (calc-refresh)
  (progn (goto-char (point-min)) (search-forward "a / b") (backward-char 3))
  (cl-assert (maf-preview--render))

  ;; Nothing to preview during an in-place edit session (the stack no
  ;; longer matches the edited text).
  (call-interactively 'maf-edit)
  (cl-assert (null (maf-preview--render)))
  (call-interactively 'maf-edit-discard)

  ;; Nothing to preview on an empty stack.
  (calc-pop (calc-stack-size))
  (cl-assert (null (maf-preview--render)))

  ;; --- a panel taken down from outside comes back ---

  ;; The redraw cache describes what the panel was drawn from, not
  ;; whether it is still up. A window manager iconifying the child frame,
  ;; or anything deleting the overlays, leaves the cache matching while
  ;; the screen is empty — and the update that would put the panel back
  ;; is the one the cache suppresses. `maf-preview--on-screen-p' is what
  ;; breaks that tie, so an unchanged entry recovers on the next command.
  ;; Driven on the in-window backend, whose panel is inspectable either
  ;; way (a child frame is not, on a terminal).
  (maf-push "a + b")
  (progn (calc-cursor-stack-index 1) (end-of-line))
  (cl-letf (((symbol-function 'maf-preview--posframe-p) (lambda () nil)))
    (maf-preview--hide)
    (maf-preview--update)
    (cl-assert maf-preview--overlays)
    (cl-assert (maf-preview--on-screen-p))
    ;; Taken down behind the module's back: the cache still stands.
    (mapc #'delete-overlay maf-preview--overlays)
    (cl-assert (not (maf-preview--on-screen-p)))
    (cl-assert maf-preview--state)
    ;; Same entry, so every cached input matches — it is the missing
    ;; panel alone that has to force the redraw.
    (maf-preview--update)
    (cl-assert (maf-preview--on-screen-p))
    (maf-preview--hide))
  (calc-pop (calc-stack-size))

  ;; --- the peek: a panel asked for by hand ---

  ;; The module is the panel that *follows point*, and with it off
  ;; nothing is previewed on its own. G is not the module's key,
  ;; though, so it still answers here — one look, asked for by hand.
  (maf-use-preview-mode -1)
  (cl-assert (null maf-preview-mode))
  (cl-assert (null maf-preview--overlays))
  (cl-assert (eq (key-binding (kbd "G")) 'maf-preview-show))

  (progn (maf-push "a / b") (calc-cursor-stack-index 1) (end-of-line))

  ;; A peek is one panel over the entry at point, put up by G and taken
  ;; down by the next command — which is why each press and the checks
  ;; on what it left are one step here: stepping is itself a command,
  ;; and would take the peek down before the next form ran.
  ;;
  ;; Driven on the in-window backend, the one whose panel is
  ;; inspectable on a terminal and off it alike.
  (cl-letf (((symbol-function 'maf-preview--posframe-p) (lambda () nil)))
    ;; Asking for a look at this entry is not asking to be shown every
    ;; entry after it: the peek leaves the mode off.
    (execute-kbd-macro (kbd "G"))
    (cl-assert (eq maf-preview--peek-buffer (current-buffer)))
    (cl-assert maf-preview--overlays)
    (cl-assert (null maf-preview-mode))

    ;; The asking key is the one command a peek survives, so a second
    ;; press is another look rather than a dismissal.
    (execute-kbd-macro (kbd "G"))
    (cl-assert maf-preview--overlays)

    ;; Any other command takes it down, and the hooks holding it up go
    ;; with it.
    (execute-kbd-macro (kbd "C-n"))
    (cl-assert (null maf-preview--overlays))
    (cl-assert (null maf-preview--peek-buffer))
    (cl-assert (not (memq 'maf-preview--peek-end post-command-hook))))

  ;; With the module back on the mode is on again in the calc buffer,
  ;; and the panel is drawn without anything asking for it.
  (maf-use-preview-mode 1)
  (cl-assert maf-preview-mode)
  (cl-letf (((symbol-function 'maf-preview--posframe-p) (lambda () nil)))
    (progn (calc-cursor-stack-index 1) (end-of-line))
    (maf-preview--update)
    (cl-assert maf-preview--overlays)
    (maf-preview--hide))
  (calc-pop (calc-stack-size)))
