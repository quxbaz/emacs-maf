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

(add-to-list 'load-path (expand-file-name "src" (file-name-directory (or load-file-name buffer-file-name))))

(require 'maf-lib)
(require 'maf-sel)
(require 'maf-debug)
(require 'maf-resolve)
(require 'maf-commit)
(require 'maf-defcmd)

(defgroup maf nil
  "Math-Algebra-Formulas: an alternative UX for Emacs Calc."
  :group 'calc
  :prefix "maf-")

(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

;;;###autoload
(define-minor-mode maf-mode
  "Toggle MAF mode.
When enabled, provides contextual commands for manipulating Calc
expressions on the stack and home line."
  :lighter " maf"
  :keymap maf-mode-map
  :group 'maf)

(provide 'maf)

;;; maf.el ends here
