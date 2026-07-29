;; The selection badge (modules/maf-selplus.el): a box in the calc
;; header line for as long as any entry carries a selection, laid over
;; the left end of calc's own banner rather than replacing it.
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
  ;; badge has to share the line with it, not take it.
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

  ;; In a window wide enough for the badge to fit in the banner's
  ;; leading dashes it eats into them rather than pushing the banner
  ;; along: same total width, and "Emacs Calc" in the column it was in
  ;; before, so nothing slides sideways as the badge comes and goes.
  ;; The cockpit's calc window can be too narrow for that, in which
  ;; case the badge stands alone — checked directly on
  ;; `maf-selplus--compose' below, where the width is ours to set.
  (when (string-match-p "Emacs Calc" (maf-selplus-test--text))
    (cl-assert (= (length (maf-selplus-test--text))
                  (length maf-selplus-test--banner)))
    (cl-assert (= (string-match "Emacs Calc" (maf-selplus-test--text))
                  (string-match "Emacs Calc" maf-selplus-test--banner))))

  ;; `calc-refresh' rebuilds the banner from scratch, wiping the badge
  ;; out of `header-line-format'; the next update puts it back over the
  ;; new banner rather than mistaking it for a line of someone else's.
  (progn (let ((calc-show-banner t)) (calc-refresh)) (maf-selplus--update))
  (cl-assert (maf-selplus-test--badge-p))

  ;; maf-edit flies its own banner in the same place. The badge stays
  ;; away for as long as that session is up, and comes back after it —
  ;; the selection outlives the edit, so the state is still worth
  ;; showing.
  (progn (maf-edit-mode 1) (maf-selplus--update))
  (cl-assert (not (maf-selplus-test--badge-p)))
  (cl-assert (string-match-p "maf-edit" (maf-selplus-test--text)))
  (progn (maf-edit-discard) (maf-selplus--update))
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

  ;; The overlay arithmetic on its own, at widths the cockpit window
  ;; cannot be made to hold. A leading fill big enough for the badge is
  ;; cut into, keeping the banner's text put and the line's width with
  ;; it; too small a fill, or no header line to speak of, and the badge
  ;; stands alone rather than shoving the text sideways or eating into
  ;; it.
  (cl-assert (equal (maf-selplus--compose "[X] " "------ Calc ------")
                    "[X] -- Calc ------"))
  (cl-assert (equal (maf-selplus--compose "[X] " "-- Calc ------") "[X] "))
  (cl-assert (equal (maf-selplus--compose "[X] " nil) "[X] "))
  (cl-assert (equal (maf-selplus--compose "[X] " '("%b")) "[X] "))

  ;; The badge names the key that is really bound, so a rebinding
  ;; carries into it rather than being hardcoded.
  (cl-assert (equal (maf-selplus--clear-key) "RET"))
  (cl-assert (eq (key-binding (kbd "RET")) 'maf-dup-or-clear-selections)))
