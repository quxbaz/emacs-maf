;; -*- lexical-binding: t; -*-
;;
;; Refactor sketch for `my/calc-push' (see lib.el).
;;
;; ============================================================================
;; WHY THIS REFACTOR
;; ============================================================================
;;
;; The current macro in lib.el is ~230 lines and tangles three concerns:
;;
;;   (1) "What am I operating on?"   -- selection? sub-formula? whole entry?
;;                                      equation sides? stack item at home?
;;   (2) "What does BODY do to it?"  -- the user's actual operation
;;   (3) "Where does point end up?"  -- preservation / realignment rules
;;
;; Five branches of (1) each contain their own (cl-flet ((commit ...))
;; ,@body) block with nearly identical shapes, and the equation-mapping
;; block (Branch 5) is duplicated between the (line? t) and default code
;; paths. The compile-time `cond' on opt-line / opt-map produces four
;; near-duplicate expansions.
;;
;; This sketch separates the three concerns:
;;
;;   1. A `my/calc--target' struct describing what BODY operates on.
;;   2. A pure resolver function `my/calc--resolve-target' that decides
;;      what kind of target point is on.
;;   3. A `my/calc--write-back' helper that handles the four non-equation
;;      replacement shapes (selection, subexpr, entry, home).
;;   4. A `my/calc--cursor-state' struct plus `--capture-cursor-state'
;;      and `--restore-cursor' functions that own the point / window
;;      restoration epilogue.
;;   5. A `my/calc-push' dispatch FUNCTION (not a macro) that ties the
;;      above together and runs the user's BODY against the target.
;;   6. A `my/defcmd' MACRO that is the only call site of my/calc-push;
;;      it wraps BODY in a lambda and emits a no-arg interactive defun.
;;
;; Keeping (5) a function means dispatch is testable in isolation and
;; there is exactly one macro layer (in `my/defcmd') dealing with call-
;; site ergonomics. Users never see `my/calc-push'.
;;
;; ============================================================================
;; TRADEOFFS
;; ============================================================================
;;
;;   - opt-map and opt-line move from compile-time dispatch (where they
;;     pick which of four cond branches to emit) to runtime arguments of
;;     the resolver. In practice every call site passes a literal, so the
;;     dead-branch cost is one extra `cond' per invocation -- negligible
;;     for interactive calc commands.
;;
;;   - BODY must still splice into two locations: once for the normal
;;     case (`wrapped-body', which carries `calc-wrapper' and `pop-forms')
;;     and once for the equation case (`body-for-map', which runs twice,
;;     once per side, with `calc-wrapper' and `pop-forms' lifted out).
;;     That duplication is structural -- there is no way to share it
;;     without changing the user-facing contract.


;;; ===========================================================================
;;; Target struct
;;; ===========================================================================
;;
;; The resolver returns one of these. It carries everything BODY (and the
;; commit closure) need to know about the target -- nothing more.
;; Fields are nil when irrelevant to the kind:
;;
;;   kind=selection : m, expr, parent-formula
;;   kind=subexpr   : m, expr, parent-formula
;;   kind=entry     : m, expr
;;   kind=home      : m, expr
;;   kind=equation  : m, expr (= full formula), rel-op, lhs, rhs

(cl-defstruct my/calc--target
  kind             ; 'selection | 'subexpr | 'entry | 'home | 'equation
  m                ; stack level (1=top, 2=second, ...)
  expr             ; what BODY's `expr' binding will see
  parent-formula   ; full formula at stack[m]; needed by `calc-replace-sub-formula'
                   ; for selection/subexpr; nil for entry/home/equation.
  rel-op           ; relational operator symbol (calcFunc-eq etc.); equation only
  lhs rhs)         ; the two sides of the relation; equation only


;;; ===========================================================================
;;; Resolver
;;; ===========================================================================
;;
;; Pure function -- no side effects beyond `calc-prepare-selection' inside
;; `my/calc-subformula-at-point' (which rebuilds the selection cache; calc
;; does this routinely). Inspects point + calc state and returns a target
;; struct. Collapses what the current macro spreads across Branches 1-5.
;;
;; Dispatch order (matches the current macro's priority):
;;
;;   1. Active selection wins, regardless of point position. Uses
;;      `my/calc-active-entry-m-dwim' which prefers the selection on the
;;      same line as point, falling back to the topmost active selection.
;;
;;   2. Point past the stack ("home") -- operate on stack level OPT-M.
;;      This is the keyboard-friendly path: the user is below the . line,
;;      so we treat it like a normal calc command targeting the top.
;;
;;   3. Point on a stack entry -- the interesting case. We then choose
;;      between subexpr, equation, and whole-entry based on:
;;        - OPT-LINE / `calc-option-flag': force whole-line targeting.
;;        - position on the line: EOL or in the "1: " prefix area means
;;          "no sub-formula", since sub-formula detection requires being
;;          inside the rendered formula text.
;;        - EQUATION-MAP?: only consider equation mapping if the caller
;;          opted in (the opt-map != -1 case in the old macro).

(defun my/calc--resolve-target (opt-m opt-line equation-map?)
  "Inspect point and calc state; return a `my/calc--target'.

OPT-M is the stack level to use when point is at home (past the stack).
OPT-LINE, when non-nil, forces whole-line targeting even if point is
inside formula text (mirrors the (line? t) option).
EQUATION-MAP?, when non-nil, lets the resolver classify the target as
an equation/inequality (= != < <= > >=) so the caller can map BODY
over both sides. When nil, equations are returned as plain entries."
  (cond

   ;; ------------------------------------------------------------------------
   ;; (1) Active selection wins.
   ;; ------------------------------------------------------------------------
   ;; `my/calc-active-selection-p' is t when calc-use-selections is on AND
   ;; some stack element has a non-nil selection field. The entry we pick
   ;; may not be the one point is on -- see `my/calc-active-entry-m-dwim'.
   ((my/calc-active-selection-p)
    (let* ((m (my/calc-active-entry-m-dwim))
           (entry (nth m calc-stack)))
      (make-my/calc--target
       :kind 'selection
       :m m
       :expr (nth 2 entry)               ; (nth 2 entry) = selected sub-expr
       :parent-formula (car entry))))    ; (car entry)   = full formula

   ;; ------------------------------------------------------------------------
   ;; (2) Point at home -- treat as a normal "operate on stack level M" command.
   ;; ------------------------------------------------------------------------
   ;; `my/calc-point-is-at-home-p' is true when point is at the . line or
   ;; below. We use OPT-M directly here (not point-derived position).
   ((my/calc-point-is-at-home-p)
    (make-my/calc--target
     :kind 'home
     :m opt-m
     :expr (car (calc-top opt-m 'entry))))

   ;; ------------------------------------------------------------------------
   ;; (3) Point on a stack entry -- decide between subexpr / equation / entry.
   ;; ------------------------------------------------------------------------
   (t
    (let* ((m (calc-locate-cursor-element (point)))
           (full (car (nth m calc-stack)))
           ;; OPT-LINE is the static (line? t) opt; `calc-option-flag' is
           ;; the runtime O prefix. Either one forces whole-line targeting.
           (line? (or opt-line calc-option-flag))
           ;; Sub-formula detection skipped if we're forcing line mode, OR
           ;; if point isn't inside formula text (EOL / line-prefix area).
           (sub (and (not line?)
                     (not (eolp))
                     (not (my/calc-point-is-in-line-prefix-p))
                     (my/calc-subformula-at-point)))
           ;; Equation mapping only kicks in when no sub-formula was picked
           ;; (otherwise the user is clearly aiming at one side already) and
           ;; the formula is a relation.
           (rel (and equation-map? (null sub) (my/calc-rel-op-p full))))
      (cond
       (sub (make-my/calc--target
             :kind 'subexpr :m m
             :expr sub
             :parent-formula full))
       (rel (make-my/calc--target
             :kind 'equation :m m
             :expr full                  ; BODY's `expr' sees full formula too,
                                        ; though the macro overrides this per-side.
             :rel-op rel
             :lhs (nth 1 full)
             :rhs (nth 2 full)))
       (t   (make-my/calc--target
             :kind 'entry :m m
             :expr full)))))))


;;; ===========================================================================
;;; Write-back helper
;;; ===========================================================================
;;
;; Owns the four ways we can write a result back to the calc stack. Called
;; from the `commit' closure the macro builds; receives the kind and
;; whatever supplementary data that kind needs (parent formula, m, etc.).
;;
;; Each branch corresponds to one of the five resolver kinds; equation is
;; handled inline by the macro (it needs to run BODY twice) and never
;; reaches this function.
;;
;; Note that `calc-pop-push-record-list' is calc's standard mechanism for
;; replacing a stack item AND logging the operation in the trail; the
;; PREFIX string is the trail label ("fctr", "abs", etc.).

(defun my/calc--write-back (kind m parent old new prefix keep-args)
  "__COMMITOLD__ with NEW in the calc stack and log PREFIX in the trail.
KIND, M, PARENT come from the resolver; KEEP-ARGS preserves the
`calc-keep-args' behavior of the original macro (when set, pushes the
new value on top instead of replacing in place)."
  (pcase kind

    ;; SELECTION: rebuild the enclosing formula by substituting OLD->NEW
    ;; inside PARENT, then push BOTH the new formula and the new selection
    ;; value (so calc can re-select the equivalent sub-expression).
    ('selection
     (calc-pop-push-record-list
      1 prefix (calc-replace-sub-formula parent old new) m new))

    ;; SUBEXPR: same shape as selection but no need to record the new
    ;; sub-expression for re-selection -- it wasn't a real selection.
    ('subexpr
     (calc-pop-push-record-list
      1 prefix (calc-replace-sub-formula parent old new) m))

    ;; ENTRY: NEW is already the full formula; just push it.
    ('entry
     (calc-pop-push-record-list 1 prefix new m))

    ;; HOME: same as entry, but `calc-keep-args' overrides M -> 1, since
    ;; keep-args is supposed to leave the original argument on the stack
    ;; and push the result on top (M=1).
    ('home
     (calc-pop-push-record-list 1 prefix new (if keep-args 1 m)))))


;;; ===========================================================================
;;; Cursor capture & restore
;;; ===========================================================================
;;
;; Functional form of point preservation: a struct captured before the
;; operation, plus a restore function called after. No macro wrapper.
;;
;; LAYERING: capture and restore are peer pre/post operations called at
;; the COMMAND-SHELL level (in `my/defcmd''s expansion). `my/calc-push'
;; itself never touches the cursor.
;;
;; The restore function takes the captured state AND the resolved
;; TARGET-KIND. The kind drives the restoration rule -- this makes the
;; conceptual dependency ("cursor behavior depends on what was targeted")
;; explicit in the function signature, instead of relying on proxy
;; predicates (sel-active-pre, at-home-pre) that happen to align with
;; the resolver's choice.
;;
;; Restoration rules (in priority order):
;;
;;   1. KIND is 'selection -> restore point exactly. Calc rebuilds the
;;      stack with the new selection at the same visual location, so
;;      `goto-char POINT' lands the cursor on the updated value.
;;
;;   2. KIND is 'home, OR keep-args was set -> realign stack window.
;;      These are the cases where calc's default "land near the new top"
;;      behavior is the right one.
;;
;;   3. Otherwise ('entry / 'subexpr / 'equation) -> restore the
;;      original logical line and snap to BOL/EOL if the cursor was on
;;      a line edge.

(cl-defstruct my/calc--cursor-state
  point line col-pos keep-args)

(defun my/calc--capture-cursor-state ()
  "Snapshot pre-operation cursor + relevant flags."
  (make-my/calc--cursor-state
   :point     (point)
   :line      (line-number-at-pos)
   :col-pos   (cond ((eolp) 'eol)
                    ((my/calc-point-is-in-line-prefix-p) 'bol))
   :keep-args calc-keep-args-flag))

(defun my/calc--restore-cursor (cs kind)
  "Restore point per cursor-state CS and the resolved target KIND."
  (pcase-let (((cl-struct my/calc--cursor-state point line col-pos keep-args)
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


;;; ===========================================================================
;;; Dispatch function
;;; ===========================================================================
;;
;; `my/calc-push' is a plain function -- not a macro. It is called only
;; from expansions of `my/defcmd', which generates a lambda for BODY and
;; passes options as keyword arguments. Keeping the dispatch as a
;; function means:
;;
;;   - The logic is testable in isolation: ERT tests can call my/calc-push
;;     directly with a controlled body-fn and assert on stack state.
;;   - There is exactly one macro layer in the file (`my/defcmd'), and it
;;     deals only with call-site ergonomics (anaphoric bindings, defun
;;     shell, interactive). Everything below is straight Elisp.
;;
;; NOT included here: cursor preservation, target resolution, arity
;; setup. All three are concerns of the COMMAND SHELL (`my/defcmd''s
;; expansion). They are peer pre-body reads that produce data
;; (cursor-state, target struct, arg-val); my/calc-push consumes the
;; target and arg-val and does only the stack mutation.
;;
;; SIGNATURE
;;
;; (my/calc-push TGT ARG-VAL BODY-FN &key PREFIX WRAP SIMP)
;;
;;   TGT       a `my/calc--target' from `my/calc--resolve-target'.
;;   ARG-VAL   top stack item for BINARY commands; nil for UNARY. Its
;;             presence (non-nil) is the binary signal; when non-nil,
;;             one stack pop fires after BODY (the consumed arg).
;;   BODY-FN   (lambda (expr commit arg) ...). EXPR is the target
;;             expression; COMMIT is the writeback closure (Lisp-2
;;             function namespace); ARG is the value of ARG-VAL.

(cl-defun my/calc-push (tgt arg-val body-fn &key
                                            (prefix "")
                                            (wrap t)
                                            (simp nil))
  "Run BODY-FN against TGT with ARG-VAL.
See section comment for the signature and semantics. This function
mutates the calc stack and does NOT save or restore the cursor; the
caller is responsible for that (`my/defcmd' handles it automatically)."
  (let* ((keep-args calc-keep-args-flag)
         (kind (my/calc--target-kind tgt)))
    (cl-flet ((run-body (expr replacer)
                ;; Apply `:simp -1' as a localized no-simp wrapper around
                ;; this single body invocation. Each side of an equation
                ;; gets its own wrapper so simplification stays disabled
                ;; across the LHS+RHS pair.
                (if (eq simp -1)
                    (my/calc-without-simplification
                     (funcall body-fn expr replacer arg-val))
                  (funcall body-fn expr replacer arg-val)))
              (binary-pop ()
                ;; In binary arity, drop the consumed arg from the top
                ;; of the stack. Fires once per command, even though
                ;; equation mode invokes body twice. ARG-VAL non-nil is
                ;; the binary indicator.
                (when arg-val (calc-pop-stack 1))))
      (pcase kind

        ;; -------------------------------------------------------------
        ;; EQUATION: run body twice -- once per side -- then push the
        ;; rebuilt relation. calc-wrapper is applied once around the
        ;; pair (single undo group, one trail entry).
        ;; -------------------------------------------------------------
        ('equation
         (let ((lhs (my/calc--target-lhs tgt))
               (rhs (my/calc--target-rhs tgt))
               (op  (my/calc--target-rel-op tgt))
               (tm  (my/calc--target-m tgt)))
           (calc-wrapper
            (run-body lhs (lambda (e) (setq lhs e)))
            (run-body rhs (lambda (e) (setq rhs e)))
            (calc-pop-push-record-list 1 prefix (list op lhs rhs) tm)
            (binary-pop))))

        ;; -------------------------------------------------------------
        ;; All other kinds: one body invocation with a replacer closure
        ;; that delegates to `my/calc--write-back'. The closure captures
        ;; kind/m/parent/expr so write-back can do the right thing per
        ;; kind without the dispatch function caring.
        ;; -------------------------------------------------------------
        (_
         (let* ((expr   (my/calc--target-expr tgt))
                (tm     (my/calc--target-m tgt))
                (parent (my/calc--target-parent-formula tgt))
                (replacer (lambda (new)
                            (my/calc--write-back kind tm parent expr new
                                                 prefix keep-args))))
           (if wrap
               (calc-wrapper
                (run-body expr replacer)
                (binary-pop))
             (run-body expr replacer)
             (binary-pop))))))))


;;; ===========================================================================
;;; my/defcmd
;;; ===========================================================================
;;
;; `my/defcmd' is the only call site of `my/calc-push'. It parses
;; the user's source form, builds a lambda from BODY, and emits a
;; no-arg interactive defun:
;;
;;   (my/defcmd NAME (BINDING...) [DOCSTRING]
;;     :key1 val1
;;     :key2 val2
;;     ...
;;     BODY...)
;;
;; expands to roughly:
;;
;;   (defun NAME ()
;;     DOCSTRING
;;     (interactive)
;;     (let* (;; PEER PRE-BODY READS:
;;            (tgt (my/calc--resolve-target M LINE? EQ-MAP?))
;;            (cs  (my/calc--capture-cursor-state))
;;            ;; BINARY-only fetch of the second operand:
;;            (arg-val (when BINARY?
;;                       (my/calc-without-simplification (calc-top-n 1)))))
;;       ;; DISPATCH: target + arg-val + body -> stack mutation:
;;       (my/calc-push tgt arg-val
;;                     (lambda (EXPR _COMMIT-FN ARG)
;;                       (cl-flet ((commit (e) (funcall _COMMIT-FN e)))
;;                         BODY))               ;; only requested names visible
;;                     :prefix ... :wrap ... :simp ...)
;;       ;; RESTORE cursor, target-aware:
;;       (my/calc--restore-cursor cs (my/calc--target-kind tgt))))
;;
;; Three peer pre-body reads (target, cursor, arg-val), one dispatch
;; call, one cursor restore. `my/calc-push' takes the resolved target
;; as input; it does NOT call the resolver itself.
;;
;; Arity is derived from BINDINGS, not declared as a keyword:
;;
;;   - If the caller asks for `arg', the command is binary: m=2, the top
;;     stack item is bound to ARG, and one stack pop fires after BODY.
;;   - Otherwise the command is unary: m=1, no arg fetch, no pop.
;;
;; Source parsing:
;;
;;   After BINDINGS, an optional docstring, then zero or more
;;   `:keyword VALUE' pairs while the next form starts with a keyword,
;;   then BODY. Body never starts with a keyword in practice, so the
;;   first-non-keyword-form heuristic is unambiguous.
;;
;; Recognized BINDINGS (any subset; order does not matter):
;;
;;   expr            target expression (selection / subformula / entry)
;;   commit         function that writes a new expression back
;;   arg             top stack item -- presence promotes the command
;;                   to BINARY arity
;;
;; Recognized option keywords:
;;
;;   :prefix STR     calc trail prefix (default: \"\")
;;   :wrap BOOL      wrap body in calc-wrapper (default: t)
;;   :simp V         -1 = disable simplification (default: nil)
;;   :map? V         -1 = disable equation mapping (default: t)
;;   :line? BOOL     skip subformula detection (default: nil)
;;
;; Implementation notes:
;;
;;   - The lambda always takes four positional args because that is
;;     what `my/calc-push' invokes it with. Names the user did NOT
;;     request get gensymmed parameter names prefixed with `_' so the
;;     byte compiler does not flag them as unused.
;;
;;   - COMMIT is special: it is a function (the body calls
;;     `(commit X)'). Emacs is Lisp-2, so a lambda parameter is in
;;     the variable namespace and `(commit X)' would not find it.
;;     We always receive the function under a gensymmed variable name
;;     and, if the user asked for `commit', expose it in the function
;;     namespace via `cl-flet'.
;;
;;   - The one existing outlier (`my/calc-expand', which takes a
;;     prefix arg) cannot go through `my/defcmd' as currently shaped.
;;     See Example 2 below; add `:arglist' / `:interactive' keywords
;;     if more arg-taking commands appear.
;;
;; (declare (indent 2) (doc-string 3)) places the docstring at arg 3
;; and indents everything after BINDINGS (keywords + body) at body
;; indent. Because keyword args and body forms sit at the same indent
;; level, no special indent rule is needed beyond `indent 2'.
;;
;; The macro delegates source-form parsing to two helpers:
;;   `my/defcmd--validate-bindings' checks BINDINGS against the known
;;     set.
;;   `my/defcmd--parse-rest' peels the optional docstring, collects
;;     leading `:keyword VALUE' pairs, and validates them against the
;;     known set. Returns (DOCSTRING OPTS BODY).

(defconst my/defcmd--known-bindings '(expr commit arg)
  "BINDING names accepted by `my/defcmd'.
Each name may be requested by a caller and will be made visible inside
BODY (as a lexical variable, or as a `cl-flet'-bound function in the
case of `commit'). Presence of `arg' promotes the command to BINARY
arity (see the section comment above).")

(defconst my/defcmd--known-options
  '(:prefix :wrap :simp :map? :line?)
  "Option keywords accepted by `my/defcmd'.
See the section comment above for what each keyword controls.")

(defun my/defcmd--validate-bindings (bindings name)
  "Signal an error if BINDINGS contains any name not allowed.
The allowed set is `my/defcmd--known-bindings'. NAME is the function
being defined; used in the error message."
  (let ((unknown (cl-set-difference bindings my/defcmd--known-bindings)))
    (when unknown
      (error "Unknown binding(s) in my/defcmd %s: %s" name unknown))))

(defun my/defcmd--parse-rest (rest name)
  "Parse the after-BINDINGS tail of a `my/defcmd' source form.

REST is everything after NAME and BINDINGS. Returns the list
\(DOCSTRING OPTS BODY) where:

  - DOCSTRING is the first form if it is a string AND there is more
    content after it; nil otherwise. (The trailing-content guard
    prevents stealing a lone string body, since the macro must always
    emit at least one body form.)

  - OPTS is an alist of (:keyword . value) pairs collected while the
    next form is a keyword. Body forms never begin with a keyword in
    practice, so this heuristic is unambiguous.

  - BODY is everything that remains after the docstring and keyword
    pairs have been peeled off.

Signals an error if any keyword in OPTS is not in
`my/defcmd--known-options'. NAME is the function being defined; used
in the error message."
  (let ((docstring (and (stringp (car rest)) (cdr rest) (pop rest)))
        (opts nil))
    (while (keywordp (car rest))
      (let ((k (pop rest))
            (v (pop rest)))
        (push (cons k v) opts)))
    (let ((unknown (cl-set-difference (mapcar #'car opts)
                                      my/defcmd--known-options)))
      (when unknown
        (error "Unknown option(s) in my/defcmd %s: %s" name unknown)))
    (list docstring opts rest)))

(defmacro my/defcmd (name bindings &rest rest)
  "Define a no-arg interactive calc command NAME wrapping `my/calc-push'.
See the section comment above this defmacro for syntax and keywords."
  (declare (indent 2) (doc-string 3))
  (my/defcmd--validate-bindings bindings name)
  (seq-let (docstring opts body) (my/defcmd--parse-rest rest name)
    (let* (;; Arity is derived from BINDINGS: requesting `arg' opts in
           ;; to binary mode (m=2, fetch top stack item, auto-pop 1).
           (binary? (memq 'arg bindings))
           ;; Lambda parameter names. Visible if the user requested the
           ;; binding by name; gensymmed with `_' prefix otherwise so
           ;; the byte compiler does not warn about unused params.
           (sym-expr (if (memq 'expr bindings) 'expr (gensym "_unused-expr-")))
           (sym-arg  (if (memq 'arg  bindings) 'arg  (gensym "_unused-arg-")))
           ;; COMMIT always arrives as a function value (in the
           ;; variable namespace); cl-flet bridges it into the function
           ;; namespace when the user asked for it.
           (raw-commit-fn (gensym "_commit-fn-"))
           (lambda-body
            (if (memq 'commit bindings)
                `((cl-flet ((commit (e) (funcall ,raw-commit-fn e)))
                    ,@body))
              body)))
      `(defun ,name ()
         ,@(when docstring (list docstring))
         (interactive)
         (let* (;; Three peer pre-body reads. Order is irrelevant -- none
                ;; depends on the others' values (only on pre-body state).
                (tgt (my/calc--resolve-target
                      ,(if binary? 2 1)
                      ,(alist-get :line? opts nil)
                      ,(not (eq (alist-get :map? opts t) -1))))
                (cs (my/calc--capture-cursor-state))
                ;; Binary-only fetch -- guarded so unary doesn't error
                ;; on an empty stack.
                (arg-val ,(when binary?
                            '(my/calc-without-simplification (calc-top-n 1)))))
           (my/calc-push
            tgt arg-val
            (lambda (,sym-expr ,raw-commit-fn ,sym-arg)
              ,@lambda-body)
            :prefix ,(alist-get :prefix opts "")
            :wrap   ,(alist-get :wrap   opts t)
            :simp   ,(alist-get :simp   opts nil))
           (my/calc--restore-cursor cs (my/calc--target-kind tgt)))))))


;;; ===========================================================================
;;; Call-site conversion examples
;;; ===========================================================================
;;
;; Three real call sites from stack.el, before and after.
;;
;; ---------------------------------------------------------------------------
;; Example 1: unary, no options.
;; ---------------------------------------------------------------------------
;;
;; BEFORE (current lib.el):
;;
;;   (defun my/calc-factor ()
;;     "Factor the active selection or whole stack entry at point."
;;     (interactive)
;;     (my/calc-replace-expr-dwim (expr replace-expr) ((prefix "fctr"))
;;       (replace-expr (calcFunc-factor expr))))
;;
;; AFTER:
;;
;;   (my/defcmd my/calc-factor (expr commit)
;;     "Factor the active selection or whole stack entry at point."
;;     :prefix "fctr"
;;     (commit (calcFunc-factor expr)))
;;
;; ---------------------------------------------------------------------------
;; Example 2: BINARY (requests `arg' -- top of stack is the right operand).
;; ---------------------------------------------------------------------------
;;
;; BEFORE (current lib.el):
;;
;;   (defun my/calc-factor-by ()
;;     "Factor the target expression by the top stack item."
;;     (interactive)
;;     (my/calc-replace-expr-dwim (expr replace-expr top)
;;         ((m 2) (prefix "fctr") (simp -1))
;;       (let* ((factor top)
;;              (divided (-> (calcFunc-div expr factor) calcFunc-expand
;;                           calcFunc-nrat calcFunc-expand math-simplify))
;;              (factored (calcFunc-mul factor divided)))
;;         (replace-expr factored)
;;         (calc-pop-stack 1))))
;;
;; AFTER (binary arity: m=2 default, top stack item bound to `arg', pop 1
;; after body -- all derived from the presence of `arg' in BINDINGS):
;;
;;   (my/defcmd my/calc-factor-by (expr commit arg)
;;     "Factor the target expression by the top stack item."
;;     :prefix "fctr"
;;     :simp -1
;;     (let* ((factor arg)
;;            (divided (-> (calcFunc-div expr factor) calcFunc-expand
;;                         calcFunc-nrat calcFunc-expand math-simplify))
;;            (factored (calcFunc-mul factor divided)))
;;       (commit factored)))
;;
;; ---------------------------------------------------------------------------
;; Example 3: prefix-arg-taking command -- calls `my/calc-push' directly.
;; ---------------------------------------------------------------------------
;;
;; `my/defcmd' supports only no-arg interactive commands. The single
;; command that reads a prefix arg (`my/calc-expand') therefore writes
;; the resolve + capture + dispatch + restore dance by hand. It is
;; unary (no `arg' binding), so arg-val is nil and the home-case stack
;; level is 1:
;;
;;   (defun my/calc-expand (n)
;;     "Expand the active selection, sub-formula at point, or top stack entry.
;;   With numeric prefix N, expand only N levels deep."
;;     (interactive "P")
;;     (let* ((tgt (my/calc--resolve-target 1 nil t))
;;            (cs  (my/calc--capture-cursor-state)))
;;       (my/calc-push tgt nil
;;                     (lambda (expr commit-fn _arg)
;;                       (funcall commit-fn
;;                                (if n (calcFunc-expand expr (prefix-numeric-value n))
;;                                  (calcFunc-expand expr))))
;;                     :prefix "expa")
;;       (my/calc--restore-cursor cs (my/calc--target-kind tgt))))
;;
;; This four-line dance is exactly what `my/defcmd' generates for the
;; no-arg case. If more prefix-arg-taking commands appear, add
;; `:arglist' and `:interactive' KEYWORDS to `my/defcmd' so it can
;; generate the shape automatically.


;; (provide 'my/calc/lib-refactor-sketch)
