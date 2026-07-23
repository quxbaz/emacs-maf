;; -*- lexical-binding: t; -*-
;;
;; project-init.el
;;
;; Session setup for the maf project: open the working set of files in
;; background buffers, load the package, and arrange the starting
;; layout — maf.org on the left, calc on the right.

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
  ;; Opt into the stack-persistence module — off in the package default
  ;; because it writes files, but wanted here: the dev instance's server
  ;; name keys its own save file, so it never collides with other
  ;; sessions. Expressed through `maf-modules' so the module list stays
  ;; the single source of truth; `maf-modules-apply' enables it.
  (add-to-list 'maf-modules 'maf-persist t)
  (maf-modules-apply)
  ;; Create the calc buffer without letting it pick the layout.
  (save-window-excursion (maf-calc-direct))
  ;; Starting layout: maf.org on the left, calc on the right. Deferred
  ;; on a timer so late startup display logic cannot clobber it; loaded
  ;; interactively, the timer fires right away.
  (run-at-time 0 nil
               (lambda ()
                 (delete-other-windows)
                 (find-file (expand-file-name "docs/maf.org" root))
                 (set-window-buffer (split-window-right) "*Calculator*"))))
