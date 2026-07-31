;; The selection badge (modules/maf-selplus.el): a box in the calc
;; header line for as long as any entry carries a selection, taking the
;; line from calc's own banner for the duration and handing it back
;; when the selection clears.
;;
;; `maf-selplus--update' rides `post-command-hook' in the real buffer;
;; these steps call it directly, as the maf-hl tests do, so each state
;; change is checked on its own.

(defvar maf-selplus-test--banner nil
  "Calc's own header line, captured before the badge goes over it.")

(defun maf-selplus-test--badge-p ()
  "Non-nil if the badge is currently up in this buffer."
  (and (stringp header-line-format)
       (string-prefix-p maf-selplus-badge-label header-line-format)))

(defun maf-selplus-test--text ()
  "The header line as plain text, or nil if there is none."
  (and (stringp header-line-format)
       (substring-no-properties header-line-format)))

(maf-step
  ;; Calc's banner is what the header line holds to begin with; the
  ;; badge takes the line from it and gives it back.
  (maf-selplus-mode 1)
  (let ((calc-show-banner t)) (calc-refresh))
  (maf-selplus--update)
  (cl-assert (stringp header-line-format))
  (cl-assert (string-match-p "Emacs Calc" header-line-format))
  (cl-assert (not (maf-selplus-test--badge-p)))
  (setq maf-selplus-test--banner (maf-selplus-test--text))

  ;; A selection puts the badge up, in the `maf-selplus-badge' face,
  ;; with the key that clears it — RET, the dispatcher's binding.
  (maf-push "a + b c")
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (call-interactively 'calc-select-here)
  (maf-selplus--update)
  (cl-assert (maf-selplus-test--badge-p))
  (cl-assert (eq (get-text-property 1 'face header-line-format)
                 'maf-selplus-badge))
  (cl-assert (string-match-p "RET clear" (maf-selplus-test--text)))

  ;; The badge is the whole line while it is up: calc's banner is out
  ;; of the way, so the indicator reads as a state and not as part of
  ;; the decoration it would otherwise sit in.
  (cl-assert (not (string-match-p "Emacs Calc" (maf-selplus-test--text))))
  (cl-assert (equal (maf-selplus-test--text)
                    (substring-no-properties (maf-selplus--header-line))))

  ;; `calc-refresh' rebuilds the banner from scratch, wiping the badge
  ;; out of `header-line-format'; the next update puts it back over the
  ;; new banner rather than mistaking it for a line of someone else's.
  (progn (let ((calc-show-banner t)) (calc-refresh)) (maf-selplus--update))
  (cl-assert (maf-selplus-test--badge-p))

  ;; maf-edit would fly its own banner in the same place, but the two
  ;; never come to share the line: it refuses to start while a selection
  ;; is shown, since the masked display would hand it a mask of the
  ;; formula instead of the formula (see `maf-edit--enter'). The badge is
  ;; left standing by the refusal, banner and all.
  (cl-assert (eq :refused
                 (condition-case nil
                     (progn (maf-edit-mode 1) :entered)
                   (error :refused))))
  (maf-selplus--update)
  (cl-assert (not (bound-and-true-p maf-edit-mode)))
  (cl-assert (maf--sel-any-p))
  (cl-assert (maf-selplus-test--badge-p))

  ;; Clearing the selection hands the line back exactly as it was.
  (progn (call-interactively 'maf-clear-selections) (maf-selplus--update))
  (cl-assert (not (maf--sel-any-p)))
  (cl-assert (not (maf-selplus-test--badge-p)))
  (cl-assert (equal (maf-selplus-test--text) maf-selplus-test--banner))

  ;; Turning the mode off with the badge up takes it down too, rather
  ;; than leaving a frozen badge behind.
  (progn (goto-char (point-min)) (search-forward "b") (backward-char 1))
  (progn (call-interactively 'calc-select-here) (maf-selplus--update))
  (cl-assert (maf-selplus-test--badge-p))
  (maf-selplus-mode -1)
  (cl-assert (equal (maf-selplus-test--text) maf-selplus-test--banner))
  (progn (maf-selplus-mode 1)
         (call-interactively 'maf-clear-selections)
         (calc-pop (calc-stack-size)))

  ;; The line is the badge and the way out of the state, nothing else —
  ;; the shape maf-edit's banner has.
  (cl-assert (string-prefix-p maf-selplus-badge-label
                              (maf-selplus--header-line)))
  (cl-assert (string-suffix-p "clear" (maf-selplus--header-line)))

  ;; The badge names the key that is really bound, so a rebinding
  ;; carries into it rather than being hardcoded.
  (cl-assert (equal (maf-selplus--clear-key) "RET"))
  (cl-assert (eq (key-binding (kbd "RET")) 'maf-dup-or-clear-selections)))
