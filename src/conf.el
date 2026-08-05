;; -*- lexical-binding: t; -*-
;;
;; conf.el
;;
;; maf's customize group and the user options belonging to the core:
;; the contextual commands, and the module list itself. Feature code
;; requires this and reads the options; nothing here has any effect on
;; its own.
;;
;; A module's own options do NOT live here — they sit beside the code
;; they configure, in the module file under modules/, so a module stays
;; self-contained and usable on its own. Nothing is lost by the split:
;; maf.el loads every module file unconditionally (loading only
;; registers the module's toggle; `maf-modules' decides what is
;; *enabled*), so the customize group is always complete. A module file
;; requires this one for the group.

(defgroup maf nil
  "Math-Algebra-Formulas: an alternative UX for Emacs Calc."
  :group 'calc
  :prefix "maf-")

;;; Contextual commands (stack.el)

(defcustom maf-toggle-op-pairs
  '((+ . -)
    (* . /)
    (calcFunc-ln . calcFunc-exp)
    (calcFunc-log . ^)
    (calcFunc-lt . calcFunc-gt)
    (calcFunc-leq . calcFunc-geq)
    (calcFunc-eq . calcFunc-neq)
    ;; Trig pairs with its inverse, like ln/exp. Upstream has no
    ;; arcsec/arccsc/arccot, so sec/csc/cot stay unpaired.
    (calcFunc-sin . calcFunc-arcsin)
    (calcFunc-cos . calcFunc-arccos)
    (calcFunc-tan . calcFunc-arctan)
    (calcFunc-sinh . calcFunc-arcsinh)
    (calcFunc-cosh . calcFunc-arccosh)
    (calcFunc-tanh . calcFunc-arctanh))
  "Operator pairs toggled by `mafcmd-toggle-op'.
Each pair toggles in both directions. Operands stay in place; only the
operator changes, so log(a, b) toggles to a^b and back, and a < b flips
to a > b without touching either side. Operators are calc's internal
symbols: +, -, *, /, ^, neg, or a calcFunc- name."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'maf)

(defcustom maf-coordinate-name-sets
  '(((var x var-x) (var y var-y) (var z var-z) (var w var-w))
    ((var h var-h) (var k var-k) (var l var-l) (var m var-m))
    ((var p var-p) (var q var-q) (var r var-r) (var s var-s)))
  "Coordinate name sets cycled by `mafcmd-coordinate-toggle'.
Each element is an ordered list of calc variable nodes, one per
dimension: the first names a vector's first component, the second its
second, and so on. An unnamed vector takes the first set; a vector
already named by one set advances to the next, wrapping around at the
end. A vector with more components than the target set has names is
refused rather than truncated, so adding a dimension means adding a
name to every set."
  :type '(repeat (repeat sexp))
  :group 'maf)

;;; Variable browsing (stack.el)

(defcustom maf-browse-variables-exclude
  '("\\`eq-" "Rules\\'" "\\`\\(Decls\\|Holidays\\|Modes\\)\\'")
  "Regexps for the calc variables `maf-browse-variables' leaves out.
A variable whose name matches any of these is not offered. Names are
matched without their `var-' prefix. Set this to nil to be offered
every variable that holds a value.

What the three defaults name is not a value anyone recalls onto a
stack. They leave a list of things worth pushing: the constants, and
whatever you have stored yourself.

  eq-*     the formula library. Dozens of entries against a handful of
           everything else, and modules/maf-formulas.el already has a
           browser built for picking one of them out — listing them
           here would be the same choice offered twice, once badly.

  *Rules   calc's rewrite-rule sets. A rule set is read by calc where
           it sits: \\`a r' and the selection commands take it from
           the variable, so a copy on the stack is not what wanting
           one means.

  Decls, Holidays, Modes
           calc's settings, kept in variables because that is how they
           are edited (\\`s D', \\`s H'). Recalling one is reading a
           setting, not doing arithmetic — and calc already has \\`m g'
           for the one case where the settings do belong on the stack.

This only decides what the prompt offers. Calc's own \\`s r' reaches
any variable by name, whatever is excluded here."
  :type '(repeat regexp)
  :group 'maf)

;;; Modules (maf-module.el)

(defcustom maf-modules '(maf-timeline maf-hl maf-edit maf-editplus
                         maf-editvars maf-recall maf-preview maf-formulas
                         maf-selplus maf-poly-order)
  "Names of the maf feature modules to enable.
Each major feature that stands apart from the contextual-command core
is an optional module (see maf-module.el); this list names the ones
that should be active. Setting it through Customize applies the change
at once — enabling newly-listed modules and disabling removed ones.
Set from Lisp, call `maf-modules-apply' to take effect.

Customize offers a checkbox per registered module, built from
`maf-module-registry' as each module file loads (see
`maf-register-module'); the plain list of symbols is the fallback for
before that happens, or for when maf-module.el is never loaded."
  :type '(repeat symbol)
  :set (lambda (sym val)
         (set-default sym val)
         (when (fboundp 'maf-modules-apply) (maf-modules-apply)))
  :group 'maf)

(provide 'maf-conf)
