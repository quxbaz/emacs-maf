;;; Tests for the options menu's example echo -- stepping shows a sample.
;;
;; A registry entry may carry a `:sample', and stepping its row formats
;; the sample under the value just set, echoing two lines — "Option:
;; VALUE" then "Example: ..." — in place of the label-and-value
;; message. Rows without a sample, and the set and reset commands, keep
;; the plain echo.
;;
;; Same workaround as options-doc.el: the step harness binds
;; `inhibit-message', which keeps output out of the echo area and so
;; out of `current-message', so the macro below lifts the binding. The
;; commands are called rather than pressed for the same reason as
;; there — a keyboard macro suppresses echo-area display entirely.
;;
;; The literal strings asserted against assume each row starts on its
;; default. The harness's fresh calc buffer still wears the session's
;; modes — mode variables are calc globals — so each block resets its
;; row before stepping rather than trusting the session.

(defmacro mafstep-ex--with-echo (&rest body)
  "Run BODY in the options buffer with the echo area live."
  (declare (indent 0))
  `(with-current-buffer (save-window-excursion
                          (maf-options)
                          (get-buffer "*maf-options*"))
     (let ((inhibit-message nil))
       ,@body)))

(defun mafstep-ex--goto-row (id)
  "Put point on ID's row."
  (goto-char (point-min))
  (while (not (eq (tabulated-list-get-id) id)) (forward-line 1))
  (dial--goto-option))

(maf-step

  ;; The examples are calc's live rendering, so they depend on modes
  ;; far beyond the row being stepped — the display language above all.
  ;; Other suite files leave the session's modes behind them, so start
  ;; from calc's factory defaults.
  (with-current-buffer "*Calculator*" (maf--reset-calc 0))

  ;; --- Stepping echoes the example ---

  ;; Digit grouping is the canonical case: the same number under each
  ;; value, with and without separators. The first line names the
  ;; option and the value just landed on, so the echo reads on its own
  ;; without looking back at the row.
  (mafstep-ex--with-echo
    (mafstep-ex--goto-row 'calc-group-digits)
    (dial-reset)
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Digit grouping: on\nExample: 999,999")
               t "grouping on")
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Digit grouping: off\nExample: 999999")
               t "grouping off"))

  ;; The example is calc's own rendering under the value just set, not
  ;; a canned string: the radix row re-renders its sample in each base.
  (mafstep-ex--with-echo
    (mafstep-ex--goto-row 'calc-number-radix)
    (dial-reset)
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Radix: binary\nExample: 2#1100100")
               t "binary")
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Radix: octal\nExample: 8#144")
               t "octal")
    (dial-reset))

  ;; A sample may be a function, for when producing it depends on the
  ;; setting itself: fraction mode's sample is the division 3/4, whose
  ;; answer is the thing the mode decides.
  (mafstep-ex--with-echo
    (mafstep-ex--goto-row 'calc-prefer-frac)
    (dial-reset)
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Fraction mode: on\nExample: 3:4")
               t "frac on")
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Fraction mode: off\nExample: 0.75")
               t "frac off"))

  ;; --- A row without a sample keeps the plain echo ---

  ;; Angle measure shapes computation, not a printed value, so it has
  ;; no sample and stepping it says what it always said.
  (mafstep-ex--with-echo
    (mafstep-ex--goto-row 'calc-angle-mode)
    (dial-reset)
    (dial-next-value)
    (cl-assert (equal (current-message) "Angle measure: radians") t
               "no-sample row")
    (dial-reset)
    ;; And reset keeps the plain echo even on a sampled row's sibling
    ;; path: it lands on a value already chosen, not a tour stop.
    (cl-assert (equal (current-message) "Angle measure: degrees") t
               "reset echo"))

  ;; --- A prompting value still steps onto, not into, its example ---

  ;; Fixed point prompts for its digit count, so stepping onto it sets
  ;; nothing — and shows no example of a value that has not landed.
  (mafstep-ex--with-echo
    (mafstep-ex--goto-row 'calc-float-format)
    (dial-reset)
    (dial-next-value)
    (cl-assert (string-match-p "needs a value" (current-message)) t
               "pending, not exemplified")
    (dial-next-value)
    (cl-assert (equal (current-message)
                      "Float format: scientific\nExample: 1.23456789e4")
               t "scientific")
    (dial-reset))

  )
