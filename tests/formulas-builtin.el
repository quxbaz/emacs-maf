;; The formulas maf ships with (`maf-formulas-builtin'): the properties
;; of real numbers, in the menu whether or not a library of one's own
;; exists. What is checked here is the shipping and the merge — that
;; the entries are well formed, that they reach the menu and calc's
;; variables with `maf-formulas-user' empty, that a formula of the
;; user's sharing a :name wins, and that an identity calc would
;; simplify away reaches the stack intact.
;;
;; Self-contained the way formulas.el is: the user's library emptied
;; for the duration, the file marked already-consulted so nothing on
;; disk is read, and the session's state put back at the end.

(maf-step
  (setq blt--stash (list maf-formulas-user maf-formulas--loaded
                         maf-use-formulas-mode maf-formulas-builtin
                         (gethash "*maf-formulas*" filter-view--sessions))
        maf-formulas--loaded t          ; skip loading maf-formulas-file
        maf-formulas-user nil)          ; the shipped set, alone

  ;; A clean session, its detail pane out of the way.
  (progn
    (remhash "*maf-formulas*" filter-view--sessions)
    (filter-view--session-put "*maf-formulas*" :pane-state nil)
    nil)

  ;; Something ships, and each entry carries the whole plist. Only
  ;; :expr is required by the shape, but a shipped formula reaching the
  ;; menu without a title or a description would be furniture.
  (cl-assert maf-formulas-builtin)
  (cl-assert (seq-every-p
              (lambda (f)
                (seq-every-p (lambda (k) (plist-get f k))
                             '(:name :title :category :expr :doc :vars)))
              maf-formulas-builtin))

  ;; No two share a :name. The name becomes a calc `var-eq-' variable,
  ;; where a collision would quietly shadow one with the other.
  (let ((names (mapcar (lambda (f) (plist-get f :name)) maf-formulas-builtin)))
    (cl-assert (= (length names) (length (delete-dups names)))))

  ;; The categories shipped, each holding formulas. The menu sorts its
  ;; groups by name, so this is also the order they come up in — which
  ;; is why the trig groups name their subject after the dash rather
  ;; than all being "Trigonometry — Identities" run together.
  (cl-assert (equal (sort (delete-dups (mapcar (lambda (f) (plist-get f :category))
                                               maf-formulas-builtin))
                          #'string<)
                    '("Algebra — Absolute value"
                      "Algebra — Exponents"
                      "Algebra — Fractions"
                      "Algebra — Logarithms"
                      "Algebra — Properties of real numbers"
                      "Algebra — Quadratic equations"
                      "Algebra — Radicals"
                      "Geometry — 2D: Coordinate plane"
                      "Geometry — 3D: Cube"
                      "Geometry — 3D: Rectangular Solid"
                      "Trigonometry — Angle sum and difference"
                      "Trigonometry — Double angle"
                      "Trigonometry — Even and odd"
                      "Trigonometry — Half angle"
                      "Trigonometry — Pythagorean identities"
                      "Trigonometry — Reciprocal and quotient")))

  ;; A formula each group promises is in it.
  (cl-assert (seq-every-p
              (lambda (n) (seq-find (lambda (f) (equal (plist-get f :name) n))
                                    maf-formulas-builtin))
              '("commutative-property-of-addition"
                "associative-property-of-addition" "distributive-property"
                "additive-identity" "multiplicative-identity"
                "additive-inverse" "multiplicative-inverse"
                "triangle-inequality" "zero-exponent" "addition-of-fractions"
                "logarithm-of-a-product" "quadratic-formula-first-root"
                "product-of-radicals" "sine-of-a-sum"
                "sine-of-a-double-angle" "cosine-is-even"
                "tangent-of-a-half-angle" "pythagorean-identity"
                "cosecant-as-a-reciprocal" "volume-of-rectangular-solid"
                "distance-formula")))

  ;; `maf-formulas--all' is the shipped set and then the user's, so a
  ;; library of one's own extends the menu rather than replacing it.
  (cl-assert (equal (maf-formulas--all) maf-formulas-builtin))
  (let ((maf-formulas-user '((:name "mine" :title "Mine" :category "Mine"
                              :expr (calcFunc-eq (var x var-x) 1)))))
    (cl-assert (equal (maf-formulas--all)
                      (append maf-formulas-builtin maf-formulas-user))))

  ;; Enabling the module registers a `var-eq-' variable per formula,
  ;; the shipped ones included.
  (maf-use-formulas-mode 1)
  (cl-assert (equal (symbol-value (intern "var-eq-additive-identity"))
                    '(calcFunc-eq (+ (var a var-a) 0) (var a var-a))))

  ;; A formula of the user's sharing a :name registers last and so
  ;; takes the variable — the way one of these is overridden. The
  ;; shipped expression is back once that library is gone.
  (let ((maf-formulas-user '((:name "additive-identity" :title "Mine"
                              :category "Mine"
                              :expr (calcFunc-eq (var q var-q) 9)))))
    (maf-formulas--register-vars)
    (cl-assert (equal (symbol-value (intern "var-eq-additive-identity"))
                      '(calcFunc-eq (var q var-q) 9))))
  (maf-formulas--register-vars)
  (cl-assert (equal (symbol-value (intern "var-eq-additive-identity"))
                    '(calcFunc-eq (+ (var a var-a) 0) (var a var-a))))

  ;; The menu shows the shipped group with no library of one's own.
  (with-current-buffer (apply #'filter-view-setup "*maf-formulas*"
                              (maf-formulas--config))
    (cl-assert (string-match-p "Algebra — Properties of real numbers"
                               (buffer-string)))
    (cl-assert (string-match-p "Additive identity" (buffer-string))))

  ;; RET pushes the identity as written. Calc's own simplifications
  ;; turn `a + 0' into `a', so evaluating `a + 0 = a' collapses it to
  ;; 1 — the push does not evaluate, and the formula reaches the stack
  ;; whole, which is what keeping it in a library is for.
  (with-current-buffer "*maf-formulas*"
    (goto-char (point-min))
    (search-forward "Additive identity")
    (beginning-of-line)
    (cl-letf (((symbol-function 'filter-view-quit) (lambda (&rest _) nil)))
      (filter-view-select)))
  (cl-assert (equal (calc-top 1)
                    '(calcFunc-eq (+ (var a var-a) 0) (var a var-a))))
  (cl-assert (equal (math-format-flat-expr (calc-top 1) 0) "a + 0 = a"))
  (cl-assert (equal (math-format-flat-expr (calc-eval "a + 0 = a" 'raw) 0) "1"))
  (calc-pop (calc-stack-size))

  ;; nil keeps only the user's — dropping the shipped set without
  ;; editing the package.
  (let ((maf-formulas-builtin nil)
        (maf-formulas-user '((:name "mine" :title "Mine" :category "Mine"
                              :expr (calcFunc-eq (var x var-x) 1)))))
    (cl-assert (equal (maf-formulas--all) maf-formulas-user)))

  ;; Restore the session state the test displaced, as formulas.el does:
  ;; turning the mode off unregisters what this run registered, and the
  ;; real library is back in place before it goes on again.
  (progn
    (maf-use-formulas-mode -1)
    (setq maf-formulas-user (nth 0 blt--stash)
          maf-formulas--loaded (nth 1 blt--stash)
          maf-formulas-builtin (nth 3 blt--stash))
    (if (nth 4 blt--stash)
        (puthash "*maf-formulas*" (nth 4 blt--stash) filter-view--sessions)
      (remhash "*maf-formulas*" filter-view--sessions))
    (when (get-buffer "*maf-formulas*") (kill-buffer "*maf-formulas*"))
    (when (nth 2 blt--stash)
      (maf-use-formulas-mode 1))
    :restored))
