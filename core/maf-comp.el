;; -*- lexical-binding: t; -*-
;;
;; maf-comp.el
;;
;; Flat-rendering coordinates for calc compositions: map formula nodes
;; and point to positions in a rendered stack entry. Calc renders each
;; entry from a composition tree whose `tag' nodes reference the actual
;; formula conses; walking it connects the formula structure to buffer
;; text. Consumers: sub-formula highlighting (maf-hl), anchor-based
;; point restoration (maf-lib), and the landing rules (src/stack.el).
;;
;; All entry points assume `calc-prepare-selection' has run for the
;; entry in question, and handle only flat (single-height) renderings —
;; matrices and Big language mode return nil.

(require 'calc)
(require 'calc-ext)   ; math-comp-sel-cpos and friends are declared here
(require 'calccomp)   ; math-comp-pos, math-comp-is-flat
(require 'calc-sel)   ; calc-prepare-selection, calc-selection-cache-*
(require 'cl-lib)

;; calccomp and calc-sel declare these with valueless defvars, which marks
;; them special only within their own files; redeclare them here so our
;; let-bindings and reads of them are dynamic too.
(defvar math-comp-pos)
(defvar math-comp-sel-tag)
(defvar math-comp-selected)
(defvar math-comp-tagged)
(defvar math-compose-level)
(defvar calc-selection-cache-entry)
(defvar calc-selection-cache-num)
(defvar calc-selection-cache-comp)
(defvar calc-selection-cache-offset)
(defvar calc-selection-true-num)

;; Flat-rendering positions of the matched tag, recorded by
;; `maf--comp-flat-term' and read by `maf--comp-find-bounds', which
;; let-binds them around the walk.
(defvar maf--comp-flat-start)
(defvar maf--comp-flat-end)

;; Upstream calc loses parens in every composition it builds for the
;; selection machinery: the tag/selection branch — the first cond arm of
;; `math-compose-expr' — recurses as (math-compose-expr a prec), dropping
;; the DIV argument. DIV is what brackets a product standing as a
;; denominator (implicit multiplication outranks `/', so precedence never
;; does it), and it is the only paren source the branch loses — PREC rides
;; through. So the tagged composition renders `8 / (3 x^3)' as
;; `8 / 3 x^3', two characters short of the displayed entry, and every
;; consumer of that composition drifts together: cursor→sub-formula
;; resolution (`calc-find-selected-part', hence maf's whole resolve layer)
;; goes off by the missing parens and finds nothing at all in the entry's
;; last columns, and a re-render from the cached composition
;; (`calc-change-current-selection', after any selection rewrite) writes
;; the paren-less text into the buffer until the next refresh.
;;
;; The advice re-runs exactly the dropped-DIV case with DIV passed
;; through, replicating the branch's own bookkeeping: the level increment
;; the bypassed outer call would have made, selection cleared inside the
;; tag, and — when tagging is on — `math-comp-tagged' pointed at A so the
;; inner call falls past the branch into the operator logic, where DIV
;; brackets the product inside the tag. Every other call passes through
;; untouched, so only tagged/selected compositions of denominator
;; products change.
(defun maf--comp-compose-keep-div (orig a prec &optional div)
  "Run `math-compose-expr' ORIG with DIV surviving its tag branch.
A and PREC pass through unchanged; see the comment above."
  (if (and div (eq (car-safe a) '*)
           (or (and (eq a math-comp-selected) a)
               (and math-comp-tagged (not (eq math-comp-tagged a)))))
      (let ((math-compose-level (1+ math-compose-level))
            (math-comp-selected nil)
            (math-comp-tagged (and math-comp-tagged a)))
        (list 'tag a (funcall orig a prec div)))
    (funcall orig a prec div)))

(advice-add 'math-compose-expr :around #'maf--comp-compose-keep-div)

;; The second upstream repair: `calc-prepare-selection' validates its
;; cache by `equal' on the stack entry alone (calc-sel.el), so two
;; entries holding the identical formula are indistinguishable to it —
;; preparing one while the other is cached is a false hit, and
;; `calc-selection-cache-num' (with the offset beside it) keeps naming
;; the other level. Everything reading the cache then works on the
;; wrong entry: maf-hl's whole-entry highlight marks the other line,
;; and stock calc's j s selects there. The entries must both have been
;; prepared once before — the cache fill encases the entry's atoms in
;; place, so a fresh duplicate is unequal until its own first prepare —
;; which a cursor pass over the lines supplies. Requiring the cached
;; *level* to match closes the hole: when the levels differ the cache
;; empties and the original recomputes, which it would have done anyway
;; in every case but the false hit.
(defun maf--comp-prepare-fresh (&optional num)
  "Empty calc's selection cache when NUM names a different stack level.
NUM defaults as `calc-prepare-selection' defaults it, from point."
  (let ((n (max (or num (calc-locate-cursor-element (point))) 1)))
    (when (and calc-selection-cache-entry
               calc-selection-cache-num
               (/= calc-selection-cache-num n))
      (setq calc-selection-cache-entry nil))))

(advice-add 'calc-prepare-selection :before #'maf--comp-prepare-fresh)

;; A composition cached before the advice landed was built without it;
;; empty the cache (`calc-prepare-selection' compares against this) so
;; the next selection recomposes.
(setq calc-selection-cache-entry nil)

(defun maf--comp-flat-term (c)
  "Walk composition C, resolving the tag at `math-comp-sel-cpos'.
Like `math-comp-sel-flat-term', but also records the matched tag's start
and end positions in the flat rendering into `maf--comp-flat-start' and
`maf--comp-flat-end', so locating its text needs no second render pass."
  (cond
   ((not (consp c))
    (setq math-comp-pos (+ math-comp-pos (length c))))
   ((memq (car c) '(set break)))
   ((eq (car c) 'horiz)
    (while (and (setq c (cdr c)) (< math-comp-sel-cpos 1000000))
      (maf--comp-flat-term (car c))))
   ((eq (car c) 'tag)
    (if (<= math-comp-pos math-comp-sel-cpos)
        (let ((start math-comp-pos))
          (maf--comp-flat-term (nth 2 c))
          ;; Point fell inside this tag and no inner tag claimed it first:
          ;; record it, and set cpos to the sentinel so enclosing tags and the
          ;; horiz loop stop looking.
          (when (> math-comp-pos math-comp-sel-cpos)
            (setq math-comp-sel-tag c
                  math-comp-sel-cpos 1000000
                  maf--comp-flat-start start
                  maf--comp-flat-end math-comp-pos)))
      (maf--comp-flat-term (nth 2 c))))
   (t
    (maf--comp-flat-term (nth 2 c)))))

(defun maf--comp-flat-to-pos (fpos toppt)
  "Convert flat-rendering position FPOS to a buffer position, or nil.
TOPPT is the buffer position of the start of the entry's first line. When a
long entry wraps, each continuation line's newline and indentation occupy
buffer positions but not flat positions, so walk line by line rather than
adding a single offset. nil when FPOS runs past the end of the buffer —
a selection cache describing a stack state the buffer no longer shows can
hand in positions with nothing under them, and the walk must fail rather
than spin on the last line."
  (save-excursion
    (goto-char (+ toppt calc-selection-cache-offset))
    (catch 'overrun
      (while (> fpos (- (line-end-position) (point)))
        (setq fpos (- fpos (- (line-end-position) (point))))
        (unless (zerop (forward-line 1))
          (throw 'overrun nil))
        (back-to-indentation))
      (+ (point) fpos))))

(defun maf--comp-point-cpos ()
  "Return point's position in the prepared entry's flat rendering, or nil.
nil when the composition is not flat or point sits left of the formula
text."
  (when (math-comp-is-flat calc-selection-cache-comp)
    (let ((line (line-beginning-position))
          (toppt nil)
          (lcount 0)
          (spaces 0))
      (save-excursion
        (calc-cursor-stack-index calc-selection-cache-num)
        (setq toppt (point))
        (while (< (point) line)
          (forward-line 1)
          (setq spaces (+ spaces (current-indentation))
                lcount (1+ lcount))))
      (when (and (>= (- (current-column) calc-selection-cache-offset) 0)
                 (> calc-selection-true-num 0))
        (- (point) toppt calc-selection-cache-offset spaces lcount)))))

(defun maf--comp-pos-cpos (pos)
  "Return buffer position POS's place in the prepared entry's flat rendering.
`maf--comp-point-cpos' for an arbitrary position instead of point; nil
under the same conditions."
  (save-excursion (goto-char pos) (maf--comp-point-cpos)))

(defun maf--comp-node-at-range (from to)
  "Return the innermost tagged sub-formula covering flat range [FROM, TO].
Both bounds are inclusive flat-rendering positions. The walk is
post-order — children complete before their enclosing tags — so the
first tag found whose span covers the range is the deepest one. nil
when the composition is not flat."
  (when (math-comp-is-flat calc-selection-cache-comp)
    (let ((math-comp-pos 0)
          (best nil))
      (cl-labels
          ((walk (c)
             (cond
              ((not (consp c))
               (setq math-comp-pos (+ math-comp-pos (length c))))
              ((memq (car c) '(set break)))
              ((eq (car c) 'horiz)
               (dolist (sub (cdr c)) (walk sub)))
              ((eq (car c) 'tag)
               (let ((start math-comp-pos))
                 (walk (nth 2 c))
                 (when (and (null best)
                            (<= start from)
                            (< to math-comp-pos))
                   (setq best (nth 1 c)))))
              (t (walk (nth 2 c))))))
        (walk calc-selection-cache-comp))
      best)))

(defun maf--comp-find-bounds ()
  "Return (START . END) buffer bounds of the sub-formula at point, or nil.
Mirrors `calc-find-selected-part', walking the composition prepared by
`calc-prepare-selection'."
  (when-let ((cpos (maf--comp-point-cpos)))
    (let ((toppt (save-excursion
                   (calc-cursor-stack-index calc-selection-cache-num)
                   (point)))
          (math-comp-sel-cpos cpos)
          (math-comp-sel-tag nil)
          (math-comp-pos 0)
          (maf--comp-flat-start nil)
          (maf--comp-flat-end nil))
      (maf--comp-flat-term calc-selection-cache-comp)
      (when maf--comp-flat-start
        (let ((start (maf--comp-flat-to-pos maf--comp-flat-start toppt))
              (end (maf--comp-flat-to-pos maf--comp-flat-end toppt)))
          (when (and start end)
            (cons start end)))))))

(defun maf--comp-node-span (node)
  "Return (START END CHILD-SPANS TEXT) for NODE in the prepared composition.
NODE must be eq to a tagged sub-formula of the prepared entry.
CHILD-SPANS is a list of (START . END) flat spans for NODE's direct
child tags, in order; TEXT is the entry's whole flat rendering. Return
nil when the composition is not flat or NODE has no tag in it."
  (when (math-comp-is-flat calc-selection-cache-comp)
    (let ((math-comp-pos 0)
          (pieces nil)
          start end children)
      (cl-labels
          ((walk (c state)
             (cond
              ((not (consp c))
               (push c pieces)
               (setq math-comp-pos (+ math-comp-pos (length c))))
              ((memq (car c) '(set break)))
              ((eq (car c) 'horiz)
               (dolist (sub (cdr c)) (walk sub state)))
              ((eq (car c) 'tag)
               (cond
                ((eq (nth 1 c) node)
                 (setq start math-comp-pos)
                 (walk (nth 2 c) 'inside)
                 (setq end math-comp-pos))
                ((eq state 'inside)
                 ;; A direct child of NODE: record its span; its own
                 ;; descendants are not direct children, so recurse flat.
                 (let ((cs math-comp-pos))
                   (walk (nth 2 c) nil)
                   (push (cons cs math-comp-pos) children)))
                (t (walk (nth 2 c) state))))
              (t (walk (nth 2 c) state)))))
        (walk calc-selection-cache-comp nil))
      (when start
        (list start end (nreverse children)
              (apply #'concat (nreverse pieces)))))))

(defun maf--comp-node-glyphs (node)
  "Flat positions of NODE's structural glyphs, or nil.
The structural glyphs are the characters NODE renders itself — its
operator with surrounding spaces, function name, commas, parens —
excluding everything covered by a direct child operand. Spaces count:
a juxtaposed product renders its multiplication as nothing but a
space. nil for atoms (no children) and non-flat renderings."
  (pcase (maf--comp-node-span node)
    (`(,start ,end ,children ,_text)
     (when children
       (cl-loop for p from start below end
                unless (cl-some (lambda (c) (and (<= (car c) p)
                                                 (< p (cdr c))))
                                children)
                collect p)))))

(defun maf--comp-node-anchor-index (node cpos)
  "Index of CPOS among NODE's structural glyph positions, or nil.
Non-nil only when point sits on a glyph NODE renders itself — an
operator, comma, function name, or the space of a juxtaposed product —
rather than inside a child operand."
  (when cpos
    (cl-position cpos (maf--comp-node-glyphs node))))

(defun maf--comp-node-anchor-pos (node index)
  "Buffer position of NODE's INDEX-th structural glyph, or nil.
INDEX clamps to the last glyph, so a node that shrank still anchors."
  (let ((glyphs (maf--comp-node-glyphs node)))
    (when glyphs
      (let ((fpos (nth (min index (1- (length glyphs))) glyphs))
            (toppt (save-excursion
                     (calc-cursor-stack-index calc-selection-cache-num)
                     (point))))
        (maf--comp-flat-to-pos fpos toppt)))))

(defun maf--comp-node-start-pos (node)
  "Buffer position of the first glyph of NODE's whole span, or nil.
Where `maf--comp-node-anchor-pos' targets a node's own structural
glyphs — and so returns nil for an atom, which has none — this returns
the start of NODE's rendering, the place to put point to land on the
node itself, atom or not. nil when NODE has no tag in the prepared
composition (identity lost, or a non-flat rendering)."
  (pcase (maf--comp-node-span node)
    (`(,start ,_end ,_children ,_text)
     (let ((toppt (save-excursion
                    (calc-cursor-stack-index calc-selection-cache-num)
                    (point))))
       (maf--comp-flat-to-pos start toppt)))))

(defun maf--comp-node-point-offset (node)
  "Point's character offset into NODE's rendering, or nil when outside it.
The counterpart of `maf--comp-node-offset-pos', read before a rewrite
that moves NODE somewhere else intact. Where
`maf--comp-node-anchor-index' counts only the glyphs NODE renders
itself — and so answers nil for point inside an operand, and for an
atom, which has none — this counts every character of NODE, so any
grip on it has a place to come back to. nil when NODE has no tag in
the prepared composition, or point is outside its span."
  (pcase (maf--comp-node-span node)
    (`(,start ,end ,_children ,_text)
     (let ((cpos (maf--comp-point-cpos)))
       (when (and cpos (<= start cpos) (< cpos end))
         (- cpos start))))))

(defun maf--comp-node-offset-pos (node offset)
  "Buffer position OFFSET characters into NODE's rendering, or nil.
OFFSET clamps into NODE's span, so a node that came back narrower still
lands inside itself. Where `maf--comp-node-start-pos' names NODE's
first character — the placement for a command that put a different
value in the slot — this keeps the character of NODE point already had,
which is what a command that moves NODE itself elsewhere wants: from
the = of p = -4, point is on that = again wherever the element lands.
nil when NODE has no tag in the prepared composition, or the rendering
is not flat."
  (pcase (maf--comp-node-span node)
    (`(,start ,end ,_children ,_text)
     (let ((toppt (save-excursion
                    (calc-cursor-stack-index calc-selection-cache-num)
                    (point))))
       (maf--comp-flat-to-pos
        (+ start (min (max offset 0) (max 0 (1- (- end start)))))
        toppt)))))

(defun maf--comp-own-brackets-p (expr)
  "Non-nil when EXPR's rendering brings its own enclosing brackets.
A vector draws the brackets of `[1, 2]' itself, an interval the mixed
pair of `(0 .. 1]', a complex number the parens of `(1, 2)': those
delimiters are glyphs the node renders, as much its own as an
operator. Every other compound is bare until its context asks for
parens — `x - 5' renders without them at the top of an entry and
gains them from the product in `3 (x - 5)' — so there the parens are
the parent's punctuation rather than the node's own first glyph."
  (memq (car-safe expr) '(vec intv cplx polar)))

(provide 'maf-comp)
