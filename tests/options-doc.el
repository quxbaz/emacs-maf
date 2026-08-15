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
  "Non-nil when the echo area is saying the current row's doc."
  (let ((doc (mafstep--doc-at-point)))
    (and doc (equal (current-message) doc))))

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
      (dial-next-line)
      (let ((row (tabulated-list-get-id)))
        (cl-assert (mafstep--echoes-doc-p) t "moving down: %s" row))))

  ;; And going back up, which walks the same rows in reverse.
  (mafstep--with-echo
    (dotimes (_ 5)
      (dial-previous-line)
      (let ((row (tabulated-list-get-id)))
        (cl-assert (mafstep--echoes-doc-p) t "moving up: %s" row))))

  ;; --- Group motion ---

  ;; M-n and M-p land on a setting too, so they say the same thing.
  (mafstep--with-echo
    (goto-char (point-min))
    (dial-next-line)
    (dial-next-group)
    (cl-assert (mafstep--echoes-doc-p) t "next group")
    (dial-previous-group)
    (cl-assert (mafstep--echoes-doc-p) t "previous group"))

  ;; --- Not logged ---

  ;; A line of help repeated down a list is not what *Messages* is for.
  ;; Checked by walking the whole list and finding the log unchanged.
  (mafstep--with-echo
    (goto-char (point-min))
    (let ((before (with-current-buffer (messages-buffer) (buffer-string))))
      (dotimes (_ (length maf-options-registry)) (dial-next-line))
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
    (dial-next-line)
    (let ((doc (current-message)))
      (goto-char (point-min))
      (cl-assert (null (mafstep--doc-at-point)))
      (dial--echo-doc)
      (cl-assert (equal (current-message) doc) t "a docless row blanked the echo")))

  )
