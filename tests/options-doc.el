;;; Tests for the options menu's help echo -- one line per row.
;;
;; Every registry entry carries a `:doc', and moving between rows says
;; it in the echo area. The checks below read `current-message' rather
;; than the *Messages* log on purpose: the echo is deliberately not
;; logged, since it fires on every motion key.
;;
;; Two things the checks have to work around.
;;
;; The step harness runs each form under `inhibit-message', which keeps
;; output out of the echo area — and so out of `current-message' — and
;; watches the *Messages* delta instead. An echo that never logs is
;; invisible to both, so `mafstep--with-echo' below lifts the binding.
;;
;; The motion commands are called rather than pressed. A keyboard macro
;; would be the closer test, but Emacs suppresses echo-area display
;; while one runs, so `current-message' is nil under `execute-kbd-macro'
;; for any message at all — there would be nothing to assert on.

(defmacro mafstep--with-echo (&rest body)
  "Run BODY in the options buffer with the echo area live."
  (declare (indent 0))
  `(with-current-buffer (save-window-excursion
                          (maf-options)
                          (get-buffer "*maf-options*"))
     (let ((inhibit-message nil))
       ,@body)))

(defun mafstep--doc-at-point ()
  "The `:doc' of the row point is on."
  (plist-get (alist-get (tabulated-list-get-id) maf-options-registry) :doc))

(defun mafstep--echoes-doc-p ()
  "Non-nil when the echo area is saying the current row's doc.
The line is the doc followed by a hint at where a step would go, so the
doc is matched as its head rather than as the whole of it."
  (let ((doc (mafstep--doc-at-point))
        (msg (current-message)))
    (and doc msg (string-prefix-p doc msg))))

(defun mafstep--goto-row (var)
  "Put point on VAR's row, from the top of the list.
Bounded by the list's own length rather than by `eobp': motion stays
put where there is no row left to reach, so a row that never turns up
would spin here forever and take the Emacs it is running in with it."
  (goto-char (point-min))
  (setq maf-options--pending nil)
  (let ((left (length maf-options-registry)))
    (while (and (not (eq (tabulated-list-get-id) var)) (> left 0))
      (maf-options-next-line)
      (setq left (1- left))))
  (cl-assert (eq (tabulated-list-get-id) var) t "no row for %s" var))

(defun mafstep--step-to-pending (values)
  "Step the current row until a value is left pending.
Bounded to one turn of the row: with the step landing somewhere other
than expected, this would otherwise cycle the row forever."
  (let ((left (length values)))
    (while (and (not maf-options--pending) (> left 0))
      (maf-options-next-value 1)
      (setq left (1- left))))
  (cl-assert maf-options--pending t "no value on this row was left pending"))

(maf-step

  ;; --- The registry ---

  ;; The echo has nothing to say for a row whose spec left `:doc' out,
  ;; so the menu is only as helpful as the table is complete.
  (let ((missing (mapcar #'car (seq-remove (lambda (e) (plist-get (cdr e) :doc))
                                           maf-options-registry))))
    (cl-assert (null missing) t "settings with no :doc: %S" missing))

  ;; --- Moving down and up ---

  ;; Each step says what the row it landed on is for. Asserted against
  ;; the row's own spec rather than a literal sentence, so rewording a
  ;; doc does not break the test.
  (mafstep--with-echo
    (goto-char (point-min))
    (dotimes (_ 8)
      (maf-options-next-line)
      (let ((row (tabulated-list-get-id)))
        (cl-assert (mafstep--echoes-doc-p) t "moving down: %s" row))))

  ;; And going back up, which walks the same rows in reverse.
  (mafstep--with-echo
    (dotimes (_ 5)
      (maf-options-previous-line)
      (let ((row (tabulated-list-get-id)))
        (cl-assert (mafstep--echoes-doc-p) t "moving up: %s" row))))

  ;; --- Group motion ---

  ;; M-n and M-p land on a setting too, so they say the same thing.
  (mafstep--with-echo
    (goto-char (point-min))
    (maf-options-next-line)
    (maf-options-next-group)
    (cl-assert (mafstep--echoes-doc-p) t "next group")
    (maf-options-previous-group)
    (cl-assert (mafstep--echoes-doc-p) t "previous group"))

  ;; --- The step hint ---

  ;; The line ends with where a step would go. Checked end to end
  ;; rather than against the helper that produced it: the hint names a
  ;; value, and stepping has to land on that same value, which is the
  ;; off-by-one the shared index exists to rule out.
  (mafstep--with-echo
    (mafstep--goto-row 'calc-angle-mode)
    (cl-assert (string-match "TAB: \\(.*\\)\\'" (current-message)) t "no hint")
    (let ((promised (match-string 1 (current-message))))
      (maf-options-next-value 1)
      (cl-assert (equal promised (maf-options--value-string
                                  'calc-angle-mode
                                  (alist-get 'calc-angle-mode maf-options-registry)))
                 t "hint said %s" promised)))

  ;; A row whose value can only be prompted for gets the key that works
  ;; on it. TAB is not that key -- it errors -- so naming it would be
  ;; worse than saying nothing.
  (mafstep--with-echo
    (mafstep--goto-row 'calc-internal-prec)
    (cl-assert (string-suffix-p "RET: prompts" (current-message)) t
               "echoed: %s" (current-message))
    (cl-assert (not (string-match-p "TAB" (current-message))))
    (cl-assert (equal '(error) (condition-case nil (maf-options-next-value 1)
                                 (user-error '(error))))
               t "TAB did not error on a prompt-only row"))

  ;; Stepping onto a value that prompts leaves it pending rather than
  ;; setting it, and the hint counts on from there -- the same place
  ;; the next step counts from.
  (mafstep--with-echo
    (mafstep--goto-row 'calc-float-format)
    (let ((values (mapcar #'cadr (maf-options--values
                                  'calc-float-format
                                  (alist-get 'calc-float-format
                                             maf-options-registry)))))
      (mafstep--step-to-pending values)
      (maf-options--echo-doc)
      (let ((after-pending (nth (mod (1+ (cdr maf-options--pending)) (length values))
                                values)))
        (cl-assert (string-suffix-p (concat "TAB: " after-pending) (current-message))
                   t "pending %S, echoed: %s" maf-options--pending (current-message)))
      (setq maf-options--pending nil)))

  ;; --- Too narrow for the hint ---

  ;; The echo area growing to two lines under every motion key costs
  ;; more than the hint is worth, so on a window that cannot hold both
  ;; the doc goes out alone.
  (mafstep--with-echo
    (mafstep--goto-row 'calc-angle-mode)
    (cl-assert (string-match-p "TAB" (current-message)))
    (cl-letf (((symbol-function 'frame-width) (lambda (&rest _) 40)))
      (maf-options--echo-doc)
      (cl-assert (equal (current-message) (mafstep--doc-at-point)) t
                 "echoed: %s" (current-message))))

  ;; --- Not logged ---

  ;; A line of help repeated down a list is not what *Messages* is for.
  ;; Checked by walking the whole list and finding the log unchanged.
  (mafstep--with-echo
    (goto-char (point-min))
    (let ((before (with-current-buffer (messages-buffer) (buffer-string))))
      (dotimes (_ (length maf-options-registry)) (maf-options-next-line))
      (cl-assert (mafstep--echoes-doc-p) t "reached the last row")
      (cl-assert (equal before (with-current-buffer (messages-buffer)
                                 (buffer-string)))
                 t "the echo reached *Messages*")))

  ;; --- Nothing to say ---

  ;; The gap rows between groups have no doc, and motion never lands on
  ;; one; reaching one another way leaves the echo area alone rather
  ;; than blanking whatever was last said.
  (mafstep--with-echo
    (goto-char (point-min))
    (maf-options-next-line)
    (let ((doc (current-message)))
      (goto-char (point-min))
      (cl-assert (null (mafstep--doc-at-point)))
      (maf-options--echo-doc)
      (cl-assert (equal (current-message) doc) t "a docless row blanked the echo")))

  )
