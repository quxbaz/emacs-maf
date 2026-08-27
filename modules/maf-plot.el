;; -*- lexical-binding: t; -*-
;;
;; modules/maf-plot.el
;;
;; Plotting. Four gestures — g g plots the whole entry at point, g l
;; every stack entry in one picture, g i and g I the same with the x
;; range asked for — behind a three-way backend choice:
;;
;;   gnuplot-external  interactive gnuplot window (mouse zoom, readout)
;;   gnuplot-embed     gnuplot-rendered SVG in a split buffer below
;;                     Calc, themed from the live faces
;;   desmos            fire-and-forget browser launch of a local page
;;                     embedding the Desmos calculator (needs network)
;;
;; The gnuplot backends never translate calc syntax: calc samples the
;; expression numerically and gnuplot receives plain data files, so
;; anything calc can evaluate can be plotted. The desmos backend sends
;; the formula instead — Desmos resamples as you zoom, and calc's own
;; LaTeX language (`maf--latex-string') is the entire translation
;; layer. Relation entries plot: gnuplot samples the rhs of y = f(x);
;; desmos receives the equation whole and graphs it natively.
;;
;; The x range is never prompted for (y always autoscales): trig
;; expressions get one period around 0, angle-mode-aware, everything
;; else `maf-plot-default-range'. A prefix argument prompts, and the
;; last prompted range is the next prompt's default. See
;; docs/plans/maf-plot.md for the decisions and the prototype findings
;; this file encodes.
;;
;; With the module off, calc's own g-prefix graphing is untouched. On,
;; the g prefix is this module's to use — g g and g l shadow
;; calc-graph-grid and calc-graph-log-x, and future gestures may take
;; more of it; the stock keys underneath are not a compatibility
;; obligation (decided).

(require 'cl-lib)
(require 'calc)
(require 'calc-yank)               ; calc-locate-cursor-element
(require 'url-util)                ; url-hexify-string
(require 'maf-conf "conf")         ; the `maf' customize group
(require 'maf-math "math")         ; maf--expr-vars
(require 'maf-lib)                 ; maf--relation-p
(require 'maf-stack "stack")       ; maf--latex-string

(declare-function maf-register-module "maf-module")
(declare-function maf-bindings-module-keys "maf-bindings")
(declare-function maf-bindings--refresh "maf-bindings")
(declare-function math-evaluate-expr "calc-ext" (x))
(declare-function math-expr-subst "calc-alg" (expr old new))
(declare-function math-read-number "calc-aent" (s &optional decimal))
(declare-function calc-stack-size "calc" ())

(defconst maf-plot--load-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory this file loads from; `maf-plot.html' sits beside it.")

;;; Options

(defcustom maf-plot-backend 'gnuplot-embed
  "Where a plot appears while the module is on.
`gnuplot-external' opens gnuplot's own interactive window,
`gnuplot-embed' renders SVG into a split buffer below Calc, `desmos'
opens the local Desmos page in a browser. The module menu steps
through these as the maf-plot row's values."
  :type '(choice (const gnuplot-external)
                 (const gnuplot-embed)
                 (const desmos))
  :group 'maf)

(defcustom maf-plot-gnuplot-program "gnuplot"
  "The gnuplot executable both gnuplot backends run."
  :type 'string
  :group 'maf)

(defcustom maf-plot-default-range '(-10.0 . 10.0)
  "The x range a non-trig expression is plotted over.
Trig expressions ignore this for one period around 0 in the current
angle mode. A prefix argument on either plot command overrides both."
  :type '(cons number number)
  :group 'maf)

(defcustom maf-plot-samples 240
  "Sample points per curve on the gnuplot backends."
  :type 'natnum
  :group 'maf)

(defcustom maf-plot-curve-faces
  '(font-lock-function-name-face font-lock-keyword-face
    font-lock-string-face font-lock-constant-face
    font-lock-type-face font-lock-builtin-face)
  "Faces whose foregrounds color the curves, in order, cycling.
Read at render time, so the plot follows the live theme."
  :type '(repeat face)
  :group 'maf)

(defcustom maf-plot-browser nil
  "Browser program the desmos backend launches, or nil.
Nil falls back to `browse-url-generic-program'. The URL must reach
the browser binary intact: the xdg-open route silently drops the
fragment of a file:// URL, and the fragment is the whole graph."
  :type '(choice (const :tag "browse-url-generic-program" nil) string)
  :group 'maf)

(defcustom maf-plot-desmos-api-key "dcb31709b452b1cf9dc26972add0fda6"
  "API key the Desmos page loads calculator.js with.
Defaults to Desmos's published demo key, fine for personal use; a
distributed deployment should carry its own (free) key. The key
travels in the URL fragment — the page itself is a fixed asset."
  :type 'string
  :group 'maf)

;;; State

(defvar maf-plot--prompted-range nil
  "The last range given at a prefix-argument prompt, or nil.
The next prompt's default; plain invocations still auto-range.")

(defvar maf-plot--work-directory nil
  "Temp directory holding this session's data files and renders.")

(defvar maf-plot--return-window nil
  "The window focus goes back to when the panel is dismissed, or nil.")

(defun maf-plot--work-file (name)
  "Return the path for NAME in the session's work directory."
  (unless (and maf-plot--work-directory
               (file-directory-p maf-plot--work-directory))
    (setq maf-plot--work-directory (make-temp-file "maf-plot" t)))
  (expand-file-name name maf-plot--work-directory))

;;; Resolving entries into curves

(defun maf-plot--entry-at-point ()
  "Return the whole stack entry at point, or the top entry at home."
  (when (bound-and-true-p maf-edit-mode)
    (user-error "Finish or discard the active edit before plotting"))
  (let ((size (calc-stack-size)))
    (when (zerop size)
      (user-error "Stack is empty"))
    (let ((level (calc-locate-cursor-element (point))))
      (calc-top (if (> level 0) (min level size) 1) 'full))))

(defun maf-plot--entries ()
  "Return all stack entries, display order (top line first)."
  (when (bound-and-true-p maf-edit-mode)
    (user-error "Finish or discard the active edit before plotting"))
  (let ((size (calc-stack-size)))
    (when (zerop size)
      (user-error "Stack is empty"))
    (let (entries)
      (dotimes (level size)
        (push (calc-top (1+ level) 'full) entries))
      entries)))

(defun maf-plot--function-of (entry)
  "Return what ENTRY plots as a function: itself, or a relation's rhs."
  (if (maf--relation-p entry) (nth 2 entry) entry))

(defun maf-plot--curve-exprs (entry)
  "Return ENTRY's curves as (EXPR . LABEL) pairs.
Most entries are one curve. A vector entry is a curve set — one curve
per element, each labeled by the element — so a subset of the stack
worth plotting together can be built with calc's own grouping and
replotted as one thing. Relations contribute their rhs either way."
  (if (eq (car-safe entry) 'vec)
      (progn
        (unless (cdr entry)
          (user-error "Nothing to plot in an empty vector"))
        (mapcar (lambda (element)
                  (cons (maf-plot--function-of element)
                        (maf-plot--label element)))
                (cdr entry)))
    (list (cons (maf-plot--function-of entry)
                (maf-plot--label entry)))))

(defun maf-plot--desmos-expressions (entries)
  "Flatten ENTRIES for desmos: a vector entry contributes per element.
Relations stay whole — Desmos graphs equations natively."
  (mapcan (lambda (entry)
            (if (eq (car-safe entry) 'vec)
                (copy-sequence (cdr entry))
              (list entry)))
          entries))

(defun maf-plot--variable (expr)
  "Return the var node EXPR is sampled over, or nil for a constant.
Signals for an expression in two or more variables — a curve needs
one axis."
  (let ((vars (cl-delete-duplicates (maf--expr-vars expr) :test #'equal)))
    (when (cdr vars)
      (user-error "Cannot plot in %d variables: %s"
                  (length vars)
                  (mapconcat (lambda (v) (symbol-name (nth 1 v))) vars ", ")))
    (car vars)))

(defun maf-plot--label (entry)
  "Return ENTRY formatted flat, for titles and legends.
Double quotes would end gnuplot's quoted string, so they degrade."
  (replace-regexp-in-string
   "\"" "'" (math-format-value entry 1000)))

;;; Ranges

(defconst maf-plot--trig-heads
  '(calcFunc-sin calcFunc-cos calcFunc-tan
    calcFunc-sec calcFunc-csc calcFunc-cot)
  "Function heads that make an expression trig for range purposes.
Inverse and hyperbolic trig take unbounded arguments, so they range
like anything else.")

(defun maf-plot--trig-p (expr)
  "Non-nil when EXPR contains a trig call."
  (or (memq (car-safe expr) maf-plot--trig-heads)
      (and (consp expr) (cl-some #'maf-plot--trig-p (cdr expr)))))

(defun maf-plot--auto-range (exprs)
  "Return (LO . HI) for EXPRS without prompting.
Any trig curve widens the whole plot to one period around 0 in the
current angle mode; otherwise `maf-plot-default-range'."
  (if (cl-some #'maf-plot--trig-p exprs)
      (if (eq calc-angle-mode 'deg)
          '(-360.0 . 360.0)
        (cons (- (* 2 float-pi)) (* 2 float-pi)))
    (cons (float (car maf-plot-default-range))
          (float (cdr maf-plot-default-range)))))

(defun maf-plot--parse-range (input)
  "Return (LO . HI) read from range INPUT.
\"lo:hi\"; \":hi\" for 0:hi; a single number N for -N:N."
  (let ((range
         (cond
          ((string-match
            "\\`\\(-?[0-9.]+\\)[ \t]*:[ \t]*\\(-?[0-9.]+\\)\\'" input)
           (cons (string-to-number (match-string 1 input))
                 (string-to-number (match-string 2 input))))
          ((string-match "\\`:[ \t]*\\(-?[0-9.]+\\)\\'" input)
           (cons 0 (string-to-number (match-string 1 input))))
          ((string-match "\\`[0-9.]+\\'" input)
           (let ((n (string-to-number input)))
             (cons (- n) n)))
          (t (user-error "Unreadable range: %s" input)))))
    (unless (< (car range) (cdr range))
      (user-error "Empty range: %g:%g" (car range) (cdr range)))
    range))

(defun maf-plot--read-range ()
  "Prompt for an x range and return (LO . HI).
What is given becomes the next prompt's default."
  (let ((default (and maf-plot--prompted-range
                      (format "%g:%g"
                              (car maf-plot--prompted-range)
                              (cdr maf-plot--prompted-range)))))
    (setq maf-plot--prompted-range
          (maf-plot--parse-range
           (string-trim
            (read-string
             (format-prompt "X range (lo:hi, :hi, or n)" default)
             nil nil default))))))

(defun maf-plot--range (exprs arg)
  "Return the x range for EXPRS; prefix ARG means ask."
  (if arg (maf-plot--read-range) (maf-plot--auto-range exprs)))

;;; Sampling (gnuplot backends)

(defun maf-plot--sample (expr range file)
  "Sample EXPR over RANGE into FILE as gnuplot data; return FILE.
Calc evaluates every point — syntax is never translated. Symbolic
mode is bound off: it leaves sin(1.5) unevaluated, rejecting every
sample of a trig curve while plain arithmetic still works, a
per-expression breakage worth ruling out wholesale. Non-real values
(singularities, complex regions) are skipped; the gaps in the data
file render as gaps in the curve, which is right."
  (let* ((calc-symbolic-mode nil)
         (var (maf-plot--variable expr))
         (lo (car range))
         (step (/ (- (cdr range) lo) (float maf-plot-samples)))
         (lines nil))
    (dotimes (i (1+ maf-plot-samples))
      (let* ((x (+ lo (* i step)))
             (v (math-evaluate-expr
                 (if var
                     (math-expr-subst
                      expr var (math-read-number (number-to-string x)))
                   expr))))
        (when (Math-realp v)
          (push (format "%s %s" x (math-format-value (math-float v) 1000))
                lines))))
    (unless lines
      (user-error "No plottable points for %s over %g:%g"
                  (maf-plot--label expr) (car range) (cdr range)))
    (with-temp-file file
      (insert (mapconcat #'identity (nreverse lines) "\n") "\n"))
    file))

;;; gnuplot scripts

(defun maf-plot--face-color (face attribute fallback)
  "Return FACE's ATTRIBUTE as a color string, or FALLBACK."
  (let ((color (face-attribute face attribute nil t)))
    (if (stringp color) color fallback)))

(defun maf-plot--curve-color (index)
  "Return the color for curve INDEX, cycling `maf-plot-curve-faces'."
  (let ((faces maf-plot-curve-faces))
    (if faces
        (maf-plot--face-color (nth (mod index (length faces)) faces)
                              :foreground "steelblue")
      "steelblue")))

(defun maf-plot--plot-clauses (curves)
  "Return the gnuplot plot command for CURVES.
Each curve is (DATA-FILE . LABEL). One curve plots untitled — its
label is the plot title; several get legend entries."
  (let ((single (null (cdr curves)))
        (index -1))
    (concat "plot "
            (mapconcat
             (lambda (curve)
               (setq index (1+ index))
               (format "\"%s\" with lines linewidth 2 linecolor rgb \"%s\" %s"
                       (car curve)
                       (maf-plot--curve-color index)
                       (if single "notitle"
                         (format "title \"%s\"" (cdr curve)))))
             curves ", "))))

(defun maf-plot--theme-lines ()
  "Return the script lines theming a plot from the live faces."
  (let ((fg (maf-plot--face-color 'default :foreground "black"))
        (grid (maf-plot--face-color 'shadow :foreground "gray")))
    (format "set border linecolor rgb \"%s\"
set grid linecolor rgb \"%s\"
set xtics textcolor rgb \"%s\"
set ytics textcolor rgb \"%s\"
set key textcolor rgb \"%s\"
set xzeroaxis linecolor rgb \"%s\"
set title textcolor rgb \"%s\"
" fg grid fg fg fg grid fg)))

(defun maf-plot--run-gnuplot (script)
  "Run SCRIPT through gnuplot synchronously; signal on failure."
  (let ((program (executable-find maf-plot-gnuplot-program)))
    (unless program
      (user-error "gnuplot not found (customize `maf-plot-gnuplot-program')"))
    (let ((file (maf-plot--work-file "plot.gp")))
      (with-temp-file file (insert script))
      (with-temp-buffer
        (let ((status (call-process program nil t nil file)))
          (unless (and (integerp status) (zerop status))
            (error "gnuplot failed (%s): %s" status
                   (string-trim (buffer-string)))))))))

;;; gnuplot-external

(defun maf-plot--show-external (curves title)
  "Plot CURVES in gnuplot's own interactive window.
No terminal line — gnuplot picks its interactive default (qt, x11).
The script pauses until the window closes, so the process holds the
window; the launch itself is fire and forget."
  (let ((program (executable-find maf-plot-gnuplot-program)))
    (unless program
      (user-error "gnuplot not found (customize `maf-plot-gnuplot-program')"))
    (let ((file (maf-plot--work-file "plot-window.gp")))
      (with-temp-file file
        (insert (format "set grid\nset title \"%s\"\n%s%s\npause mouse close\n"
                        title
                        (if (cdr curves) "set key top center\n" "set key off\n")
                        (maf-plot--plot-clauses curves))))
      (start-process "maf-plot-gnuplot" nil program file))))

;;; gnuplot-embed

(defconst maf-plot--buffer "*maf-plot*"
  "Name of the buffer displaying the last embedded plot.")

(defvar maf-plot-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    map)
  "Keymap for `maf-plot-mode'.")

(defun maf-plot-quit ()
  "Dismiss the plot panel and hand focus back."
  (interactive)
  (let ((window (get-buffer-window maf-plot--buffer)))
    (when (window-live-p window)
      (if (window-parent window)
          (delete-window window)
        (quit-window nil window))))
  (when (window-live-p maf-plot--return-window)
    (select-window maf-plot--return-window)))

;; Outside the defvar so a reload applies edits to the map. g closes as
;; well as opens (the gesture is g g), and RET reads as done-here.
(define-key maf-plot-mode-map "q" #'maf-plot-quit)
(define-key maf-plot-mode-map "g" #'maf-plot-quit)
(define-key maf-plot-mode-map (kbd "RET") #'maf-plot-quit)

(define-derived-mode maf-plot-mode special-mode "maf-plot"
  "Major mode for the embedded plot panel."
  (setq-local cursor-type nil)
  (setq-local truncate-lines t)
  (setq-local header-line-format " Plot    q / g / RET closes"))

(defun maf-plot--display (fill)
  "Show the plot panel in an even split below and select it.
FILL is called with the empty, writable panel buffer current. The
same window arithmetic as maf-pretty's preview: `display-buffer'
sizes only windows it creates, so a reused window is evened by hand."
  (let ((buffer (get-buffer-create maf-plot--buffer))
        (height (max window-min-height
                     (/ (window-total-height (selected-window)) 2))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'maf-plot-mode)
        (maf-plot-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (funcall fill)
        (goto-char (point-min))))
    (when-let ((window
                (display-buffer
                 buffer
                 `((display-buffer-reuse-window
                    display-buffer-below-selected)
                   (inhibit-same-window . t)
                   (window-height . ,height)))))
      (set-window-start window (point-min))
      (ignore-errors
        (window-resize window
                       (/ (- (window-total-height)
                             (window-total-height window))
                          2)))
      (unless (eq (selected-window) window)
        (setq maf-plot--return-window (selected-window)))
      (select-window window))))

(defun maf-plot--show-embedded (curves title)
  "Render CURVES to SVG and show them in the plot panel.
Sized to the window the plot will occupy: full width, half height.
On a non-graphic display gnuplot's dumb terminal draws the plot as
text into the same panel instead."
  (if (not (display-graphic-p))
      (maf-plot--show-dumb curves title)
    (let* ((width (max 320 (window-pixel-width)))
           (height (max 200 (/ (window-pixel-height) 2)))
           (bg (maf-plot--face-color 'default :background "white"))
           (svg (maf-plot--work-file "plot.svg")))
      (maf-plot--run-gnuplot
       (format "set terminal svg size %d,%d dynamic background rgb \"%s\" font \"monospace,11\"
set output \"%s\"
%sset title \"%s\"
%s%s\n"
               width height bg svg
               (maf-plot--theme-lines) title
               (if (cdr curves) "set key top center\n" "set key off\n")
               (maf-plot--plot-clauses curves)))
      (let ((image (create-image svg 'svg nil :ascent 'center)))
        ;; The svg path is reused across renders, and Emacs caches
        ;; rendered images by their whole spec: the flush must use this
        ;; exact image, or the cached previous plot keeps displaying.
        (image-flush image)
        (maf-plot--display
         (lambda ()
           (insert-image image title)
           (insert "\n")))))))

(defun maf-plot--show-dumb (curves title)
  "Draw CURVES as text with gnuplot's dumb terminal, for tty frames."
  (let ((out (maf-plot--work-file "plot.txt"))
        (width (max 40 (- (window-width) 2)))
        (height (max 12 (/ (window-height) 2))))
    (maf-plot--run-gnuplot
     (format "set terminal dumb size %d,%d\nset output \"%s\"\nset title \"%s\"\n%s%s\n"
             width height out title
             (if (cdr curves) "set key top center\n" "set key off\n")
             (maf-plot--plot-clauses curves)))
    (maf-plot--display
     (lambda ()
       (insert-file-contents out)))))

;;; desmos

;; Desmos reads LaTeX, but not calc's dialect of it. Calc writes
;; function arguments in braces (\cos{x}, and parens only when the
;; argument needs them structurally) where Desmos requires parens, and
;; absolute value as bare pipes (|x + 1|) where Desmos requires
;; \left|...\right|. The fixes below operate on calc's output grammar,
;; which is known and regular — this is not general LaTeX rewriting.
;; Pipes are the one thing a string pass cannot repair (nested abs
;; makes their pairing ambiguous), so abs is lifted out of the
;; expression before formatting; exp goes to e^x the same way, a form
;; both sides agree on.

(defconst maf-plot--desmos-brace-functions
  '("sin" "cos" "tan" "sec" "csc" "cot"
    "arcsin" "arccos" "arctan"
    "sinh" "cosh" "tanh" "arcsinh" "arccosh" "arctanh"
    "ln")
  "Function names whose brace argument becomes parens for Desmos.
Sub/superscripted forms (\\log_{10}) and structural braces (\\sqrt,
\\frac) are untouched — the match requires the brace directly after
the name.")

(defun maf-plot--desmos-parenthesize (latex)
  "Return LATEX with \\func{arg} rewritten to \\func\\left(arg\\right).
Only for `maf-plot--desmos-brace-functions'; the argument's own
braces are respected by depth."
  (with-temp-buffer
    (insert latex)
    (goto-char (point-min))
    (while (re-search-forward
            (concat "\\\\" (regexp-opt maf-plot--desmos-brace-functions) "{")
            nil t)
      (let ((depth 1))
        (delete-char -1)
        (insert "\\left(")
        (while (and (> depth 0) (not (eobp)))
          (pcase (char-after)
            (?{ (setq depth (1+ depth)))
            (?} (setq depth (1- depth))))
          (if (and (zerop depth) (eq (char-after) ?}))
              (progn (delete-char 1) (insert "\\right)"))
            (forward-char 1)))))
    (buffer-string)))

(defvar maf-plot--desmos-lifted nil
  "Placeholder-to-latex pairs collected while lifting abs nodes.")

(defun maf-plot--desmos-lift (expr)
  "Return EXPR with abs subtrees as placeholder vars, exp as e^x.
Each lifted abs's finished latex is pushed on
`maf-plot--desmos-lifted' under its placeholder's printed name."
  (pcase (car-safe expr)
    ('calcFunc-abs
     (let* ((name (format "mafabs%c" (+ ?a (length maf-plot--desmos-lifted))))
            (placeholder (list 'var (intern name) (intern (concat "var-" name)))))
       (push (cons name
                   (concat "\\left|"
                           (maf-plot--desmos-latex (nth 1 expr))
                           "\\right|"))
             maf-plot--desmos-lifted)
       placeholder))
    ('calcFunc-exp
     (list '^ '(var e var-e) (maf-plot--desmos-lift (nth 1 expr))))
    (_ (if (consp expr)
           (cons (car expr) (mapcar #'maf-plot--desmos-lift (cdr expr)))
         expr))))

(defun maf-plot--desmos-latex (expr)
  "Format EXPR as LaTeX in the dialect Desmos parses."
  (let* ((maf-plot--desmos-lifted nil)
         (latex (maf-plot--desmos-parenthesize
                 (maf--latex-string (maf-plot--desmos-lift expr)))))
    (dolist (lifted maf-plot--desmos-lifted latex)
      (setq latex (string-replace (car lifted) (cdr lifted) latex)))))

(defun maf-plot--desmos-url (entries)
  "Return the local Desmos page URL plotting ENTRIES.
The fragment is the whole handoff: a URI-encoded JSON object with the
entries as calc-formatted LaTeX (relations go whole — Desmos graphs
equations natively), the angle mode, and the API key the page loads
calculator.js with. Nothing is generated per plot; the page is a
fixed asset and the URL is the graph."
  (let ((page (expand-file-name "maf-plot.html" maf-plot--load-directory)))
    (unless (file-exists-p page)
      (error "maf-plot.html missing beside maf-plot.el"))
    (concat "file://" page "#"
            (url-hexify-string
             (json-serialize
              (list :e (vconcat (mapcar #'maf-plot--desmos-latex entries))
                    :d (if (eq calc-angle-mode 'deg) t :false)
                    :k maf-plot-desmos-api-key))))))

(defun maf-plot--show-desmos (expressions)
  "Open the Desmos page on EXPRESSIONS in the configured browser.
The browser binary gets the URL directly: `browse-url' via xdg-open
resolves a file:// URL to a bare path and silently drops the
fragment, opening an empty calculator."
  (let ((program (or maf-plot-browser browse-url-generic-program)))
    (unless program
      (user-error
       "No browser configured: set `maf-plot-browser' (xdg-open would drop the graph)"))
    (start-process "maf-plot-browser" nil program
                   (maf-plot--desmos-url expressions))
    (message "Sent %d %s to Desmos" (length expressions)
             (if (cdr expressions) "expressions" "expression"))))

;;; Commands

(defun maf-plot--gnuplot-curves (specs range)
  "Sample SPECS — (EXPR . LABEL) pairs — into (DATA-FILE . LABEL) curves.
A curve that cannot be sampled — several variables, no real points —
is skipped with a message when others remain, so one odd curve does
not sink a whole plot; a lone curve's error surfaces."
  (let ((index 0)
        (curves nil)
        (skipped nil))
    (dolist (spec specs)
      (setq index (1+ index))
      (condition-case err
          (push (cons (maf-plot--sample
                       (car spec) range
                       (maf-plot--work-file (format "curve-%d.dat" index)))
                      (cdr spec))
                curves)
        (error
         (if (cdr specs)
             (push (error-message-string err) skipped)
           (signal (car err) (cdr err))))))
    (unless curves
      (user-error "Nothing plottable: %s" (string-join skipped "; ")))
    (when skipped
      (message "Skipped %d: %s" (length skipped) (string-join skipped "; ")))
    (nreverse curves)))

(defun maf-plot--dispatch (entries arg)
  "Plot ENTRIES on the configured backend; prefix ARG prompts a range."
  (pcase maf-plot-backend
    ('desmos (maf-plot--show-desmos (maf-plot--desmos-expressions entries)))
    (backend
     (let* ((specs (mapcan #'maf-plot--curve-exprs entries))
            (range (maf-plot--range (mapcar #'car specs) arg))
            (curves (maf-plot--gnuplot-curves specs range))
            (title (cond ((null (cdr curves)) (cdr (car curves)))
                         ((cdr entries) (format "%d curves" (length curves)))
                         (t (maf-plot--label (car entries))))))
       (if (eq backend 'gnuplot-external)
           (maf-plot--show-external curves title)
         (maf-plot--show-embedded curves title))))))

;;;###autoload
(defun maf-plot-entry (arg)
  "Plot the whole stack entry at point.

  2:  y = (x - 2)^2 + 5      g g  =>  the parabola, wherever
  1:  42                               point sits in entry 2

Point anywhere in an entry plots that entry — sub-formula and
selection make no difference — and at home the top entry plots. A
relation plots its right side as the curve on the gnuplot backends
and goes to Desmos whole. A vector entry is a curve set: one curve
per element, so [2 sin(x), cos(x)] overlays both — the way to keep a
replottable subset of the stack. With prefix ARG, prompt for the x
range \(lo:hi, :hi, or n for -n:n) instead of auto-ranging."
  (interactive "P")
  (maf-plot--dispatch (list (maf-plot--entry-at-point)) arg))

;;;###autoload
(defun maf-plot-entry-with-range ()
  "Plot the whole stack entry at point, asking for the x range first.
`maf-plot-entry' with the prompt unconditional rather than behind a
prefix argument — the g i gesture of the legacy config."
  (interactive)
  (maf-plot-entry '(4)))

;;;###autoload
(defun maf-plot-all-with-range ()
  "Plot every stack entry in one picture, asking for the x range first.
`maf-plot-all' with the prompt unconditional — g i's whole-stack
sibling."
  (interactive)
  (maf-plot-all '(4)))

;;;###autoload
(defun maf-plot-all (arg)
  "Plot every stack entry in one picture.

  2:  2 sin(x)     g l  =>  both curves overlaid, shared x
  1:  cos(x)                 range, a legend naming each

On the gnuplot backends the curves share one x range and one y axis —
a mismatched-scale curve is honestly squashed rather than silently
moved to its own axis — and entries that cannot be sampled are
skipped with a message. Desmos receives every entry and scales
interactively. With prefix ARG, prompt for the x range."
  (interactive "P")
  (maf-plot--dispatch (maf-plot--entries) arg))

;;; Module

(defun maf-plot--engage (backend)
  "Set BACKEND and turn the module on; the dial's setter."
  (setq maf-plot-backend backend)
  (maf-use-plot-mode 1))

(define-minor-mode maf-use-plot-mode
  "Make maf's plotting available on the g prefix in Calc.

g g plots the whole entry at point; g l plots every stack entry in
one picture; g i and g I are the same with the x range asked for. Where the plot appears
is `maf-plot-backend': gnuplot's
own interactive window, an SVG panel split below Calc, or the Desmos
calculator in a browser. Off, calc's stock g-prefix graphing is
untouched."
  :global t
  :group 'maf
  ;; Module key claims compile in only while the mode is on; the
  ;; toggle is the recompile trigger.
  (maf-bindings--refresh))

(when (require 'maf-bindings nil t)
  (maf-bindings-module-keys 'maf-plot 'maf-use-plot-mode
    '(((native) "g g" maf-plot-entry)
      ((native) "g l" maf-plot-all)
      ((native) "g i" maf-plot-entry-with-range)
      ((native) "g I" maf-plot-all-with-range)
      ((vim) "g g" maf-plot-entry)
      ((vim) "g l" maf-plot-all)
      ((vim) "g i" maf-plot-entry-with-range)
      ((vim) "g I" maf-plot-all-with-range))))

(when (require 'maf-module nil t)
  (maf-register-module 'maf-plot #'maf-use-plot-mode
                       "Plot stack entries: gnuplot window, embedded SVG, or Desmos.

g g plots the whole entry at point, g l the whole stack in one
picture; g i and g I ask for the x range first. The row's value picks the
surface: an interactive gnuplot
window, an SVG panel split below Calc themed from the live faces, or
a fire-and-forget Desmos page in the browser. Trig curves auto-range
one period in the current angle mode; a prefix argument asks for the
range. Off, calc's own g-prefix graphing is untouched."
                       "g g / g l / g i / g I" "Plotting"
                       (lambda ()
                         (list :values
                               '((off "off" (maf-use-plot-mode -1))
                                 (gnuplot-external "ext"
                                  (maf-plot--engage 'gnuplot-external))
                                 (gnuplot-embed "embed"
                                  (maf-plot--engage 'gnuplot-embed))
                                 (desmos "desmos"
                                  (maf-plot--engage 'desmos)))
                               ;; Reads live state, so the default is
                               ;; stated rather than derived (see
                               ;; `dial--default-value').
                               :current (lambda (_raw)
                                          (if maf-use-plot-mode
                                              maf-plot-backend
                                            'off))
                               :default 'off))))

(provide 'maf-plot)
