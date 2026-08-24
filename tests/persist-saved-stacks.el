;;; The saved-stacks buffer (modules/maf-persist.el): every save file
;; listed as a dial row with size, age and liveness, hovering a row
;; previews its stack in a window below, RET restores it, D deletes
;; the file. Driven against a scratch directory the way
;; persist-stack.el drives the save/restore core, with the session's
;; own persistence state stashed and put back at the end.

(require 'maf-persist)

(maf-step
  (setq pstacks--stash (list maf-stack-directory
                             maf-stack-session-name
                             maf--stack-session
                             maf--stack-restored
                             maf--stack-last-saved)
        maf-stack-directory (make-temp-file "maf-stacks-test" t)
        maf-stack-session-name "test-buf-a"
        maf--stack-session nil
        maf--stack-restored t
        maf--stack-last-saved 'pstacks--unset)

  ;; Three saved sessions: this one's, saved for real, and two written
  ;; by hand — no lock on either, so neither reads as live.
  (calc-wrapper (maf-push "6 x + 12") (maf-push "a + b"))
  (cl-assert (maf-save-stack))
  (let ((print-length nil) (print-level nil))
    (with-temp-file (maf--stack-file "test-buf-b")
      (prin1 (list (math-read-expr "y^2")) (current-buffer)))
    (with-temp-file (maf--stack-file "test-buf-c")
      (prin1 (list (math-read-expr "n!")) (current-buffer))))

  ;; Save times set apart by hand: three files written in one step
  ;; land on the same second, and rows sorted newest first would then
  ;; fall back on whatever order the directory listed them in. Spread
  ;; them and the list is c, b, a — which is what the ages shown, and
  ;; every row-order assertion below, actually rest on.
  (progn
    (set-file-times (maf--stack-file "test-buf-a") (time-subtract nil 300))
    (set-file-times (maf--stack-file "test-buf-b") (time-subtract nil 200))
    (set-file-times (maf--stack-file "test-buf-c") (time-subtract nil 100))
    (cl-assert (equal (mapcar #'car (maf--stack-saved-sessions))
                      '("test-buf-c" "test-buf-b" "test-buf-a")))
    :ordered)

  ;; The buffer lists every saved session, sized and aged, the
  ;; session's own row saying whose it is.
  (save-window-excursion
    (maf-saved-stacks)
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (cl-assert (string-match-p "test-buf-a.*2 entries.*(current session)" text))
      (cl-assert (string-match-p "test-buf-b.*1 entries" text))
      (cl-assert (not (string-match-p "test-buf-b.*live" text)))
      ;; Every row is a saved session, so the table names no group:
      ;; no Group column in the format, and the name at the margin.
      (cl-assert (not (dial--grouped-p)))
      (cl-assert (not (seq-find (lambda (col) (equal (car col) "Group"))
                                tabulated-list-format))
                 t "group column shown: %S" tabulated-list-format)
      (cl-assert (string-match-p "^ +test-buf-a" text))))

  ;; Hovering a row previews its saved stack, laid out as calc lays
  ;; out a stack: top of the stack on the last line, at level 1.
  (save-window-excursion
    (maf-saved-stacks)
    (goto-char (point-min))
    (search-forward "test-buf-a")
    (maf--stacks-preview)
    (cl-assert (eq maf--stacks-previewed (intern "test-buf-a")))
    (cl-assert (get-buffer-window "*maf-stacks preview*"))
    (with-current-buffer "*maf-stacks preview*"
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (cl-assert (equal text "2: 6 x + 12\n1: a + b"))))
    ;; Resting on the row redraws nothing; another row redraws to it.
    ;; The rows run newest save first, so b is the one above a.
    (maf--stacks-preview)
    (goto-char (point-min))
    (search-forward "test-buf-b")
    (maf--stacks-preview)
    (with-current-buffer "*maf-stacks preview*"
      (cl-assert (equal (buffer-substring-no-properties (point-min) (point-max))
                        "1: y^2"))))

  ;; Restoring replaces the current stack with the row's and closes
  ;; the buffer, preview and all.
  (save-window-excursion
    (maf-saved-stacks)
    (goto-char (point-min))
    (search-forward "test-buf-b")
    (maf-stacks-restore)
    (cl-assert (not (get-buffer-window "*maf-stacks*")))
    (cl-assert (not (get-buffer-window "*maf-stacks preview*"))))
  (cl-assert (= (calc-stack-size) 1))
  (cl-assert (string= (math-format-value (calc-top 1 'full)) "y^2"))

  ;; Deleting removes the file and the row, asking nothing; the buffer
  ;; stays while rows remain. `y-or-n-p' is stubbed to signal rather
  ;; than to answer: a prompt reintroduced here has to fail the test,
  ;; not sail through on the stub's yes.
  (save-window-excursion
    (maf-saved-stacks)
    (goto-char (point-min))
    (search-forward "test-buf-b")
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (_) (error "delete asked for confirmation"))))
      (maf-stacks-delete))
    (cl-assert (not (file-exists-p (maf--stack-file "test-buf-b"))))
    (cl-assert (null (assq (intern "test-buf-b") dial-items)))
    (cl-assert (get-buffer-window "*maf-stacks*"))
    ;; Point stayed on the line, which now holds the row that moved up
    ;; into the deleted one's place: b sat between c and a, so a.
    (cl-assert (eq (tabulated-list-get-id) (intern "test-buf-a"))
               t "point left the deleted row's place: %S"
               (tabulated-list-get-id))
    ;; The bottom row has nothing below to move up, so point takes the
    ;; row above instead. This is also the session's own row: only the
    ;; file goes, the live name lock stays.
    (maf-stacks-delete)
    (cl-assert (not (file-exists-p (maf--stack-file "test-buf-a"))))
    (cl-assert (file-exists-p (maf--stack-file "test-buf-a" ".lock")))
    (cl-assert (eq (tabulated-list-get-id) (intern "test-buf-c"))
               t "point left the last row's neighbour: %S"
               (tabulated-list-get-id))
    ;; Deleting the only row left closes the buffer.
    (maf-stacks-delete)
    (cl-assert (not (file-exists-p (maf--stack-file "test-buf-c"))))
    (cl-assert (not (get-buffer-window "*maf-stacks*"))))

  ;; An emptied directory refuses to open at all.
  (cl-assert (equal (condition-case err
                        (save-window-excursion (maf-saved-stacks))
                      (user-error (cadr err)))
                    (format "No saved stacks in %s" maf-stack-directory)))

  ;; Put the session's own persistence state back.
  (progn (calc-pop (calc-stack-size))
         (when (get-buffer "*maf-stacks*") (kill-buffer "*maf-stacks*"))
         (when (get-buffer "*maf-stacks preview*")
           (kill-buffer "*maf-stacks preview*"))
         (delete-directory maf-stack-directory t)
         (setq maf-stack-directory (nth 0 pstacks--stash)
               maf-stack-session-name (nth 1 pstacks--stash)
               maf--stack-session (nth 2 pstacks--stash)
               maf--stack-restored (nth 3 pstacks--stash)
               maf--stack-last-saved (nth 4 pstacks--stash))
         :cleaned))
