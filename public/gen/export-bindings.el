;;; export-bindings.el --- Write public/data/bindings.json from a live maf  -*- lexical-binding: t; -*-

;; Run inside an Emacs with maf loaded, from the repository root:
;;
;;   emacsclient -s '#emacs' --eval '(load-file "public/gen/export-bindings.el")'
;;
;; Every profile's groups come from `maf-keys--groups', the same taxonomy
;; the *maf-keys* buffer renders, so the site and the help buffer agree.
;; The I/H variants come from the mafcmd table rows. Then run
;; gen/finish-bindings.py to normalize nulls and emit the .js file.

(require 'json)
(require 'lisp-mnt)


;; Examples as LaTeX, for the cheat sheet's typeset toggle. An example
;; reads "INPUTS => RESULT", the inputs comma-separated calc syntax;
;; each piece that calc can read composes through maf's own LaTeX
;; writer, and a piece it cannot — prose like "by +", a date, an hms
;; form — goes out as text.
(defun maf-site--split-top (s sep)
  "Split S on SEP characters at bracket depth zero."
  (let ((depth 0) (start 0) (i 0) out)
    (while (< i (length s))
      (let ((c (aref s i)))
        (cond ((memq c '(?\( ?\[ ?\{ ?<)) (setq depth (1+ depth)))
              ((memq c '(?\) ?\] ?\} ?>)) (setq depth (max 0 (1- depth))))
              ((and (eq c sep) (zerop depth))
               (push (substring s start i) out) (setq start (1+ i)))))
      (setq i (1+ i)))
    (push (substring s start) out)
    (nreverse out)))

(defun maf-site--text (s)
  (format "\\text{%s}" (replace-regexp-in-string "\\([&%$#_{}^\\\\]\\)" "\\\\\\1" s)))

(defun maf-site--piece-latex (s)
  (let ((s (string-trim s)))
    (cond ((string-empty-p s) "")
          ;; Prose: two words of two letters or more, or three or more words.
          ((string-match-p "\\`\\(?:[a-zA-Z][a-zA-Z]+ [a-zA-Z][a-zA-Z]+\\|[a-zA-Z]+ [a-zA-Z]+ [a-zA-Z ]+\\)\\'" s) (maf-site--text s))
          ((string-match-p "[<@]" s) (maf-site--text s))
          (t (let ((v (ignore-errors (math-read-expr s))))
               (if (or (null v) (eq (car-safe v) 'error)) (maf-site--text s)
                 (condition-case nil
                     (let ((maf--latex-typeset-quantities t)) (maf--latex-string v))
                   (error (maf-site--text s)))))))))

(defun maf-site--example-latex (ex)
  (if (or (null ex) (string-match-p "\n" ex)) :null
    (mapconcat (lambda (side)
                 (mapconcat #'maf-site--piece-latex (maf-site--split-top side ?,) ",\\; "))
               (split-string ex "=>") " \\;\\Rightarrow\\; ")))

;; The same example split into stack levels, for the cheat sheet's
;; stack-format rendering: INPUTS are the comma-separated pieces before
;; the arrow, the last one level 1; RESULT is everything after it.
(defun maf-site--example-parts (ex)
  (if (or (null ex) (string-match-p "\n" ex)) :null
    (let* ((at (string-match "=>" ex))
           (lhs (if at (substring ex 0 at) ex))
           (rhs (if at (string-trim (substring ex (+ at 2))) ""))
           (inputs (seq-remove #'string-empty-p
                               (mapcar #'string-trim (maf-site--split-top lhs ?,)))))
      `((inputs . ,(vconcat inputs))
        (result . ,rhs)
        (inputs_latex . ,(vconcat (mapcar #'maf-site--piece-latex inputs)))
        (result_latex . ,(mapconcat #'maf-site--piece-latex (maf-site--split-top rhs ?,) ",\\; "))))))

;; Whether a command has a counterpart in stock Calc: a table row wrapping
;; a calcFunc, or a calc- command of the same suffix. What is left is
;; new with maf.
(defconst maf-site--calc-analogs
  '(mafcmd-vconcat mafcmd-fold mafcmd-accum mafcmd-outer mafcmd-inner
    mafcmd-neg maf-del maf-copy maf-dup maf-dup-or-clear-selections
    maf-dup-here-or-clear-selections maf-dup-here maf-dup-go maf-digit-start
    maf-digit-quit maf-digit-commit-contextual maf-digit-commit-here
    maf-reset-settings maf-recall-variable maf-roll-to-top maf-roll-to-bottom
    maf-plot-embed maf-plot-desmos maf-plot-gnuplot maf-toggle-simplify
    maf-edit-add-entry-above maf-edit-add-entry-below)
  "Commands whose Calc counterpart goes by another name: concat, reduce,
accumulate, the outer and inner products, pop, copy-as-kill, enter,
digit entry, reset, recall, roll, the graph commands, the simplify
mode toggle. Not caught by the name rule below.")

(defun maf-site--calc-analog-p (cmd)
  (let* ((row (assq cmd maf-cmds--table))
         (name (symbol-name cmd))
         (suffix (cond ((string-prefix-p "mafcmd-" name) (substring name 7))
                       ((string-prefix-p "maf-" name) (substring name 4)))))
    (or (memq cmd maf-site--calc-analogs)
        (and row (symbolp (nth 2 row))
             (string-prefix-p "calcFunc-" (symbol-name (nth 2 row))))
        (and suffix (fboundp (intern (concat "calc-" suffix)))))))

(let* ((root (locate-dominating-file (or load-file-name default-directory) "maf.el"))
       (out-file (expand-file-name "public/data/bindings.json" root))
       (item-of
        (lambda (cmd keys)
          (let ((row (assq cmd maf-cmds--table))
                (full (or (ignore-errors (documentation cmd)) "")))
            `((cmd . ,(symbol-name cmd))
              (keys . ,(vconcat keys))
              (title . ,(or (maf-command-title cmd) :null))
              (example . ,(or (maf-command-example cmd) :null))
              (example_latex . ,(maf-site--example-latex (maf-command-example cmd)))
              (example_parts . ,(maf-site--example-parts (maf-command-example cmd)))
              (doc . ,(maf-keys--doc cmd))
              (docfull . ,(or (ignore-errors (substitute-command-keys full)) full))
              (contextual . ,(if (get cmd 'maf-command) t :json-false))
              (new . ,(if (maf-site--calc-analog-p cmd) :json-false t))
              (inv . ,(or (and row (nth 4 row) (symbol-name (nth 4 row))) :null))
              (hyp . ,(or (and row (nth 5 row) (symbol-name (nth 5 row))) :null))
              (invhyp . ,(or (and row (nth 6 row) (symbol-name (nth 6 row))) :null))))))
       (variants
        (let (syms)
          (dolist (row maf-cmds--table)
            (dolist (s (list (nth 4 row) (nth 5 row) (nth 6 row)))
              (when (and s (fboundp s)) (cl-pushnew s syms))))
          (mapcar (lambda (s)
                    `((cmd . ,(symbol-name s))
                      (title . ,(or (maf-command-title s) :null))
                      (example . ,(or (maf-command-example s) :null))
                      (example_latex . ,(maf-site--example-latex (maf-command-example s)))
                      (example_parts . ,(maf-site--example-parts (maf-command-example s)))
                      (doc . ,(maf-keys--doc s))))
                  syms)))
       (out
        `((generated . ,(format-time-string "%Y-%m-%d"))
          (version . ,(lm-version (expand-file-name "maf.el" root)))
          (default_profile . "native")
          (profiles
           . ,(mapcar
               (lambda (p)
                 (let ((maf-bindings-profile p))
                   `((name . ,(symbol-name p))
                     (description . ,(or (plist-get (maf-bindings--profile p) :description) ""))
                     (groups
                      . ,(vconcat
                          (mapcar (lambda (g)
                                    `((title . ,(car g))
                                      (items . ,(vconcat (mapcar (lambda (it) (funcall item-of (car it) (cdr it)))
                                                                 (cdr g))))))
                                  (maf-keys--groups)))))))
               '(native calc vim)))
          (variants . ,variants))))
  (with-temp-file out-file (insert (json-encode out)))
  out-file)
