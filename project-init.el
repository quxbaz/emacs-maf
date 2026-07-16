;; -*- lexical-binding: t; -*-
;;
;; project-init.el
;;
;; Session setup for the maf project: open the working set of files in
;; background buffers and load the package.

(defconst maf-seed-entries
  '("3:4"                    ; fraction
    "2.5"                    ; float
    "x"                      ; variable
    "(a + b) (2 c - d)"      ; nested expressions
    "2 x - 3 < 7"            ; inequality
    "f(x) = x^2 + 1"         ; function
    "sin(2 x + 1)"           ; trig
    "[a, b, c]"              ; vector
    "[1 .. 3]"               ; interval
    "6 x + 12"               ; expression
    "6 x + 12 = 18 y + 6"    ; equation
    )
  "Algebraic entries pushed onto a fresh calc stack for casual testing.
One entry per common expression shape.")

(defun maf-seed-calc ()
  "Push `maf-seed-entries' onto the calc stack."
  (interactive)
  ;; calc-wrapper's epilogue renumbers and refreshes the stack display;
  ;; raw pushes would leave every entry rendered as level 1.
  (calc-wrapper
   (mapc #'maf-push maf-seed-entries)))

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
    (switch-to-buffer-other-window "*Calculator*"))
  ;; Seed the stack so casual testing doesn't start from scratch.
  (maf-seed-calc))
