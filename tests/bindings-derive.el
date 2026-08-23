;; Profile derivation (maf-bindings--effective-defaults): the vim
;; profile compiles as native's whole set beneath its own motions,
;; and the registry-level merge prunes what an own claim overlaps.

(maf-step
  ;; Registry level: own beats inherited, overlap prunes both ways.
  ;; A two-key own claim drops an inherited command on its first key;
  ;; an own command drops the inherited family under its letter.
  (progn
    (maf-bindings-defprofile 'maf-test-src)
    (maf-bindings-define '(maf-test-src) "q q" #'ignore)
    (maf-bindings-define '(maf-test-src) "z" #'ignore)
    (maf-bindings-define '(maf-test-src) "! !" #'ignore)
    (maf-bindings-defprofile 'maf-test-der :derive 'maf-test-src)
    (maf-bindings-define '(maf-test-der) "q" #'forward-char)
    (maf-bindings-define '(maf-test-der) "z z" #'backward-char)
    nil)
  (cl-assert (equal (maf-bindings--effective-defaults 'maf-test-der)
                    '(("! !" . ignore)
                      ("q" . forward-char) ("z z" . backward-char))))
  ;; A cycle is refused, not looped.
  (progn (maf-bindings-defprofile 'maf-test-src :derive 'maf-test-der) nil)
  (cl-assert (condition-case nil
                 (progn (maf-bindings--effective-defaults 'maf-test-der) nil)
               (error t)))
  (progn (maf-bindings--forget 'maf-test-der)
         (maf-bindings--forget 'maf-test-src)
         nil)

  ;; The vim profile: motions win their keys.
  (maf-bindings-set-profile 'vim)
  (cl-assert (eq (key-binding (kbd "h")) 'backward-char))
  (cl-assert (eq (key-binding (kbd "l")) 'forward-char))
  (cl-assert (eq (key-binding (kbd "j")) 'next-line))
  (cl-assert (eq (key-binding (kbd "k")) 'previous-line))
  (cl-assert (eq (key-binding (kbd "w")) 'maf-forward-noun))
  (cl-assert (eq (key-binding (kbd "b")) 'maf-backward-noun))

  ;; Vim's delete reflex: x runs C-d's command, displacing the
  ;; inherited single-key expand — which moves up a case to X and
  ;; keeps its table key a x. Log-exp cedes X, name-only in vim.
  (cl-assert (eq (key-binding (kbd "x")) 'maf-del))
  (cl-assert (eq (key-binding (kbd "X")) 'mafcmd-expand))
  (cl-assert (eq (key-binding (kbd "a x")) 'mafcmd-expand))

  ;; Native's layout flows through the derivation: table siblings,
  ;; shadowing, and additions alike, with no declaration naming vim.
  (cl-assert (eq (key-binding (kbd "+")) 'mafcmd-add))
  (cl-assert (eq (key-binding (kbd "i")) 'mafcmd-solve-for))
  (cl-assert (eq (key-binding (kbd "C-c C-c")) 'mafcmd-esimplify))
  (cl-assert (eq (key-binding (kbd "M-l")) 'mafcmd-ref-angle))
  (cl-assert (eq (key-binding (kbd "W")) 'mafcmd-sqr))

  ;; The families the motions displace are gone whole, not in part.
  (cl-assert (null (key-binding (kbd "j x"))))
  (cl-assert (null (key-binding (kbd "l l"))))
  (cl-assert (null (key-binding (kbd "k k"))))
  (cl-assert (null (key-binding (kbd "b a"))))

  ;; The custom-letter family rides o in vim, second letters intact,
  ;; mirrored from native's l declarations. The commands it displaces
  ;; from o's case pair trade places one step over: commute on the
  ;; doubled o o, the reciprocal on the capital O commute vacates.
  (cl-assert (eq (key-binding (kbd "o c")) 'mafcmd-collect-fractions))
  (cl-assert (eq (key-binding (kbd "o a")) 'mafcmd-poly-roots))
  (cl-assert (eq (key-binding (kbd "o F")) 'mafcmd-factor-gcd))
  (cl-assert (eq (key-binding (kbd "o o")) 'mafcmd-commute))
  (cl-assert (eq (key-binding (kbd "O")) 'mafcmd-inv))
  ;; Log-exp, whose X went to expand here, rides the family: o e.
  (cl-assert (eq (key-binding (kbd "o e")) 'mafcmd-log-exp))
  ;; The float/frac toggle's single chord, on the family's meta
  ;; letter; the inherited mod-360 cedes it and rides the family
  ;; instead — o w, wrapping the angle into range, native's l w
  ;; through the mirror. M-o is the toggle's only vim home: the
  ;; mirror skips l l.
  (cl-assert (eq (key-binding (kbd "M-o")) 'mafcmd-float-frac))
  (cl-assert (eq (key-binding (kbd "o w")) 'mafcmd-mod-360))
  (cl-assert (null (key-binding (kbd "o l"))))

  ;; The selection/structure family rides its capital in vim, second
  ;; letters intact, mirrored from native's j declarations. It
  ;; displaces native's J whole (the second multiply key — mul keeps
  ;; *); the conjugate rides the custom-letter family on its
  ;; initial: o j. The u prefix is untouched.
  (cl-assert (eq (key-binding (kbd "J i")) 'mafcmd-isolate))
  (cl-assert (null (key-binding (kbd "J x"))))
  (cl-assert (null (key-binding (kbd "J f"))))
  (cl-assert (eq (key-binding (kbd "J D")) 'maf-distribute))
  (cl-assert (eq (key-binding (kbd "J M")) 'maf-merge))
  (cl-assert (eq (key-binding (kbd "J e")) 'maf-jump-equals))
  (cl-assert (eq (key-binding (kbd "J j")) 'mafcmd-raise))
  (cl-assert (eq (key-binding (kbd "J U")) 'mafcmd-unpack))
  (cl-assert (eq (key-binding (kbd "o j")) 'mafcmd-conj))
  (cl-assert (eq (key-binding (kbd "u M")) 'mafcmd-vmean))
  (cl-assert (eq (key-binding (kbd "u c")) 'calc-convert-units))

  ;; Numeric evaluation, homeless since k became a motion, on the
  ;; last weak single letter; complete-square rides the family on
  ;; its own letter.
  (cl-assert (eq (key-binding (kbd "y")) 'mafcmd-evaluate))
  (cl-assert (eq (key-binding (kbd "o s")) 'mafcmd-complete-square))
  (cl-assert (eq (key-binding (kbd "o D")) 'mafcmd-factor-powers))
  ;; The line-edge reflex: $ to the end, bouncing to the entry start.
  (cl-assert (eq (key-binding (kbd "$")) 'maf-end-of-line-bounce))

  ;; Module keys ride their own targeting, not the derivation.
  (cl-assert (eq (key-binding (kbd "M-h")) 'maf-history))

  ;; The other profiles are untouched by vim's derivation.
  (maf-bindings-set-profile 'calc)
  (cl-assert (eq (key-binding (kbd "+")) 'mafcmd-add))
  (cl-assert (eq (key-binding (kbd "x")) 'calc-execute-extended-command))
  (cl-assert (eq (key-binding (kbd "j D")) 'calc-sel-distribute))
  (maf-bindings-set-profile 'native)
  (cl-assert (eq (key-binding (kbd "x")) 'mafcmd-expand))
  (cl-assert (eq (key-binding (kbd "o")) 'mafcmd-inv))
  (cl-assert (eq (key-binding (kbd "O")) 'mafcmd-commute))
  (cl-assert (eq (key-binding (kbd "M-o")) 'mafcmd-mod-360))
  (cl-assert (null (key-binding (kbd "o l"))))
  (cl-assert (eq (key-binding (kbd "l l")) 'mafcmd-float-frac))
  (cl-assert (null (key-binding (kbd "j x"))))
  (cl-assert (eq (key-binding (kbd "j D")) 'maf-distribute))
  (cl-assert (eq (key-binding (kbd "J")) 'mafcmd-mul))
  (cl-assert (eq (key-binding (kbd "l j")) 'mafcmd-conj))
  (cl-assert (eq (key-binding (kbd "y")) 'calc-copy-to-buffer))
  (cl-assert (keymapp (key-binding (kbd "j")))))
