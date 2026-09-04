;;; export-modules.el --- Write public/data/modules.json from a live maf  -*- lexical-binding: t; -*-

;; Run inside an Emacs with maf loaded, from the repository root:
;;   emacsclient -s '#emacs' --eval '(load-file "public/gen/export-modules.el")'
;; The groups and their order are the module menu's own (m c), read from
;; the registry; each module carries its summary, entry keys, shipped
;; default, and the details text the menu shows.

(require 'json)
(require 'seq)

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
          (cons 'details (substring-no-properties (or (ignore-errors (maf-module--details name)) ""))))))

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
