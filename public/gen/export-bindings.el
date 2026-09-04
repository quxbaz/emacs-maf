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
              (doc . ,(maf-keys--doc cmd))
              (docfull . ,(or (ignore-errors (substitute-command-keys full)) full))
              (contextual . ,(if (get cmd 'maf-command) t :json-false))
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
