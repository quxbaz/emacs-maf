;; -*- lexical-binding: t; -*-
;;
;; Batch-runnable verification of the equation target (per-side iteration).
;; Unlike step-tests/, this needs no interactive frame — it drives calc
;; directly and asserts on results. Run with:
;;
;;   emacs --batch -Q -l ai-tests/equation-tests.el
;;
;; Exits non-zero if any assertion fails.

(add-to-list 'load-path
             (expand-file-name "../src" (file-name-directory
                                         (or load-file-name buffer-file-name))))
(require 'calc)
(require 'maf-lib)
(require 'maf-sel)
(require 'maf-resolve)
(require 'maf-commit)
(require 'maf-defcmd)

(maf-defcmd maf-square (expr arg commit)
  "Square command." :arity unary :prefix "sqr"
  (commit (calcFunc-mul expr expr)))

(maf-defcmd maf-mult (expr arg commit)
  "Multiplication command." :arity binary :prefix "mult"
  (commit (calcFunc-mul expr arg)))

(defvar maf--test-failures 0)

(defun maf--expect (label got want)
  (if (equal got want)
      (princ (format "PASS %s\n" label))
    (setq maf--test-failures (1+ maf--test-failures))
    (princ (format "FAIL %s: got %S, want %S\n" label got want))))

(defun maf--fmt (m) (math-format-value (calc-top m 'full)))

(calc-create-buffer)
(with-current-buffer "*Calculator*"
  (calc-mode)

  ;; Unary: body runs once per side, relation reassembled. x = 5 -> x^2 = 25.
  (calc-reset 0)
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (calc-refresh)
  (goto-char (point-min))
  (call-interactively 'maf-square)
  (calc-refresh)
  (maf--expect "unary square on equation" (maf--fmt 1) "x^2 = 25")
  (maf--expect "unary leaves one entry" (calc-stack-size) 1)

  ;; Binary: relation at level 2, arg 2 at top, consumed once. x = 5 -> 2 x = 10.
  (calc-reset 0)
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (calc-push 2)
  (calc-refresh)
  (calc-cursor-stack-index 2)
  (beginning-of-line)
  (call-interactively 'maf-mult)
  (calc-refresh)
  (maf--expect "binary mult on equation" (maf--fmt 1) "2 x = 10")
  (maf--expect "binary consumes arg once" (calc-stack-size) 1)

  ;; Keep-args unary: result pushed on top, original relation preserved below.
  (calc-reset 0)
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (calc-refresh)
  (goto-char (point-min))
  (let ((calc-keep-args-flag t))
    (call-interactively 'maf-square))
  (calc-refresh)
  (maf--expect "keep-args result on top" (maf--fmt 1) "x^2 = 25")
  (maf--expect "keep-args preserves original" (maf--fmt 2) "x = 5")
  (maf--expect "keep-args leaves two entries" (calc-stack-size) 2)

  ;; Binary on a relation that IS the top (m=1): arg would be the relation
  ;; itself, so resolve rejects it.
  (calc-reset 0)
  (calc-push '(calcFunc-eq (var x var-x) 5))
  (calc-refresh)
  (goto-char (point-min))
  (maf--expect "binary at top relation errors"
               (condition-case nil
                   (progn (call-interactively 'maf-mult) nil)
                 (error t))
               t))

(if (zerop maf--test-failures)
    (princ "\nAll equation tests passed.\n")
  (princ (format "\n%d failure(s).\n" maf--test-failures))
  (kill-emacs 1))
