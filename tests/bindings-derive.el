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

  ;; Native's layout flows through the derivation: table siblings,
  ;; shadowing, and additions alike, with no declaration naming vim.
  (cl-assert (eq (key-binding (kbd "+")) 'mafcmd-add))
  (cl-assert (eq (key-binding (kbd "x")) 'mafcmd-expand))
  (cl-assert (eq (key-binding (kbd "i")) 'mafcmd-solve-for))
  (cl-assert (eq (key-binding (kbd "C-c C-c")) 'mafcmd-esimplify))
  (cl-assert (eq (key-binding (kbd "M-l")) 'mafcmd-ref-angle))
  (cl-assert (eq (key-binding (kbd "W")) 'mafcmd-sqr))

  ;; The families the motions displace are gone whole, not in part.
  (cl-assert (null (key-binding (kbd "j x"))))
  (cl-assert (null (key-binding (kbd "l l"))))
  (cl-assert (null (key-binding (kbd "k k"))))
  (cl-assert (null (key-binding (kbd "b a"))))

  ;; Module keys ride their own targeting, not the derivation.
  (cl-assert (eq (key-binding (kbd "M-h")) 'maf-timeline))

  ;; The other profiles are untouched by vim's derivation.
  (maf-bindings-set-profile 'calc)
  (cl-assert (eq (key-binding (kbd "+")) 'mafcmd-add))
  (cl-assert (eq (key-binding (kbd "x")) 'calc-execute-extended-command))
  (cl-assert (eq (key-binding (kbd "j D")) 'calc-sel-distribute))
  (maf-bindings-set-profile 'native)
  (cl-assert (eq (key-binding (kbd "l l")) 'mafcmd-float-frac))
  (cl-assert (eq (key-binding (kbd "j x")) 'maf-distribute))
  (cl-assert (keymapp (key-binding (kbd "j")))))
