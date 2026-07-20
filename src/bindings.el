;; -*- lexical-binding: t; -*-
;;
;; bindings.el
;;
;; Default maf-mode-map key bindings. The mafcmd table in maf-cmds.el
;; binds its own keys from row data; this file collects every binding
;; made outside the table.

(require 'maf-stack "stack")
(require 'maf-history "history")
(require 'maf-minibuffer "minibuffer")
(require 'maf-edit "edit")

;; Also defvar'd in maf.el and maf-cmds.el; whichever file loads first
;; creates the map, the rest are no-ops.
(defvar maf-mode-map (make-sparse-keymap)
  "Keymap for `maf-mode'.")

;; Shadows calc-stirling's key; the contextual stirling pair
;; (mafcmd-stir1/stir2) cedes it — see the table in maf-cmds.el.
(define-key maf-mode-map (kbd "k s") #'mafcmd-complete-square)
;; Shadows calc-double-factorial's key; mafcmd-dfact cedes it — see
;; the table in maf-cmds.el.
(define-key maf-mode-map (kbd "k d") #'mafcmd-factor-powers)
(define-key maf-mode-map (kbd "l f") #'mafcmd-factor-by)
(define-key maf-mode-map (kbd "l F") #'mafcmd-factor-gcd)
(define-key maf-mode-map (kbd "l l") #'mafcmd-float)
(define-key maf-mode-map (kbd "l c") #'mafcmd-frac)
(define-key maf-mode-map (kbd "l d") #'mafcmd-to-degrees)
(define-key maf-mode-map (kbd "l r") #'mafcmd-to-radians)
;; M-o is unbound in calc itself; H M-o runs the mod-180 variant.
(define-key maf-mode-map (kbd "M-o") #'mafcmd-mod-360)
(define-key maf-mode-map (kbd "O") #'mafcmd-commute)
;; Shadows calc-call-last-kbd-macro.
(define-key maf-mode-map (kbd "X") #'mafcmd-log-exp)
;; A toggle between pair members is its own inverse, so both directions
;; run the same command.
(define-key maf-mode-map (kbd "S-<up>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd "S-<down>") #'mafcmd-toggle-op)
(define-key maf-mode-map (kbd ",") #'maf-quick-variable)
;; SPC toggles in-place stack editing: enter maf-edit, and inside it
;; RET (maf-edit-mode-map) commits. C-RET enters with a fresh entry
;; started at the bottom, returning point when the session ends.
;; Shadows one of calc-enter's two keys; RET still runs it. Inside
;; maf-edit SPC is self-inserting, since the edit text map replaces
;; this one.
(define-key maf-mode-map (kbd "SPC") #'maf-edit)
(define-key maf-mode-map (kbd "C-<return>") #'maf-edit-add-entry)
;; S-RET opens the new entry below the entry at point instead.
(define-key maf-mode-map (kbd "S-<return>") #'maf-edit-add-entry-below)
(define-key maf-mode-map (kbd "U") #'maf-undo)
(define-key maf-mode-map (kbd "D") #'maf-redo)
;; Catch every key that dispatches to undo/redo, so point handling
;; never depends on which undo key was pressed. Remapping is a single
;; step: calc-mode-map already remaps undo to calc-undo, and a key
;; resolved through that chain is never re-remapped — so the plain
;; Emacs commands must be remapped here too, and the minor-mode map
;; wins over calc's.
(define-key maf-mode-map [remap undo] #'maf-undo)
(define-key maf-mode-map [remap undo-redo] #'maf-redo)
(define-key maf-mode-map [remap calc-undo] #'maf-undo)
(define-key maf-mode-map [remap calc-redo] #'maf-redo)
;; Contextual delete; C-d is unbound in calc itself, and backspace
;; shadows calc-pop, whose behavior maf-del keeps at home.
(define-key maf-mode-map (kbd "C-d") #'maf-del)
(define-key maf-mode-map (kbd "DEL") #'maf-del)
;; Line-based kill: the whole entry at point, onto the kill ring.
;; Shadows calc-kill, keeping its whole-entry semantics.
(define-key maf-mode-map (kbd "C-k") #'maf-kill)
;; Shadows calc's TAB with the contextual line swap.
(define-key maf-mode-map (kbd "TAB") #'maf-swap-up)
;; Equate gets both = (shadowing calc-evaluate) and e (shadowing the
;; e-notation digit start; inside digit entry e still means exponent,
;; since the entry minibuffer is calc's own).
(define-key maf-mode-map (kbd "=") #'maf-equal-to)
(define-key maf-mode-map (kbd "e") #'maf-equal-to)

;; The simplification toggle takes @ from the digit-entry starters
;; below; inside digit entry @ still means degrees, since the entry
;; minibuffer is calc's own (cf. e and maf-equal-to).
(define-key maf-mode-map (kbd "@") #'maf-toggle-simplify)

;; The digit-entry starters, mirroring calc-mode-map's calcDigit-start
;; set minus @, which maf-toggle-simplify shadows.
(mapc (lambda (x)
        (define-key maf-mode-map (char-to-string x) #'maf-digit-start))
      "_0123456789.#")

;; Entry-beginning motion. Shadows calc's own M-m prefix, whose two
;; sequences (M-m t, M-m M-t) stay reachable as m t and m M-t.
(define-key maf-mode-map (kbd "M-m") #'maf-beginning-of-entry)

;; The stack history buffer replaces the trail; its window opens on
;; the trail-display key. Only t d is shadowed — the rest of calc's t
;; prefix (trail motion, time commands) still falls through.
(define-key maf-mode-map (kbd "t d") #'maf-history)

(provide 'maf-bindings)
