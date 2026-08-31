;; -*- lexical-binding: t; -*-
;;
;; maf-defcmd.el
;;
;; Defines the `maf-defcmd' macro for declaring contextual calc commands.
;; A defcmd inspects point and the calc stack at call time, resolves a context
;; (home, entry, selection, etc.), and commits its result to the right location.

(require 'calc)  ; the macro expands to `calc-wrapper', defined in calc
(require 'maf-lib)
(require 'maf-resolve)
(require 'maf-commit)

(defvar maf-map-flag nil
  "Non-nil while the next contextual command should map over its subject.
Set by `mafcmd-map-flag' (M) through calc's fancy-prefix machinery, and
consumed by the next `maf-defcmd' command: a vector subject runs the
body once per element (`maf--defcmd-map-vec'), a relation subject runs
it once per side — even for commands that opt out with :map -1, though
those split only an =; ordered relations and != refuse
(`maf--resolve-mapflag-relation-check') — and anything else refuses:
the flag promised a mapping, and a subject with no elements has
nowhere to map. The consuming command clears it up
front, signal or not; `maf--map-flag-expire' sweeps it when the next
command is not one that reads it.")

(defvar maf-target nil
  "The resolved target, bound while a `maf-defcmd' body runs.
One of the `:target' symbols `maf--resolve-context' produces — `home',
`entry', `equation', `selection', `subexpr', or `region'.

Bodies read it when the shape of the result depends on where it will
land, not just on the operand. A whole stack entry (`home', `entry')
accepts a list of values, committed as separate stack entries; any
other target holds exactly one expression. `mafcmd-unpack' is the
case in point: it spreads its entry's parts across the stack, except
when the map flag forces a relation apart per side (`equation'), where
each side's slot fits only a single part.")

(defun maf--defcmd-parse-docstring (forms)
  "Return the docstring from FORMS if the first element is a string, else nil."
  (when (stringp (car forms))
    (car forms)))

(defun maf--defcmd-parse-opts (forms)
  "Return an alist of keyword-value pairs from FORMS.
Skips a leading docstring."
  ;; Strip docstring
  (when (stringp (car forms)) (pop forms))
  (let (final-opts)
    (while (keywordp (car forms))
      (seq-let (k v) (list (pop forms) (pop forms))
        (push (cons k v) final-opts)))
    final-opts))

(defconst maf--narrowing-targets '(region selection subexpr)
  "The three narrowing gestures a *-targets variable may name.
The other targets — home, entry, equation — are not gestures but the
places a subject lands when nothing narrows, so they are not on the
menu: every command has them.")

(defun maf--defcmd-validate-opts (opts)
  "Validate OPTS, signaling an error if any are invalid."
  (let ((arity (alist-get :arity opts))
        (tdecl (assq :targets opts)))
    (unless arity
      (error "Missing required option :arity"))
    (unless (memq arity '(unary binary))
      (error "Invalid :arity %s (expected unary or binary)" arity))
    ;; assq, not alist-get: an explicitly empty declaration must not
    ;; read as absent — it would silently grant full capability, the
    ;; opposite of what it says. The two things it could mean are
    ;; already spelled :scope entry and :targets custom.
    (when tdecl
      (let ((targets (cdr tdecl)))
        (unless (or (eq targets 'custom)
                    (and (consp targets)
                         (seq-every-p (lambda (s)
                                        (memq s maf--narrowing-targets))
                                      targets)))
          (error "Invalid :targets %s (custom or a nonempty subset of %s; for no capability say :scope entry or :targets custom)"
                 targets maf--narrowing-targets))))))

(defun maf--targets-checked (value capability name)
  "Return VALUE, signaling when it names a target outside CAPABILITY.
VALUE is a *-targets variable's current list, NAME the command about
to consult it. The bound is what makes the variable safe to edit
freely: a gesture the command's body cannot take — or a misspelled
one — signals here, loudly, instead of resolving nonsense."
  (unless (proper-list-p value)
    (user-error "%s: targets must be a list of gestures, not %S" name value))
  (let ((extra (seq-difference value capability)))
    (when extra
      (user-error "%s cannot target %s" name (car extra))))
  value)

(defun maf--defcmd-parse-body (forms)
  "Return the body forms from FORMS.
Skips a leading docstring and keyword-value pairs."
  ;; Strip docstring and options
  (when (stringp (car forms)) (pop forms))
  (while (keywordp (car forms)) (pop forms) (pop forms))
  forms)

(defun maf--defcmd-parse-rest (forms)
  (let ((docstring (maf--defcmd-parse-docstring forms))
        (opts (maf--defcmd-parse-opts forms))
        (body (maf--defcmd-parse-body forms)))
    `(,docstring ,opts ,body)))

(defun maf--defcmd-map-vec (runner expr arg)
  "Run RUNNER over each element of vector EXPR; return the mapped vector.
RUNNER is a defcmd body as a function of (ELEMENT ARG COMMIT-FN): each
element runs the body once, ARG shared across the runs, and what the
body commits becomes the element's replacement. A body that commits
nothing leaves its element unchanged. Nested vectors recurse, so a
matrix maps over its individual elements — the same reading
`mafcmd-map' gives one. A non-vector subject is the degenerate map:
the body runs once on the whole expression, so M Q on a scalar is
plain Q (a relation never reaches here — it resolves to the equation
target first)."
  (if (eq (car-safe expr) 'vec)
      (cons 'vec
            (mapcar (lambda (el)
                      (if (eq (car-safe el) 'vec)
                          (maf--defcmd-map-vec runner el arg)
                        (let (out)
                          (funcall runner el arg (lambda (val) (setq out val)))
                          (or out el))))
                    (cdr expr)))
    (let (out)
      (funcall runner expr arg (lambda (val) (setq out val)))
      (or out expr))))

(defvar maf--dispatch-narrowing nil
  "Narrowing policy riding a flag dispatch to a variant command.
The policy of the key the user pressed governs, whichever variant
answers it: I L maps through ln's *-targets variable even though
`mafcmd-exp' runs, and H E through exp's even though `mafcmd-exp10'
does — a variant reached from two families cannot say this statically.
Bound by `maf--defcmd-dispatch' to a one-element list holding the
invoking command's checked policy, which the dispatched command
prefers over its own variable. The wrapper is what keeps an empty
policy distinct from no policy: (nil) rides \"whole entry always\",
bare nil (a direct, undirected invocation) means use your own.")

(defun maf--defcmd-dispatch (cmd flag-desc &optional policy capability name)
  "Consume calc's Inverse/Hyperbolic flags, then invoke variant command CMD.
The flags are cleared before CMD runs, so a variant that itself declares
flag variants does not dispatch again — that is what keeps cross-linked
pairs like ln <-> exp from looping. CMD resolves its own context, and its
`calc-do' epilogue refreshes the mode line as usual. A nil CMD means the
invoking command has no FLAG-DESC variant: signal `user-error', still
consuming the flags so the next command starts clean.

POLICY is the invoking command's targeting policy, raw, with its
CAPABILITY and NAME; a non-nil CAPABILITY means the invoker has a
policy to send, which rides so the variant honors the pressed key's
variable (see `maf--dispatch-narrowing'). It is validated here, not at
the call — an argument is evaluated before the callee runs, and a
misconfigured variable must not signal past the flag consumption
above, stranding I or H for the next command."
  (setq calc-inverse-flag nil
        calc-hyperbolic-flag nil)
  (if cmd
      (let ((maf--dispatch-narrowing
             (and capability
                  (list (maf--targets-checked policy capability name)))))
        (call-interactively cmd))
    (calc-set-mode-line)
    (user-error "No %s variant for this command" flag-desc)))

(defmacro maf-defcmd (name bindings &rest rest)
  "Define NAME as an interactive contextual calc command.

BINDINGS is a three-symbol list (EXPR ARG COMMIT) naming the locals the
body sees:

  EXPR    The operand the command acts on, resolved from context — the
          formula at home/entry, the selected sub-expression, the one
          under point, etc. For an equation target the body runs once
          per side, with EXPR bound to the LHS and then the RHS.
  ARG     The second operand for `binary' commands (taken from the calc
          stack top); nil for `unary' commands.
  COMMIT  A local function; call it with the result to write it back to
          the resolved location. Call it once per body run (once per
          side, for an equation target). At a whole-entry target the
          result may be a list of values, committed as one stack entry
          each; a sub-formula slot takes a single expression. Bodies
          that can produce either read `maf-target' to tell which
          applies.

REST is an optional docstring, then zero or more keyword-value option
pairs (OPTS), then the body forms — in that order.

OPTS configure context resolution and commit:

  :arity  Required. `unary' or `binary'. Selects whether ARG is taken
          from the stack and drives how each target resolves EXPR/ARG.
  :prefix String label recorded in the calc trail for the operation.

  :title  The command's proper name, spelled out — \"power\" for
          mafcmd-pow. For the surfaces that list commands to read by,
          where the symbol is an abbreviation.
  :example
          One line showing what the command does, by convention a
          subject, an arrow and the result: \"x, 2 => x^2\". Both are
          plain strings, stamped on the symbol and read back through
          `maf-command-title' and `maf-command-example'; both are
          optional, and every reader of them falls back.

  :inverse             Command (symbol) to run instead when calc's
  :hyperbolic          Inverse flag is set (the I prefix), the
  :inverse-hyperbolic  Hyperbolic flag (H), or both. The flags are
          consumed before the variant runs, so variants may themselves
          declare variants (cross-links like ln <-> exp do not loop).
          When a flag is set but the matching variant is absent, the
          command signals `user-error' and still consumes the flags.

  :map    When -1, opt out of per-side equation mapping: a subject that
          is a relation stays whole in EXPR instead of the body running
          once per side. For commands that consume or produce relations
          (solve, mapeq, the relation builders).

  :pair   When -1, keep a relation ARG whole at an equation target
          instead of pairing its two sides with the subject's sides. For
          commands that consume a relation argument as one operand.

Independent of OPTS, every defcmd answers the map flag (`maf-map-flag',
set by M): a vector subject runs the body once per element with the
result reassembled in place, a relation subject runs it once per side
even under :map -1 — though a command forced past :map -1 splits only
an =; ordered relations and != refuse — and any other subject refuses.
The flag is consumed up front, so it never leaks past the command that
received it.

  :scope  Narrows which targets resolve. `entry' takes the whole entry
          at point (the top at home) whatever the gesture, for commands
          with no sub-formula meaning; `explicit' takes it whole only
          when the narrowing was implicit, so a region or a calc
          selection still picks out a part. Absent, every target
          resolves as usual. See `maf--resolve-context'.

  :commit-scope
          When `entry', the body's value replaces the whole entry at
          the target's stack level rather than being spliced back into
          the sub-formula slot the target named. The command still
          resolves a part from point; what differs is that the part
          stands as the entry afterwards, the formula around it gone
          (`mafcmd-raise'). Independent of `:scope', which decides what
          the body receives, not where the result lands.

  :targets     The narrowing gestures the command's body can take at
          all: a nonempty subset of (region selection subexpr), or
          `custom' for a command whose targeting is bespoke. An
          explicit nil is rejected — its two readings are already
          spelled `:scope entry' and `custom'. Unless `custom' — or
          the command is `:scope entry' with no :targets declared,
          which bounds it to nothing — the macro generates a NAME-targets
          variable holding the gestures the command currently honors
          (defaulted from :scope), consulted on every run: the user
          edits that list to retune the command's targeting, and a
          gesture outside the declared bound signals.
  :targets-var Symbol naming the generated variable instead of
          NAME-targets — for a worker whose public command is the name
          users know; two workers of one public command name the same
          variable and share it.

  :widen  A predicate (named as a bare symbol) deciding which
          sub-formulas the command can act on. At the subexpr target the
          node under point is widened outward to the innermost ancestor
          the predicate accepts, so a command whose result does not fit
          the node point names can still act on the enclosing node that
          holds it, rather than doing nothing. Explicit calc selections
          are never widened. See `maf--resolve-widen'.

Any other keyword in OPTS is merged verbatim into the resolved context
alist, so resolve/commit extensions can read it.

At call time the command resolves point and the calc stack into a
context (home, entry, selection, subexpr, or equation), binds EXPR and
ARG, runs the body, and commits its result to the right stack location."
  (declare (indent 2) (doc-string 3))
  (pcase-let* ((`(,docstring ,opts ,body) (maf--defcmd-parse-rest rest))
               (`(,expr ,arg ,commit) bindings)
               (inv (alist-get :inverse opts))
               (hyp (alist-get :hyperbolic opts))
               (invhyp (alist-get :inverse-hyperbolic opts))
               (scope (alist-get :scope opts))
               (targets-opt (alist-get :targets opts))
               ;; The narrowing gestures this command can honor at all.
               ;; Empty — declared custom, or entry-scoped with nothing
               ;; declared — means no policy variable is generated: a
               ;; knob that could hold only nil would be a knob that
               ;; lies.
               (capability (cond ((eq targets-opt 'custom) nil)
                                 ((consp targets-opt) targets-opt)
                                 ((eq scope 'entry) nil)
                                 (t maf--narrowing-targets)))
               (tvar (and capability
                          (or (alist-get :targets-var opts)
                              (intern (format "%s-targets" name)))))
               ;; The default policy encodes the declared :scope, so
               ;; the variable's initial value is the behavior the
               ;; command shipped with. An entry-scoped command with a
               ;; declared capability is the "entry by default, user
               ;; may enable" case: the capability opens the door, the
               ;; default leaves it shut.
               (tdefault (pcase scope
                           ('entry nil)
                           ('explicit (seq-intersection
                                       '(region selection) capability))
                           (_ capability)))
               ;; What the resolve call receives: the policy rides in as
               ;; :narrowing, checked against capability on every run so
               ;; edits fail loudly, not silently. A policy sent along
               ;; by a flag dispatch — the pressed key's — outranks this
               ;; command's own variable (see `maf--dispatch-narrowing').
               (baseopts (if tvar
                             `(cons (cons :narrowing
                                          (maf--targets-checked
                                           (if maf--dispatch-narrowing
                                               (car maf--dispatch-narrowing)
                                             ,tvar)
                                           ',capability ',name))
                                    ',opts)
                           `',opts))
               (context (gensym "context-"))
               (landed (gensym "landed-"))
               (err (gensym "err-"))
               (lhs (gensym "lhs-"))
               (rhs (gensym "rhs-"))
               (mapflag (gensym "mapflag-"))
               (runner (gensym "runner-"))
               (oarg (gensym "oarg-"))
               (relem (gensym "elem-"))
               (rarg (gensym "arg-"))
               (rcommit (gensym "commit-"))
               (main
                ;; `calc-wrapper' makes the whole command a single undoable
                ;; unit and runs calc's command epilogue (trail, stack
                ;; refresh/renumber, point). The context and commit's return
                ;; (where the result landed) are hoisted out so point can be
                ;; restored after the epilogue — anything done inside the
                ;; wrapper would be clobbered by it.
                `(let (,context ,landed)
                   (condition-case ,err
                       (progn
                         (calc-wrapper
                          ;; The map flag (M) is consumed here: snapshot and
                          ;; clear before resolve, so a command that signals
                          ;; still leaves the next command clean. Resolve
                          ;; sees it as :mapflag, which forces a relation
                          ;; subject to the equation target even past
                          ;; :map -1.
                          (let ((,mapflag (prog1 maf-map-flag
                                            (setq maf-map-flag nil))))
                            (setq ,context
                                  (maf--resolve-context
                                   (if ,mapflag
                                       (cons '(:mapflag . t) ,baseopts)
                                     ,baseopts)))
                            ;; A gensym, not the caller's ARG symbol: the
                            ;; runner binds that one per run, and a `_'-named
                            ;; ARG must stay unused outside the body.
                            (let ((,oarg (alist-get :arg ,context))
                                  (maf-target (alist-get :target ,context))
                                  ;; The body as a function: bind the
                                  ;; caller's EXPR/ARG locals and route its
                                  ;; COMMIT to the given continuation. Every
                                  ;; branch below runs the body through it.
                                  (,runner
                                   (lambda (,relem ,rarg ,rcommit)
                                     (let ((,expr ,relem)
                                           (,arg ,rarg))
                                       (cl-flet ((,commit (val)
                                                   (funcall ,rcommit val)))
                                         ,@body)))))
                              (cond
                               ((eq maf-target 'equation)
                                ;; Equation target: run the body once per side
                                ;; (expr bound to the LHS, then the RHS),
                                ;; capturing each side's committed result. Then
                                ;; reassemble into a new relation and commit
                                ;; once. Both sides share the arg bound above,
                                ;; unless the arg is an equation too, in which
                                ;; case resolve split it and each side gets its
                                ;; own half — the two relations pair up rather
                                ;; than each side taking the whole arg as a
                                ;; term (see `maf--resolve-pair-arg').
                                (let (,lhs ,rhs)
                                  (funcall ,runner
                                           (alist-get :lhs ,context)
                                           (or (alist-get :arg-lhs ,context)
                                               ,oarg)
                                           (lambda (val) (setq ,lhs val)))
                                  (funcall ,runner
                                           (alist-get :rhs ,context)
                                           (or (alist-get :arg-rhs ,context)
                                               ,oarg)
                                           (lambda (val) (setq ,rhs val)))
                                  (setq ,landed
                                        (maf--commit
                                         (list (alist-get :rel-op ,context)
                                               ,lhs ,rhs)
                                         ,context))))
                               (,mapflag
                                ;; Map flag, and the subject was no relation:
                                ;; it must be a vector, mapped elementwise
                                ;; with the arg shared across the runs.
                                (setq ,landed
                                      (maf--commit
                                       (maf--defcmd-map-vec
                                        ,runner (alist-get :expr ,context)
                                        ,oarg)
                                       ,context)))
                               (t
                                ;; All other targets: body runs once on :expr.
                                (funcall ,runner
                                         (alist-get :expr ,context) ,oarg
                                         (lambda (val)
                                           (setq ,landed
                                                 (maf--commit
                                                  val ,context)))))))))
                         ;; An entry the user typed as part of this gesture
                         ;; folds into this command's undo group, so one undo
                         ;; reverts both instead of stranding the push: the
                         ;; arg of 1 +, and equally the subject of a unary
                         ;; command dispatched off the entry's own
                         ;; terminator (400 o). Gated on the digit handoff,
                         ;; so a deliberate push (1 RET, the command later)
                         ;; keeps its own group.
                         (maf--undo-amalgamate-digit-entry)
                         ;; The epilogue parks point at home; put it back on
                         ;; what the command acted on — the committed node's
                         ;; glyph or its start, else where resolve found it
                         ;; (see `maf--point-restore-commit').
                         (maf--point-restore-commit ,context ,landed)
                         ;; Keep the resolve-time snapshot for undo: a single
                         ;; `maf-undo' of this command puts point back where it
                         ;; was before the command ran.
                         (maf--undo-record-cmd-point (alist-get :point ,context)))
                     ;; A body that signals inside `calc-wrapper' unwinds
                     ;; through calc's refresh, which parks point at home. Put
                     ;; point back where resolve found it (best effort — only
                     ;; when context was resolved) so a failed command does not
                     ;; teleport the cursor, then re-raise so the error still
                     ;; reaches the echo area.
                     (error
                      (when ,context
                        (maf--point-restore-commit ,context ,landed))
                      (signal (car ,err) (cdr ,err)))))))
    (maf--defcmd-validate-opts opts)
    `(progn
       ;; The command's targeting policy, a variable so the user edits
       ;; a list instead of diving into config structure. `defvar'
       ;; leaves an existing value standing, so a setq in the init file
       ;; survives however load order falls — and a variable shared
       ;; between two workers of one public command is defined by
       ;; whichever loads first, the other a no-op.
       ,@(when tvar
           (list
            `(defvar ,tvar ',tdefault
               ,(format "Narrowing targets `%s' honors, a subset of %S.
These are the gestures that narrow the subject to a sub-formula under
point; the whole-entry targets (home, entry, equation) are always on.
Remove a symbol and the command ignores that gesture, taking the whole
entry at point instead: the gesture is never chosen as the subject and
never captures the result, though a selection living on the very entry
the command rewrites is gone with that entry. A symbol outside the
subset above signals when the command runs."
                        (replace-regexp-in-string
                         "-targets\\'" "" (symbol-name tvar))
                        capability))))
       ;; Mark the command as one that accepts calc's prefix flags. The
       ;; commit path reads the resolve-time `:keep' snapshot, so keep-args
       ;; means something here in a way it does not for a hand-written stack
       ;; command. `maf--fancy-prefix-keep' reads the property to decide
       ;; which keys may carry a flag past calc's fancy prefix; a plain
       ;; `defun' that wants the same treatment sets it by hand (see
       ;; `maf-dup-or-clear-selections').
       (put ',name 'maf-command t)
       ,@(let ((title (alist-get :title opts))
               (example (alist-get :example opts)))
           (when (or title example)
             `((maf-set-command-doc ',name ,title ,example))))
       (defun ,name ()
         ,@(when docstring (list docstring))
         (interactive)
         ,(if (or inv hyp invhyp)
              ;; Calc's I/H flags reroute to the declared variant command
              ;; before any context is resolved (and before calc-wrapper, so
              ;; the variant's own wrapper is the only one that runs).
              ;; The policy rides raw — dispatch validates it after
              ;; consuming the flags, so a misconfigured variable
              ;; cannot strand I or H set for the next command.
              `(cond ((and calc-inverse-flag calc-hyperbolic-flag)
                      (maf--defcmd-dispatch ,(and invhyp `#',invhyp)
                                            "inverse hyperbolic"
                                            ,tvar ',capability ',name))
                     (calc-inverse-flag
                      (maf--defcmd-dispatch ,(and inv `#',inv) "inverse"
                                            ,tvar ',capability ',name))
                     (calc-hyperbolic-flag
                      (maf--defcmd-dispatch ,(and hyp `#',hyp) "hyperbolic"
                                            ,tvar ',capability ',name))
                     (t ,main))
            main)))))

(provide 'maf-defcmd)
