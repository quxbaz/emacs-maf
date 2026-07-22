;; -*- lexical-binding: t; -*-
;;
;; maf-resolve.el
;;
;; Resolve point and calc state into a target-specific context descriptor.
;;
;; ----------------------------------------------------------------------------
;; Context schema (alist returned by `maf--resolve-context')
;; ----------------------------------------------------------------------------
;;
;; Target-specific keys (produced by `maf--resolve-target-*'):
;;
;;   :target       Symbol identifying the target: region, home, selection,
;;                 subexpr, equation, or entry.
;;   :expr         The expression the command operates on (full formula or
;;                 selected sub-formula, depending on target). Clean — the
;;                 (cplx N 0) encasing that calc-prepare-selection wraps atoms
;;                 in is stripped (`maf--strip-encasing') so the body sees
;;                 clean values, but never re-normalized, which could
;;                 re-simplify the user's formula.
;;   :expr-ref     The same sub-formula as :expr but as the *original encased
;;                 cons cell* from the stack entry. Used by commit's
;;                 `calc-replace-sub-formula` for eq-based splicing — only the
;;                 encased ref matches the cons in the entry. Set only for
;;                 selection and subexpr.
;;   :arg          Second operand for binary commands; nil for unary.
;;   :m            Stack position (1 = top) of the target entry. Only set when
;;                 the target lives at a specific stack level (e.g. selection).
;;   :point-anchor Index of point's glyph among the structural glyphs the
;;                 resolved sub-formula renders itself (operator, comma,
;;                 function name), or nil when point is inside an operand.
;;                 Subexpr target only — used to re-anchor point on the
;;                 committed node after the rewrite.
;;   :rel-op       Relation operator symbol (calcFunc-eq/neq/lt/...). Equation
;;                 target only — the macro uses it to reassemble the relation
;;                 after running the body once per side.
;;   :chain-ref    Region target only — the encased cons of the chain the
;;                 region's run was carved from; commit splices the rebuilt
;;                 chain at it.
;;   :chain-kind   Region target only — sum or prod (see maf-chain.el).
;;   :pre-terms,
;;   :post-terms   Region target only — the untouched (OP . TERM) chain terms
;;                 before and after the run, original conses intact.
;;   :lhs, :rhs    The two sides of the relation. Equation target only — the
;;                 macro binds :expr to each in turn for the per-side body runs.
;;
;; Commit instructions (consumed by `maf--defcmd-commit'):
;;
;;   :commit-m     Stack level where the result is pushed.
;;   :commit-n     N argument to `calc-pop-push-record-list' — number of
;;                 entries popped at :commit-m before pushing.
;;   :post-pop     Number of entries popped from the top *after* the push,
;;                 to consume extra inputs (e.g. the binary arg on selection).
;;   :reselect     If non-nil, commit carries the result as the new selection
;;                 on the pushed entry. Set for targets with an explicit
;;                 user-set selection (selection); nil for implicit ones
;;                 (subexpr) where there's no selection to preserve.
;;
;; Merged in by `maf--resolve-context':
;;
;;   :arity        From OPTS: unary or binary.
;;   :prefix       From OPTS: calc trail label.
;;   :keep         Snapshot of `calc-keep-args-flag' at resolve time.
;;   :point        Snapshot of point's placement at resolve time (see
;;                 `maf--point-snapshot'). The generated command restores
;;                 point from it after the calc epilogue runs.
;;   ...any other keyword option passed to `maf-defcmd'.

(require 'maf-lib)
(require 'maf-sel)
(require 'maf-comp)
(require 'maf-chain)

;; Defined in lazily-loaded calc modules; calc-ext's autoload registry
;; resolves them at runtime, but the byte compiler needs declarations.
(declare-function calc-top "calc-ext")
(declare-function calc-locate-cursor-element "calc-yank")
(declare-function calc-prepare-selection "calc-sel")
(declare-function calc-find-selected-part "calc-sel")

;; calc-sel declares this with a valueless defvar, which marks it
;; special only within its own file; redeclare so our read is dynamic.
(defvar calc-selection-cache-offset)


(defun maf--resolve-target-selection (opts)
  "Return the selection target's context alist.
:expr is the selected sub-expression. The chosen entry is the one under point
when it has a selection, otherwise the top-most entry with an active selection.

For binary commands, :arg is the top of the stack. Binary commands require the
selected entry to be below the top (:m > 1); otherwise the arg would be the
entry containing the selection, which has no coherent commit semantics."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (m (maf--sel-effective-m))
           (keep calc-keep-args-flag)
           (encased (maf--sel-effective-expr)))
      ;; If m=1 and arity=binary then there's nowhere to take the arg from - reject.
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on selection require the selected entry below the top"))
      `((:target     . selection)
        ;; :expr is the clean form for the body — encasing stripped, but
        ;; not re-normalized, which could re-simplify what the user
        ;; selected. :expr-ref is the encased cons commit needs for
        ;; eq-based splicing.
        (:expr       . ,(maf--strip-encasing encased))
        (:expr-ref   . ,encased)
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:m          . ,m)
        (:commit-m   . ,(if keep 1 m))
        (:commit-n   . ,(if keep 0 1))
        (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))
        (:reselect   . t)))))

(defun maf--resolve-target-region (opts)
  "Return the active region's context alist.
The region denotes its target structurally — the covered text is never
parsed. Both endpoints must lie in the same stack entry; clamped into
the entry's formula text, they map into the flat rendering, and the
innermost sub-formula containing both is the container.

A +/- or * chain container snaps the region outward to the run of
terms it touches (a region on an operator glyph alone pulls in both
neighbors). A run that is the whole chain or a single term collapses
to the subexpr target on that node, and a non-chain container resolves
as subexpr on the container itself — the smallest sub-formula defined
by two points, as calc's j a selects. Any other run is synthesized:
:expr is the fold of the covered terms, each keeping its chain sign,
and commit rebuilds the chain with the result as one term in the run's
place (see maf-chain.el).

Binary commands take :arg from the top of the stack and require the
target entry below the top, as with subexpr. Resolving consumes the
gesture: the mark deactivates."
  (maf--with-calc-buffer
    (let* ((beg (region-beginning))
           (end (max (region-beginning) (1- (region-end))))
           (m (calc-locate-cursor-element beg)))
      (unless (> m 0)
        (error "Region must lie within a stack entry"))
      (unless (= m (calc-locate-cursor-element end))
        (error "Region spans multiple stack entries"))
      (calc-prepare-selection m)
      ;; Clamp the endpoints into the entry's formula text: the start
      ;; may sit in the line prefix, the end on the newline or beyond.
      (let* ((text-beg (+ (save-excursion (calc-cursor-stack-index m) (point))
                          calc-selection-cache-offset))
             (text-end (- (save-excursion (calc-cursor-stack-index (1- m))
                                          (point))
                          2))
             (beg (max beg text-beg))
             (end (min end text-end)))
        (when (> beg end)
          (error "Region does not touch the entry's formula"))
        (let* ((ca (maf--comp-pos-cpos beg))
               (cb (maf--comp-pos-cpos end))
               (container (and ca cb (maf--comp-node-at-range ca cb))))
          (unless container
            (error "Region target requires a flat rendering"))
          (prog1
              (pcase (maf--chain-kind container)
                ('nil (maf--resolve-subexpr-context container m opts))
                (kind (maf--resolve-region-run container kind ca cb m opts)))
            (deactivate-mark)))))))

(defun maf--resolve-region-run (container kind ca cb m opts)
  "Context for flat range [CA, CB] inside chain CONTAINER at level M.
Snaps the range outward to the run of KIND-chain terms it touches and
builds the region context — or a subexpr context when the run is the
whole chain or a single term. The split from
`maf--resolve-target-region' is mechanical; see there for semantics."
  (let* ((terms (maf--chain-terms container))
         (spans (mapcar (lambda (term)
                          (pcase (maf--comp-node-span (cdr term))
                            (`(,s ,e ,_ ,_) (cons s e))))
                        terms))
         ;; First term ending after CA, last term starting at or before
         ;; CB: when the range meets any term spans, these bracket
         ;; exactly the touched terms; when it sits wholly in the gap
         ;; around an operator glyph they cross, and min/max below
         ;; brackets the gap — the operator pulls in both neighbors.
         (j1 (cl-position-if (lambda (sp) (and sp (> (cdr sp) ca))) spans))
         (j2 (cl-position-if (lambda (sp) (and sp (<= (car sp) cb))) spans
                             :from-end t)))
    (unless (and j1 j2)
      (error "Region does not touch the entry's formula"))
    (let ((i (min j1 j2))
          (j (max j1 j2))
          (arity (alist-get :arity opts))
          (keep calc-keep-args-flag))
      (cond
       ((and (= i 0) (= j (1- (length terms))))
        (maf--resolve-subexpr-context container m opts))
       ((= i j)
        (maf--resolve-subexpr-context (cdr (nth i terms)) m opts))
       (t
        (when (and (eq arity 'binary) (= m 1))
          (error "Binary commands on a region require the target entry below the top"))
        `((:target     . region)
          ;; The fold of the covered signed terms, encasing stripped for
          ;; the body like every :expr — never re-read, never normalized.
          (:expr       . ,(maf--strip-encasing
                           (maf--chain-fold (cl-subseq terms i (1+ j)))))
          ;; What commit needs to rebuild: the container cons to splice
          ;; at, and the untouched terms on each side of the run.
          (:chain-ref  . ,container)
          (:chain-kind . ,kind)
          (:pre-terms  . ,(cl-subseq terms 0 i))
          (:post-terms . ,(cl-subseq terms (1+ j)))
          (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
          (:m          . ,m)
          (:commit-m   . ,(if keep 1 m))
          (:commit-n   . ,(if keep 0 1))
          (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))
          (:reselect   . nil)))))))

(defun maf--resolve-target-home (opts)
  "Return the home target's context alist."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (keep calc-keep-args-flag))
      `((:target     . home)
        ;; For binary, the lower entry is :expr and the top is :arg, so e.g.
        ;; 3 over 2 subtracts to 3 - 2 (not 2 - 3). Encasing stripped:
        ;; selection machinery (maf-hl included) encases entry atoms in
        ;; place, and the body must see clean values — but the entry is
        ;; not re-normalized, which could re-simplify it.
        (:expr       . ,(maf--strip-encasing
                         (pcase arity
                           ('unary (calc-top 1 'full))
                           ('binary (calc-top 2 'full)))))
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:commit-m   . 1)
        (:commit-n   . ,(if keep 0 (pcase arity ('unary 1) ('binary 2))))
        (:post-pop   . 0)))))

(defun maf--resolve-subexpr-context (encased m opts)
  "Context alist for a subexpr-style target on ENCASED at stack level M.
The shared shape behind the subexpr and region targets: subexpr hands
in the node under point, region the node its endpoints resolved to.
Binary commands require the target entry to be below the top (M > 1);
otherwise the arg would be the entry containing the sub-expression,
which has no coherent commit semantics."
  (let ((arity (alist-get :arity opts))
        (keep calc-keep-args-flag))
    ;; If m=1 and arity=binary then there's nowhere to take the arg from - reject.
    (when (and (eq arity 'binary) (= m 1))
      (error "Binary commands on subexpr require the target entry below the top"))
    `((:target     . subexpr)
      ;; :expr is the clean form for the body — encasing stripped, but
      ;; not re-normalized, which could re-simplify the sub-formula
      ;; under point. :expr-ref is the encased cons commit needs for
      ;; eq-based splicing.
      (:expr       . ,(maf--strip-encasing encased))
      (:expr-ref   . ,encased)
      ;; Non-nil when point sits on a glyph the sub-formula renders
      ;; itself (its operator, comma, function name): the glyph's
      ;; index, used to re-anchor point on the committed node.
      (:point-anchor . ,(maf--comp-node-anchor-index
                         encased (maf--comp-point-cpos)))
      (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
      (:m          . ,m)
      (:commit-m   . ,(if keep 1 m))
      (:commit-n   . ,(if keep 0 1))
      (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))
      (:reselect   . nil))))

(defun maf--resolve-target-subexpr (opts)
  "Return the subexpr target's context alist.
Point is inside an entry's formula text; :expr is the implicit sub-expression
under cursor.

For binary commands, :arg is the top of the stack. Binary commands require the
target entry to be below the top (:m > 1); otherwise the arg would be the
entry containing the sub-expression, which has no coherent commit semantics.
With keep-args off, commit replaces the sub-expression in-place; with
keep-args on, commit pushes the spliced result on top, leaving originals
untouched."
  (maf--with-calc-buffer
    (let ((m (calc-locate-cursor-element (point))))
      (calc-prepare-selection m)
      (maf--resolve-subexpr-context (calc-find-selected-part) m opts))))

(defun maf--resolve-target-equation (opts)
  "Return the equation target's context alist.
The stack entry under point is a relation. The body runs once per side (the
macro binds :expr to :lhs, then to :rhs), and the per-side results are
reassembled into a new relation under :rel-op.

For binary commands, :arg is the top of the stack, shared across both sides.
Binary commands require the relation below the top (:m > 1); otherwise the arg
would be the relation itself. Unlike entry, equation cannot shift the target
down — the target must remain a relation — so it errors instead."
  (maf--with-calc-buffer
    (let* ((arity (alist-get :arity opts))
           (m     (calc-locate-cursor-element (point)))
           (keep  calc-keep-args-flag)
           ;; Encasing stripped: selection machinery (maf-hl included)
           ;; encases entry atoms in place, and the body must see clean
           ;; values — but not re-normalized, which could re-simplify.
           (expr  (maf--strip-encasing (calc-top m 'full))))
      (when (and (eq arity 'binary) (= m 1))
        (error "Binary commands on equation require the relation below the top"))
      `((:target     . equation)
        (:expr       . ,expr)
        (:rel-op     . ,(car expr))
        (:lhs        . ,(nth 1 expr))
        (:rhs        . ,(nth 2 expr))
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:m          . ,m)
        (:commit-m   . ,(if keep 1 m))
        (:commit-n   . ,(if keep 0 1))
        (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))))))

(defun maf--resolve-target-entry (opts)
  "Return the entry target's context alist.
Point is on a stack entry's margin (line-prefix or EOL); :expr is the whole
formula of that entry.

For binary commands, :arg is the top of the stack. With keep-args off, commit
replaces the entry in-place; with keep-args on, commit pushes the result on
top instead, leaving originals untouched.

Ergonomic shift: if point is at the top entry (m=1) and the command is binary,
the top is treated as :arg and the entry below as the target — point doesn't
have to be on the operand whose value will be replaced."
  (maf--with-calc-buffer
    (let ((arity (alist-get :arity opts))
          (m (calc-locate-cursor-element (point)))
          (keep calc-keep-args-flag))
      ;; For binary at the top entry, shift m down: the top becomes the arg
      ;; and the entry below becomes the target.
      (when (and (eq arity 'binary) (= m 1))
        (setq m 2))
      `((:target     . entry)
        ;; Encasing stripped: selection machinery (maf-hl included)
        ;; encases entry atoms in place, and the body must see clean
        ;; values — but not re-normalized, which could re-simplify.
        (:expr       . ,(maf--strip-encasing (calc-top m 'full)))
        (:arg        . ,(pcase arity ('unary nil) ('binary (math-normalize (calc-top 1 'full)))))
        (:commit-m   . ,(if keep 1 m))
        (:commit-n   . ,(if keep 0 1))
        (:post-pop   . ,(if keep 0 (pcase arity ('unary 0) ('binary 1))))))))

(defun maf--resolve-map-relation (context opts)
  "Convert CONTEXT to an equation target when its subject is a relation.
Applies to home, entry, and subexpr targets: whenever the resolved :expr
is itself a relation, the body should run once per side, exactly as it
does when point sits on a relation entry's margin. Commands whose body
consumes the relation whole (solve, mapeq, the relation builders) opt out
with :map -1 in OPTS.

The equation keys are prepended, shadowing :target while keeping the base
target's commit fields — the rebuilt relation replaces whatever the base
target would have replaced."
  (let ((expr (alist-get :expr context)))
    (if (or (eql (alist-get :map opts) -1)
            (not (memq (alist-get :target context) '(home entry subexpr)))
            (not (maf--relation-p expr)))
        context
      (append `((:target . equation)
                (:rel-op . ,(car expr))
                ;; :expr is already clean; keep the sides as they are
                ;; rather than re-normalizing them.
                (:lhs    . ,(nth 1 expr))
                (:rhs    . ,(nth 2 expr)))
              context))))

(defun maf--resolve-context (opts)
  "Inspect point and calc state; return a context descriptor alist.

The returned alist contains:
  - target-specific keys (:target, :expr, :arg) for the matched target
  - all entries from OPTS (e.g. :arity, :prefix), merged in
  - ambient state snapshots (:keep, :point)

Possible :target values, in order of priority:
  region     Active Emacs region; expr is the run of chain terms (or the
             sub-formula) the region covers. May resolve as subexpr.
  selection  Active calc selection; expr is the selected sub-expression.
  home       Point is at or below the . line.
  subexpr    Implicit selection. Point is inside an entry.
  equation   Entry is a relation (=, !=, <, <=, >, >=); body runs once per side.
  entry      Whole stack entry; point is at EOL or in the line-prefix zone.

Whenever the resolved subject (:expr) is itself a relation — the entry at
the margin, the entry at home, the shifted entry target, or the relation
node under point — the context is converted to the equation target so the
body runs once per side. Commands opt out with :map -1 in OPTS, keeping
the whole relation as :expr.

With `:scope entry' in OPTS the sub-formula/selection/region targets are
bypassed entirely: the command always operates on the whole entry at
point (or the top at home). For commands with no sub-formula meaning —
solving an equation, finding a polynomial's roots."
  (maf--with-calc-buffer
    ;; Snapshot point before target resolution: the target functions probe
    ;; calc state and must not perturb what restore later reproduces.
    (let ((point-snapshot (maf--point-snapshot)))
      (append (maf--resolve-map-relation
               (cond
                ;; Whole-entry commands take the entry at point (or the
                ;; top at home) regardless of where point sits within it.
                ((eq (alist-get :scope opts) 'entry)
                 (if (maf--at-home-p)
                     (maf--resolve-target-home opts)
                   (maf--resolve-target-entry opts)))
                ;; The region is the most deliberate gesture there is;
                ;; it outranks even an explicit calc selection.
                ((use-region-p)          (maf--resolve-target-region opts))
                ((maf--sel-any-p)        (maf--resolve-target-selection opts))
                ((maf--at-home-p)        (maf--resolve-target-home opts))
                ((maf--at-subexpr-p)     (maf--resolve-target-subexpr opts))
                ((and (maf--at-equation-p)
                      (not (eql (alist-get :map opts) -1)))
                                         (maf--resolve-target-equation opts))
                ((maf--at-line-margin-p) (maf--resolve-target-entry opts))
                (t (error "Could not resolve target at point")))
               opts)
              ;; Also include options declared in the defcmd body like :arity, :prefix, etc
              opts
              ;; Include some useful properties as well like calc flag states
              `((:keep . ,calc-keep-args-flag)
                (:point . ,point-snapshot))))))

(provide 'maf-resolve)
