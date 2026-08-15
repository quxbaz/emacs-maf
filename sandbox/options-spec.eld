((open :buffer
       " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"
       :header "     Group Option Value " :at
       (:line 3 :column 11 :text
              " Numbers   Angle measure      degrees  radians  HMS")
       :faces
       ((1 " " ((:background . "#1c2733") (:extend . t)))
        (1 "TAB"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " select   " ((:background . "#1c2733") (:extend . t)))
        (1 "RET"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " set   " ((:background . "#1c2733") (:extend . t)))
        (1 "d"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " reset   " ((:background . "#1c2733") (:extend . t)))
        (1 "c"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " changed   " ((:background . "#1c2733") (:extend . t)))
        (1 "K"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " calc keys   " ((:background . "#1c2733") (:extend . t)))
        (1 "S"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " save   " ((:background . "#1c2733") (:extend . t)))
        (1 "M-n"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 "/" ((:background . "#1c2733") (:extend . t)))
        (1 "M-p"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " group   " ((:background . "#1c2733") (:extend . t)))
        (1 "g"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " refresh   " ((:background . "#1c2733") (:extend . t)))
        (1 "q"
           ((:foreground . "#00bcff") (:background . "#1c2733") (:weight . bold)
            (:extend . t)))
        (1 " quit   " ((:background . "#1c2733") (:extend . t)))
        (1 "underlined"
           ((:foreground . "#989898") (:background . "#1c2733")
            (:underline . "#989898") (:extend . t)))
        (1 " = default"
           ((:foreground . "#989898") (:background . "#1c2733") (:extend . t)))
        (1 "\n" ((:background . "#1c2733") (:extend . t)))
        (3 "degrees" ((:foreground . "white") (:background . "#553280")))
        (3 "radians" ((:foreground . "#989898")))
        (3 "HMS" ((:foreground . "#989898")))
        (4 "12" ((:foreground . "white") (:background . "#553280")))
        (5 "on" ((:foreground . "#989898")))
        (5 "off" ((:foreground . "white") (:background . "#553280")))
        (6 "on" ((:foreground . "#989898")))
        (6 "off" ((:foreground . "white") (:background . "#553280")))
        (7 "on" ((:foreground . "#989898")))
        (7 "off" ((:foreground . "white") (:background . "#553280")))
        (8 "rectangular" ((:foreground . "white") (:background . "#553280")))
        (8 "polar" ((:foreground . "#989898")))
        (10 "none" ((:foreground . "#989898")))
        (10 "numeric" ((:foreground . "#989898")))
        (10 "basic" ((:foreground . "#989898")))
        (10 "binary" ((:foreground . "#989898")))
        (10 "algebraic" ((:foreground . "white") (:background . "#553280")))
        (10 "extended" ((:foreground . "#989898")))
        (10 "units" ((:foreground . "#989898")))
        (11 "off" ((:foreground . "white") (:background . "#553280")))
        (11 "partial" ((:foreground . "#989898")))
        (11 "incomplete" ((:foreground . "#989898")))
        (11 "total" ((:foreground . "#989898")))
        (12 "unknown" ((:foreground . "white") (:background . "#553280")))
        (12 "matrix" ((:foreground . "#989898")))
        (12 "square matrix" ((:foreground . "#989898")))
        (12 "scalar" ((:foreground . "#989898")))
        (13 "on" ((:foreground . "white") (:background . "#553280")))
        (13 "off" ((:foreground . "#989898")))
        (15 "decimal" ((:foreground . "white") (:background . "#553280")))
        (15 "binary" ((:foreground . "#989898")))
        (15 "octal" ((:foreground . "#989898")))
        (15 "hexadecimal" ((:foreground . "#989898")))
        (16 "normal" ((:foreground . "white") (:background . "#553280")))
        (16 "fixed point" ((:foreground . "#989898")))
        (16 "scientific" ((:foreground . "#989898")))
        (16 "engineering" ((:foreground . "#989898")))
        (17 "on" ((:foreground . "#989898")))
        (17 "off" ((:foreground . "white") (:background . "#553280")))
        (18 "on" ((:foreground . "#989898")))
        (18 "off" ((:foreground . "white") (:background . "#553280")))
        (19 "on" ((:foreground . "white") (:background . "#553280")))
        (19 "off" ((:foreground . "#989898")))
        (20 "on" ((:foreground . "white") (:background . "#553280")))
        (20 "off" ((:foreground . "#989898")))
        (21 "left" ((:foreground . "white") (:background . "#553280")))
        (21 "center" ((:foreground . "#989898")))
        (21 "right" ((:foreground . "#989898")))
        (22 "." ((:foreground . "white") (:background . "#553280")))
        (23 "on" ((:foreground . "#989898")))
        (23 "off" ((:foreground . "white") (:background . "#553280")))
        (24 "on" ((:foreground . "#989898")))
        (24 "off" ((:foreground . "white") (:background . "#553280")))
        (25 "normal" ((:foreground . "white") (:background . "#553280")))
        (25 "flat" ((:foreground . "#989898")))
        (25 "big" ((:foreground . "#989898")))
        (25 "unformatted" ((:foreground . "#989898")))
        (25 "C" ((:foreground . "#989898")))
        (25 "Pascal" ((:foreground . "#989898")))
        (25 "FORTRAN" ((:foreground . "#989898")))
        (25 "TeX" ((:foreground . "#989898")))
        (25 "LaTeX" ((:foreground . "#989898")))
        (25 "eqn" ((:foreground . "#989898")))
        (25 "Yacas" ((:foreground . "#989898")))
        (25 "Maxima" ((:foreground . "#989898")))
        (25 "Giac" ((:foreground . "#989898")))
        (25 "Mathematica" ((:foreground . "#989898")))
        (25 "Maple" ((:foreground . "#989898")))
        (27 "(x,y)" ((:foreground . "white") (:background . "#553280")))
        (27 "x+yi" ((:foreground . "#989898")))
        (27 "x+yj" ((:foreground . "#989898")))
        (28 ":" ((:foreground . "white") (:background . "#553280")))
        (29 "%s@ %s' %s\"" ((:foreground . "white") (:background . "#553280")))
        (30 "H:mmCSSpp Www Mmm D, YYYY"
            ((:foreground . "white") (:background . "#553280")))
        (31 "," ((:foreground . "white") (:background . "#553280")))
        (32 "none" ((:foreground . "white") (:background . "#553280")))
        (33 "none" ((:foreground . "white") (:background . "#553280")))
        (35 "[ ]" ((:foreground . "white") (:background . "#553280")))
        (35 "{ }" ((:foreground . "#989898")))
        (35 "( )" ((:foreground . "#989898")))
        (35 "none" ((:foreground . "#989898")))
        (36 "on" ((:foreground . "white") (:background . "#553280")))
        (36 "off" ((:foreground . "#989898")))
        (37 "on" ((:foreground . "white") (:background . "#553280")))
        (37 "off" ((:foreground . "#989898")))
        (38 "on" ((:foreground . "#989898")))
        (38 "off" ((:foreground . "white") (:background . "#553280")))
        (39 "on" ((:foreground . "white") (:background . "#553280")))
        (39 "off" ((:foreground . "#989898")))
        (40 "left" ((:foreground . "#989898")))
        (40 "center" ((:foreground . "white") (:background . "#553280")))
        (40 "right" ((:foreground . "#989898")))
        (41 "R O" ((:foreground . "white") (:background . "#553280")))
        (43 "8" ((:foreground . "#989898")))
        (43 "16" ((:foreground . "#989898")))
        (43 "32" ((:foreground . "white") (:background . "#553280")))
        (43 "64" ((:foreground . "#989898")))
        (44 "on" ((:foreground . "#989898")))
        (44 "off" ((:foreground . "white") (:background . "#553280")))
        (46 "on" ((:foreground . "white") (:background . "#553280")))
        (46 "off" ((:foreground . "#989898")))
        (47 "on" ((:foreground . "white") (:background . "#553280")))
        (47 "off" ((:foreground . "#989898")))
        (49 "off" ((:foreground . "#989898")))
        (49 "brief" ((:foreground . "#989898")))
        (49 "detailed" ((:foreground . "white") (:background . "#553280")))
        (50 "never" ((:foreground . "#989898")))
        (50 "sometimes" ((:foreground . "white") (:background . "#553280")))
        (50 "always" ((:foreground . "#989898")))
        (51 "on" ((:foreground . "white") (:background . "#553280")))
        (51 "off" ((:foreground . "#989898")))
        (52 "on" ((:foreground . "white") (:background . "#553280")))
        (52 "off" ((:foreground . "#989898")))
        (53 "7" ((:foreground . "white") (:background . "#553280")))
        (54 "on" ((:foreground . "#989898")))
        (54 "off" ((:foreground . "white") (:background . "#553280")))
        (55 "on" ((:foreground . "#989898")))
        (55 "off" ((:foreground . "white") (:background . "#553280")))
        (56 "on" ((:foreground . "#989898")))
        (56 "off" ((:foreground . "white") (:background . "#553280")))
        (57 "nowhere" ((:foreground . "#989898")))
        (57 "local" ((:foreground . "white") (:background . "#553280")))
        (57 "edit" ((:foreground . "#989898")))
        (57 "perm" ((:foreground . "#989898")))
        (57 "global" ((:foreground . "#989898")))
        (57 "settings" ((:foreground . "#989898")))))
 (bindings ("TAB" . maf-options-next-value)
           ("<backtab>" . maf-options-previous-value) ("SPC" . maf-options-set)
           ("RET" . maf-options-set) ("d" . maf-options-reset)
           ("c" . maf-options-toggle-changed-only)
           ("K" . maf-options-toggle-keys) ("S" . maf-options-save)
           ("g" . maf-options-refresh) ("l" . maf-options-next-value)
           ("h" . maf-options-previous-value) ("j" . maf-options-next-line)
           ("k" . maf-options-previous-line) ("n" . maf-options-next-line)
           ("p" . maf-options-previous-line) ("M-n" . maf-options-next-group)
           ("M-p" . maf-options-previous-group) ("q" . quit-window))
 (motion
  (:key "n" :messages ("Significant digits kept in floating-point results.")
        :error nil :at
        (:line 4 :column 11 :text "           Precision          12"))
  (:key "n" :messages
        ("Leave integer quotients as fractions rather than floats.") :error nil
        :at (:line 5 :column 11 :text "           Fraction mode      on  off"))
  (:key "j" :messages ("Defer inexact results like sqrt(2) in symbolic form.")
        :error nil :at
        (:line 6 :column 11 :text "           Symbolic mode      on  off"))
  (:key "k" :messages
        ("Leave integer quotients as fractions rather than floats.") :error nil
        :at (:line 5 :column 11 :text "           Fraction mode      on  off"))
  (:key "p" :messages ("Significant digits kept in floating-point results.")
        :error nil :at
        (:line 4 :column 11 :text "           Precision          12"))
  (:key "p" :messages ("Units trigonometric functions read and produce.") :error
        nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS"))
  (:key "p" :messages ("Units trigonometric functions read and produce.") :error
        nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS"))
  (:key "M-n" :messages ("How far results are simplified automatically.") :error
        nil :at
        (:line 10 :column 11 :text
               " Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units"))
  (:key "M-n" :messages ("Base numbers are displayed in.") :error nil :at
        (:line 15 :column 11 :text
               " Display   Radix              decimal  binary  octal  hexadecimal"))
  (:key "M-p" :messages ("How far results are simplified automatically.") :error
        nil :at
        (:line 10 :column 11 :text
               " Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units"))
  (:key "M-p" :messages ("Units trigonometric functions read and produce.")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS"))
  (:key "M-p" :messages nil :error "No previous group" :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")))
 (step-values
  (:key "TAB" :messages ("Angles measured in radians" "Angle measure: radians")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle rad :row
                ((3 "degrees"
                    ((:foreground . "#989898") (:underline . "#989898")))
                 (3 "radians"
                    ((:foreground . "white") (:background . "#553280")))
                 (3 "HMS" ((:foreground . "#989898"))))))
  (:key "TAB" :messages
        ("Angles measured in degrees-minutes-seconds" "Angle measure: HMS")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle hms :row
                ((3 "degrees"
                    ((:foreground . "#989898") (:underline . "#989898")))
                 (3 "radians" ((:foreground . "#989898")))
                 (3 "HMS" ((:foreground . "white") (:background . "#553280"))))))
  (:key "TAB" :messages ("Angles measured in degrees" "Angle measure: degrees")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle deg :row
                ((3 "degrees"
                    ((:foreground . "white") (:background . "#553280")))
                 (3 "radians" ((:foreground . "#989898")))
                 (3 "HMS" ((:foreground . "#989898"))))))
  (:key "<backtab>" :messages
        ("Angles measured in degrees-minutes-seconds" "Angle measure: HMS")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle hms :row
                ((3 "degrees"
                    ((:foreground . "#989898") (:underline . "#989898")))
                 (3 "radians" ((:foreground . "#989898")))
                 (3 "HMS" ((:foreground . "white") (:background . "#553280"))))))
  (:key "<backtab>" :messages
        ("Angles measured in radians" "Angle measure: radians") :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle rad :row
                ((3 "degrees"
                    ((:foreground . "#989898") (:underline . "#989898")))
                 (3 "radians"
                    ((:foreground . "white") (:background . "#553280")))
                 (3 "HMS" ((:foreground . "#989898"))))))
  (:key "<backtab>" :messages
        ("Angles measured in degrees" "Angle measure: degrees") :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle deg :row
                ((3 "degrees"
                    ((:foreground . "white") (:background . "#553280")))
                 (3 "radians" ((:foreground . "#989898")))
                 (3 "HMS" ((:foreground . "#989898")))))))
 (no-fixed-values
  (:key "n" :messages ("Significant digits kept in floating-point results.")
        :error nil :at
        (:line 4 :column 11 :text "           Precision          12"))
  (:key "TAB" :messages nil :error
        "Precision takes no fixed set of values — RET prompts for one" :at
        (:line 4 :column 11 :text "           Precision          12")))
 (pending
  (:key "M-n" :messages ("How far results are simplified automatically.") :error
        nil :at
        (:line 10 :column 11 :text
               " Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units")
        :extra
        (:float (float 0) :row
                ((10 "none" ((:foreground . "#989898")))
                 (10 "numeric" ((:foreground . "#989898")))
                 (10 "basic" ((:foreground . "#989898")))
                 (10 "binary" ((:foreground . "#989898")))
                 (10 "algebraic"
                     ((:foreground . "white") (:background . "#553280")))
                 (10 "extended" ((:foreground . "#989898")))
                 (10 "units" ((:foreground . "#989898"))))))
  (:key "M-n" :messages ("Base numbers are displayed in.") :error nil :at
        (:line 15 :column 11 :text
               " Display   Radix              decimal  binary  octal  hexadecimal")
        :extra
        (:float (float 0) :row
                ((15 "decimal"
                     ((:foreground . "white") (:background . "#553280")))
                 (15 "binary" ((:foreground . "#989898")))
                 (15 "octal" ((:foreground . "#989898")))
                 (15 "hexadecimal" ((:foreground . "#989898"))))))
  (:key "n" :messages ("Notation floating-point numbers print in.") :error nil
        :at
        (:line 16 :column 11 :text
               "           Float format       normal  fixed point  scientific  engineering")
        :extra
        (:float (float 0) :row
                ((16 "normal"
                     ((:foreground . "white") (:background . "#553280")))
                 (16 "fixed point" ((:foreground . "#989898")))
                 (16 "scientific" ((:foreground . "#989898")))
                 (16 "engineering" ((:foreground . "#989898"))))))
  (:key "TAB" :messages ("fixed point needs a value — RET to enter it") :error
        nil :at
        (:line 16 :column 11 :text
               "           Float format       normal  [fixed point]  scientific  engineering")
        :extra
        (:float (float 0) :row
                ((16 "normal"
                     ((:foreground . "white") (:background . "#553280")))
                 (16 "[fixed point]"
                     ((:foreground . "#989898") (:weight . bold)
                      (:box :line-width -1)))
                 (16 "scientific" ((:foreground . "#989898")))
                 (16 "engineering" ((:foreground . "#989898"))))))
  (:key "TAB" :messages
        ("Displaying floats in scientific notation" "Float format: scientific")
        :error nil :at
        (:line 16 :column 11 :text
               "           Float format       normal  fixed point  scientific  engineering")
        :extra
        (:float (sci 0) :row
                ((16 "normal"
                     ((:foreground . "#989898") (:underline . "#989898")))
                 (16 "fixed point" ((:foreground . "#989898")))
                 (16 "scientific"
                     ((:foreground . "white") (:background . "#553280")))
                 (16 "engineering" ((:foreground . "#989898"))))))
  (:key "d" :messages
        ("Displaying floating-point numbers normally" "Float format: normal")
        :error nil :at
        (:line 16 :column 11 :text
               "           Float format       normal  fixed point  scientific  engineering")
        :extra
        (:float (float 0) :row
                ((16 "normal"
                     ((:foreground . "white") (:background . "#553280")))
                 (16 "fixed point" ((:foreground . "#989898")))
                 (16 "scientific" ((:foreground . "#989898")))
                 (16 "engineering" ((:foreground . "#989898")))))))
 (changed-only
  (:key "M-p" :messages ("Base numbers are displayed in.") :error nil :at
        (:line 15 :column 11 :text
               " Display   Radix              decimal  binary  octal  hexadecimal")
        :extra
        (:angle deg :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"))
  (:key "M-p" :messages ("How far results are simplified automatically.") :error
        nil :at
        (:line 10 :column 11 :text
               " Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units")
        :extra
        (:angle deg :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"))
  (:key "M-p" :messages ("Units trigonometric functions read and produce.")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle deg :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"))
  (:key "TAB" :messages ("Angles measured in radians" "Angle measure: radians")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle rad :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"))
  (:key "c" :messages ("Showing changed settings") :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle rad :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n"))
  (:key "c" :messages ("Showing all settings") :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle rad :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"))
  (:key "d" :messages ("Angles measured in degrees" "Angle measure: degrees")
        :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:angle deg :buffer
                " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n")))
 (keys-column
  (:key "K" :messages nil :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      m d/r/h              degrees  radians  HMS")
        :extra
        (:header "     Group Option Calc key Value " :buffer
                 " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      m d/r/h              degrees  radians  HMS\n           Precision          p                    12\n           Fraction mode      m f                  on  off\n           Symbolic mode      m s                  on  off\n           Infinite mode      m i                  on  off\n           Complex form       m p                  rectangular  polar\n                                                   \n Algebra   Simplification     m O/N/I/B/A/E/U      none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    m a, m t             off  partial  incomplete  total\n           Matrix mode        m v                  unknown  matrix  square matrix  scalar\n           Auto-recompute     m C                  on  off\n                                                   \n Display   Radix              d 0/2/8/6, d r       decimal  binary  octal  hexadecimal\n           Float format       d n/f/s/e            normal  fixed point  scientific  engineering\n           Digit grouping     d g                  on  off\n           Leading zeros      d z                  on  off\n           Line numbers       d l                  on  off\n           Line breaking      d b                  on  off\n           Justification      d </=/>              left  center  right\n           Decimal point      d .                  .\n           Strings            d \"                  on  off\n           Raw display        d '                  on  off\n           Language           d N/B/C/… (15 keys)  normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                                                   \n Formats   Complex numbers    d c/i/j              (x,y)  x+yi  x+yj\n           Fractions          d o                  :\n           HMS                d h                  %s@ %s' %s\"\n           Dates              d d                  H:mmCSSpp Www Mmm D, YYYY\n           Group separator    d ,                  ,\n           Left label         d {                  none\n           Right label        d }                  none\n                                                   \n Vectors   Vector brackets    v [/{/(              [ ]  { }  ( )  none\n           Vector commas      v ,                  on  off\n           Long vectors       v .                  on  off\n           One per line       v /                  on  off\n           Trail vectors                           on  off\n           Matrix columns     v </=/>              left  center  right\n           Matrix brackets    v ]                  R O\n                                                   \n Binary    Word size          b w                  8  16  32  64\n           Two's complement                        on  off\n                                                   \n Selection Show selection     j d                  on  off\n           Associative                             on  off\n                                                   \n Session   Working message    m w                  off  brief  detailed\n           Explain results    d w                  never  sometimes  always\n           Trail window                            on  off\n           Banner             d @                  on  off\n           Window height                           7\n           Shifted prefixes   m S                  on  off\n           Load extensions    m x                  on  off\n           Autorange units    u a                  on  off\n           Record modes       m R                  nowhere  local  edit  perm  global  settings\n"))
  (:key "K" :messages nil :error nil :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")
        :extra
        (:header "     Group Option Value " :buffer
                 " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n")))
 (final :buffer
        " TAB select   RET set   d reset   c changed   K calc keys   S save   M-n/M-p group   g refresh   q quit   underlined = default\n\n Numbers   Angle measure      degrees  radians  HMS\n           Precision          12\n           Fraction mode      on  off\n           Symbolic mode      on  off\n           Infinite mode      on  off\n           Complex form       rectangular  polar\n                              \n Algebra   Simplification     none  numeric  basic  binary  algebraic  extended  units\n           Algebraic entry    off  partial  incomplete  total\n           Matrix mode        unknown  matrix  square matrix  scalar\n           Auto-recompute     on  off\n                              \n Display   Radix              decimal  binary  octal  hexadecimal\n           Float format       normal  fixed point  scientific  engineering\n           Digit grouping     on  off\n           Leading zeros      on  off\n           Line numbers       on  off\n           Line breaking      on  off\n           Justification      left  center  right\n           Decimal point      .\n           Strings            on  off\n           Raw display        on  off\n           Language           normal  flat  big  unformatted  C  Pascal  FORTRAN  TeX  LaTeX  eqn  Yacas  Maxima  Giac  Mathematica  Maple\n                              \n Formats   Complex numbers    (x,y)  x+yi  x+yj\n           Fractions          :\n           HMS                %s@ %s' %s\"\n           Dates              H:mmCSSpp Www Mmm D, YYYY\n           Group separator    ,\n           Left label         none\n           Right label        none\n                              \n Vectors   Vector brackets    [ ]  { }  ( )  none\n           Vector commas      on  off\n           Long vectors       on  off\n           One per line       on  off\n           Trail vectors      on  off\n           Matrix columns     left  center  right\n           Matrix brackets    R O\n                              \n Binary    Word size          8  16  32  64\n           Two's complement   on  off\n                              \n Selection Show selection     on  off\n           Associative        on  off\n                              \n Session   Working message    off  brief  detailed\n           Explain results    never  sometimes  always\n           Trail window       on  off\n           Banner             on  off\n           Window height      7\n           Shifted prefixes   on  off\n           Load extensions    on  off\n           Autorange units    on  off\n           Record modes       nowhere  local  edit  perm  global  settings\n"
        :header "     Group Option Value " :at
        (:line 3 :column 11 :text
               " Numbers   Angle measure      degrees  radians  HMS")))
