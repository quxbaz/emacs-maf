;; -*- lexical-binding: t; -*-

(cl-defstruct sketch/calc--target
  kind

  m

  expr

  parent-formula

  rel-op

  lhs rhs)

(defun sketch/calc--resolve-target (opt-m opt-line equation-map?)
  "Inspect point and calc state; return a `sketch/calc--target'.

OPT-M is the stack level to use when point is at home (past the stack).
OPT-LINE, when non-nil, forces whole-line targeting even if point is
inside formula text (mirrors the (line? t) option).
EQUATION-MAP?, when non-nil, lets the resolver classify the target as
an equation/inequality (= != < <= > >=) so the caller can map BODY
over both sides. When nil, equations are returned as plain entries."
  (cond

   ((sketch/calc-active-selection-p)
    (let* ((m (sketch/calc-active-entry-m-dwim))
           (entry (nth m calc-stack)))
      (make-sketch/calc--target
       :kind 'selection
       :m m
       :expr (nth 2 entry)

       :parent-formula (car entry))))

   ((sketch/calc-point-is-at-home-p)
    (make-sketch/calc--target
     :kind 'home
     :m opt-m
     :expr (car (calc-top opt-m 'entry))))

   (t
    (let* ((m (calc-locate-cursor-element (point)))
           (full (car (nth m calc-stack)))

           (line? (or opt-line calc-option-flag))

           (sub (and (not line?)
                     (not (eolp))
                     (not (sketch/calc-point-is-in-line-prefix-p))
                     (sketch/calc-subformula-at-point)))

           (rel (and equation-map? (null sub) (sketch/calc-rel-op-p full))))
      (cond
       (sub (make-sketch/calc--target
             :kind 'subexpr :m m
             :expr sub
             :parent-formula full))
       (rel (make-sketch/calc--target
             :kind 'equation :m m
             :expr full

             :rel-op rel
             :lhs (nth 1 full)
             :rhs (nth 2 full)))
       (t   (make-sketch/calc--target
             :kind 'entry :m m
             :expr full)))))))

(defun sketch/calc--write-back (kind m parent old new prefix keep-args)
  "__COMMITOLD__ with NEW in the calc stack and log PREFIX in the trail.
KIND, M, PARENT come from the resolver; KEEP-ARGS preserves the
`calc-keep-args' behavior of the original macro (when set, pushes the
new value on top instead of replacing in place)."
  (pcase kind

    ('selection
     (calc-pop-push-record-list
      1 prefix (calc-replace-sub-formula parent old new) m new))

    ('subexpr
     (calc-pop-push-record-list
      1 prefix (calc-replace-sub-formula parent old new) m))

    ('entry
     (calc-pop-push-record-list 1 prefix new m))

    ('home
     (calc-pop-push-record-list 1 prefix new (if keep-args 1 m)))))

(cl-defstruct sketch/calc--cursor-state
  point line col-pos keep-args)

(defun sketch/calc--capture-cursor-state ()
  "Snapshot pre-operation cursor + relevant flags."
  (make-sketch/calc--cursor-state
   :point     (point)
   :line      (line-number-at-pos)
   :col-pos   (cond ((eolp) 'eol)
                    ((sketch/calc-point-is-in-line-prefix-p) 'bol))
   :keep-args calc-keep-args-flag))

(defun sketch/calc--restore-cursor (cs kind)
  "Restore point per cursor-state CS and the resolved target KIND."
  (pcase-let (((cl-struct sketch/calc--cursor-state point line col-pos keep-args)
               cs))
    (cond
     ((eq kind 'selection)
      (goto-char point))
     ((or (eq kind 'home) keep-args)
      (calc-align-stack-window))
     (t
      (goto-char point)
      (when (/= (line-number-at-pos) line)
        (goto-char (point-min))
        (forward-line (1- line)))
      (pcase col-pos
        ('eol (end-of-line))
        ('bol (beginning-of-line)))))))

(cl-defun sketch/calc-push (tgt arg-val body-fn &key
                                            (prefix "")
                                            (wrap t)
                                            (simp nil))
  "Run BODY-FN against TGT with ARG-VAL.
See section comment for the signature and semantics. This function
mutates the calc stack and does NOT save or restore the cursor; the
caller is responsible for that (`sketch/defcmd' handles it automatically)."
  (let* ((keep-args calc-keep-args-flag)
         (kind (sketch/calc--target-kind tgt)))
    (cl-flet ((run-body (expr replacer)

                (if (eq simp -1)
                    (sketch/calc-without-simplification
                     (funcall body-fn expr replacer arg-val))
                  (funcall body-fn expr replacer arg-val)))
              (binary-pop ()

                (when arg-val (calc-pop-stack 1))))
      (pcase kind

        ('equation
         (let ((lhs (sketch/calc--target-lhs tgt))
               (rhs (sketch/calc--target-rhs tgt))
               (op  (sketch/calc--target-rel-op tgt))
               (tm  (sketch/calc--target-m tgt)))
           (calc-wrapper
            (run-body lhs (lambda (e) (setq lhs e)))
            (run-body rhs (lambda (e) (setq rhs e)))
            (calc-pop-push-record-list 1 prefix (list op lhs rhs) tm)
            (binary-pop))))

        (_
         (let* ((expr   (sketch/calc--target-expr tgt))
                (tm     (sketch/calc--target-m tgt))
                (parent (sketch/calc--target-parent-formula tgt))
                (replacer (lambda (new)
                            (sketch/calc--write-back kind tm parent expr new
                                                 prefix keep-args))))
           (if wrap
               (calc-wrapper
                (run-body expr replacer)
                (binary-pop))
             (run-body expr replacer)
             (binary-pop))))))))

(defconst sketch/defcmd--known-bindings '(expr commit arg)
  "BINDING names accepted by `sketch/defcmd'.
Each name may be requested by a caller and will be made visible inside
BODY (as a lexical variable, or as a `cl-flet'-bound function in the
case of `commit'). Presence of `arg' promotes the command to BINARY
arity (see the section comment above).")

(defun sketch/defcmd--validate-bindings (bindings name)
  "Signal an error if BINDINGS contains any name not allowed.
The allowed set is `sketch/defcmd--known-bindings'. NAME is the function
being defined; used in the error message."
  (let ((unknown (cl-set-difference bindings sketch/defcmd--known-bindings)))
    (when unknown
      (error "Unknown binding(s) in sketch/defcmd %s: %s" name unknown))))

(cl-defstruct sketch/defcmd--opts
  (prefix "")
  (wrap   t)
  (simp   nil)
  (map?   t)
  (line?  nil))

(defun sketch/defcmd--collect-opts (rest name)
  "Consume leading :key val pairs from REST; return (opts . body).
Signals an error immediately on an unrecognized keyword."
  (let ((opts (make-sketch/defcmd--opts)))
    (while (keywordp (car rest))
      (let ((k (pop rest))
            (v (pop rest)))
        (pcase k
          (:prefix (setf (sketch/defcmd--opts-prefix opts) v))
          (:wrap   (setf (sketch/defcmd--opts-wrap   opts) v))
          (:simp   (setf (sketch/defcmd--opts-simp   opts) v))
          (:map?   (setf (sketch/defcmd--opts-map?   opts) v))
          (:line?  (setf (sketch/defcmd--opts-line?  opts) v))
          (_       (error "Unknown option in sketch/defcmd %s: %s" name k)))))
    (cons opts rest)))

(defun sketch/defcmd--parse-rest (rest name)
  "Parse the after-BINDINGS tail of a `sketch/defcmd' source form.
Returns (DOCSTRING OPTS BODY) where OPTS is a `sketch/defcmd--opts' struct."
  (let ((docstring (and (stringp (car rest)) (cdr rest) (pop rest))))
    (pcase-let ((`(,opts . ,body) (sketch/defcmd--collect-opts rest name)))
      (list docstring opts body))))

(defmacro sketch/defcmd (name bindings &rest rest)
  "Define a no-arg interactive calc command NAME wrapping `sketch/calc-push'.
See the section comment above this defmacro for syntax and keywords."
  (declare (indent 2) (doc-string 3))
  (sketch/defcmd--validate-bindings bindings name)
  (seq-let (docstring opts body) (sketch/defcmd--parse-rest rest name)
    (let* (

           (binary? (memq 'arg bindings))

           (sym-expr (if (memq 'expr bindings) 'expr (gensym "_unused-expr-")))
           (sym-arg  (if (memq 'arg  bindings) 'arg  (gensym "_unused-arg-")))

           (raw-commit-fn (gensym "_commit-fn-"))
           (lambda-body
            (if (memq 'commit bindings)
                `((cl-flet ((commit (e) (funcall ,raw-commit-fn e)))
                    ,@body))
              body)))
      `(defun ,name ()
         ,@(when docstring (list docstring))
         (interactive)
         (let* (

                (tgt (sketch/calc--resolve-target
                      ,(if binary? 2 1)
                      ,(sketch/defcmd--opts-line? opts)
                      ,(not (eq (sketch/defcmd--opts-map? opts) -1))))
                (cs (sketch/calc--capture-cursor-state))

                (arg-val ,(when binary?
                            '(sketch/calc-without-simplification (calc-top-n 1)))))
           (sketch/calc-push
            tgt arg-val
            (lambda (,sym-expr ,raw-commit-fn ,sym-arg)
              ,@lambda-body)
            :prefix ,(sketch/defcmd--opts-prefix opts)
            :wrap   ,(sketch/defcmd--opts-wrap   opts)
            :simp   ,(sketch/defcmd--opts-simp   opts))
           (sketch/calc--restore-cursor cs (sketch/calc--target-kind tgt)))))))
