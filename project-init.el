;; -*- lexical-binding: t; -*-
;;
;; project-init.el
;;
;; Session setup for the maf project: open the working set of files in
;; background buffers and load the package.

(let ((root (file-name-directory (or load-file-name buffer-file-name))))
  ;; Open docs and sources without selecting them.
  (dolist (file (append
                 (directory-files (expand-file-name "docs" root) t "\\.org\\'")
                 (directory-files-recursively (expand-file-name "core" root) "")
                 (directory-files-recursively (expand-file-name "src" root) "")))
    (find-file-noselect file))
  ;; Load the package entry point.
  (load (expand-file-name "maf.el" root))
  ;; Enable maf-mode in calc buffers. This lives here, not in the package:
  ;; enabling is the user's choice. Hooking calc-mode (rather than enabling
  ;; once) also keeps maf-mode on across calc-reset, which re-runs calc-mode
  ;; and thereby kills buffer-local minor modes.
  (add-hook 'calc-mode-hook #'maf-mode)
  ;; Show calc in the other window, keeping the current window selected.
  (save-window-excursion (maf-calc-direct))
  (save-selected-window
    (switch-to-buffer-other-window "*Calculator*")))
