;;; maf.el --- Math-Algebra-Formulas: Calc UX overhaul  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Yeung
;;
;; Author: David Yeung <quxbaz@gmail.com>
;; Version: 0.0.1
;; Package-Requires: ((emacs "28.1"))
;; Keywords: calc, math, tools
;; URL: https://github.com/quxbaz/emacs-maf

;; This file is not part of GNU Emacs.

;;; Commentary:

;; maf provides an alternative UX over Emacs Calc, with contextual commands
;; for manipulating expressions on the stack and on the home line.
;;
;; This package is under active development; the public API is unstable.

;;; Code:

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "src" dir))
  (add-to-list 'load-path (expand-file-name "core" dir))
  (add-to-list 'load-path (expand-file-name "debug" dir)))

(require 'maf-conf "conf")
(require 'maf-comp)
(require 'maf-chain)
(require 'maf-lib)
(require 'maf-sel)
(require 'maf-hl)
(require 'maf-step)
(require 'maf-hl-verify)
(require 'maf-resolve)
(require 'maf-commit)
(require 'maf-defcmd)
(require 'maf-cmds)
(require 'maf-math "math")
(require 'maf-stack "stack")
(require 'maf-persist "persist")
(require 'maf-bindings "bindings")
(require 'maf-minibuffer "minibuffer")

;;;###autoload
(defun maf-calc ()
  "Start calc with dwim window behavior.
From a special buffer or single-window frame, opens calc full-screen.
From a single window, splits right first.
Otherwise delegates to calc interactively."
  (interactive)
  (cond ((or (string-match-p "^[*]" (buffer-name))
             (memq major-mode '(dired-mode magit-status-mode)))
         (calc nil t t))
        ((= (count-windows) 1)
         (split-window-right)
         (other-window 1)
         (calc nil t t))
        (t
         (call-interactively #'calc))))

;;;###autoload
(defun maf-calc-direct ()
  "Open calc directly without window management."
  (interactive)
  (calc nil t t))

(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

;;;###autoload
(define-minor-mode maf-mode
  "Toggle MAF mode.
When enabled, provides contextual commands for manipulating Calc
expressions on the stack and home line. Sub-formula highlighting is
part of the UX and toggles with the mode; `maf-hl-mode' also works
standalone for the highlight alone."
  :lighter " maf"
  :keymap maf-mode-map
  :group 'maf
  (maf-hl-mode (if maf-mode 1 -1)))

(provide 'maf)

;;; maf.el ends here
