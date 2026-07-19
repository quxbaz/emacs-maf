;; -*- lexical-binding: t; -*-
;;
;; bindings.el
;;
;; Default maf-mode-map key bindings. The mafcmd table in maf-cmds.el
;; binds its own keys from row data; this file collects every binding
;; made outside the table.

(require 'maf-stack "stack")
(require 'maf-minibuffer "minibuffer")
(require 'maf-edit "edit")

;; Also defvar'd in maf.el and maf-cmds.el; whichever file loads first
;; creates the map, the rest are no-ops.
(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

(define-key maf-mode-map (kbd "l f") #'mafcmd-factor-by)
(define-key maf-mode-map (kbd "l F") #'mafcmd-factor-gcd)
(define-key maf-mode-map (kbd "l l") #'mafcmd-float)
(define-key maf-mode-map (kbd "l c") #'mafcmd-frac)
(define-key maf-mode-map (kbd "O") #'mafcmd-commute)
;; A toggle between pair members is its own inverse, so both directions
;; run the same command.
(define-key maf-mode-map (kbd "S-<up>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd "S-<down>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd ",") #'maf-quick-variable)
;; RET toggles in-place stack editing: enter maf-edit, and inside it
;; RET (maf-edit-mode-map) commits — one key edits and commits. S-RET
;; enters with a fresh entry started at the bottom, returning point
;; when the session ends; inside maf-edit the same key is the newline
;; gesture. Shadows one of calc-enter's two keys; SPC still runs it.
(define-key maf-mode-map (kbd "RET") #'maf-edit)
(define-key maf-mode-map (kbd "S-<return>") #'maf-edit-add-entry)
(define-key maf-mode-map (kbd "U") #'maf-undo)
(define-key maf-mode-map (kbd "D") #'maf-redo)
;; Shadows calc's TAB with the contextual line swap.
(define-key maf-mode-map (kbd "TAB") #'maf-swap-up)
;; Equate gets both = (shadowing calc-evaluate) and e (shadowing the
;; e-notation digit start; inside digit entry e still means exponent,
;; since the entry minibuffer is calc's own).
(define-key maf-mode-map (kbd "=") #'maf-equal-to)
(define-key maf-mode-map (kbd "e") #'maf-equal-to)

;; The digit-entry starters, mirroring calc-mode-map's calcDigit-start set.
(mapc (lambda (x)
        (define-key maf-mode-map (char-to-string x) #'maf-digit-start))
      "_0123456789.#@")

(provide 'maf-bindings)
