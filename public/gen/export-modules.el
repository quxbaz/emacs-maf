;;; export-modules.el --- Write public/data/modules.json from a live maf  -*- lexical-binding: t; -*-

;; Run inside an Emacs with maf loaded, from the repository root:
;;   emacsclient -s '#emacs' --eval '(load-file "public/gen/export-modules.el")'
;; The groups and their order are the module menu's own (m c), read from
;; the registry; each module carries its summary, entry keys, shipped
;; default, and the details text the menu shows.

(require 'json)
(require 'seq)

(defun maf-site--default-form (sym)
  "SYM's shipped default as the source form its defcustom wrote.
custom stores it as (funcall (function (lambda () FORM))), the lambda
an interpreted closure in a compiled file; the FORM is dug back out.
A string value is shown with the home directory abbreviated."
  (let* ((form (car (get sym 'standard-value)))
         (fn (and (eq (car-safe form) 'funcall)
                  (eq (car-safe (nth 1 form)) 'function)
                  (nth 1 (nth 1 form)))))
    (cond ((and (consp fn) (eq (car fn) 'lambda)) (setq form (car (last fn))))
          ((and fn (fboundp 'interpreted-function-p) (interpreted-function-p fn))
           (setq form (car (last (aref fn 1))))))
    (if (stringp form) (abbreviate-file-name form) form)))

(defun maf-site--module-record (it)
  (let* ((name (car it))
         (entry (assq name maf-module-registry))
         (keys (maf-module--keys name (nth 3 entry))))
    (list (cons 'name (symbol-name name))
          (cons 'mode (symbol-name (nth 1 entry)))
          (cons 'default_on (if (maf-module--default name) t :json-false))
          (cons 'keys (or keys :null))
          (cons 'summary (or (maf-module--summary (nth 2 entry)) ""))
          (cons 'doc (substring-no-properties (or (plist-get (cdr it) :doc) "")))
          ;; The mode docstrings and the options with their shipped
          ;; defaults, as source forms: nothing read from the live
          ;; session, whose state and settings are this machine's.
          (cons 'sections (vconcat (mapcar (lambda (sec) (list (cons 'title (symbol-name (car sec)))
                                                              (cons 'text (substring-no-properties (cdr sec)))))
                                           (ignore-errors (maf-module--mode-sections (nth 1 entry))))))
          (cons 'options (vconcat (mapcar (lambda (sym)
                                            (let ((form (maf-site--default-form sym)))
                                              (list (cons 'name (symbol-name sym))
                                                    (cons 'default (truncate-string-to-width (prin1-to-string form) 90 nil nil "…"))
                                                    (cons 'doc (or (ignore-errors (car (split-string (documentation-property sym 'variable-documentation) "\n"))) "")))))
                                          (ignore-errors (maf-module--options name))))))))

(let* ((root (locate-dominating-file (or load-file-name default-directory) "maf.el"))
       (items (maf-module--items))
       (present (delete-dups (mapcar (lambda (it) (plist-get (cdr it) :group)) items)))
       (groups (append (seq-filter (lambda (g) (member g present)) maf-module--group-order)
                       (seq-remove (lambda (g) (member g maf-module--group-order)) present)))
       (records
        (mapcar (lambda (g)
                  (list (cons 'title g)
                        (cons 'modules
                              (vconcat (mapcar #'maf-site--module-record
                                               (seq-filter (lambda (it) (equal (plist-get (cdr it) :group) g))
                                                           items))))))
                groups))
       (out (list (cons 'generated (format-time-string "%Y-%m-%d"))
                  (cons 'groups (vconcat records)))))
  (with-temp-file (expand-file-name "public/data/modules.json" root)
    (insert (json-encode out)))
  (with-temp-file (expand-file-name "public/data/modules.js" root)
    (insert "window.MAF_MODULES = " (json-encode out) ";\n"))
  (mapcar (lambda (g) (cons (alist-get 'title g) (length (alist-get 'modules g)))) records))
