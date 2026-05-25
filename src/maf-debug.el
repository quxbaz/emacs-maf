;; -*- lexical-binding: t; -*-
;;
;; maf-debug.el
;;
;; maf debug functions

(defmacro maf-debug-slowly (&rest body)
  "Run each form in BODY on a timer, spaced 0.5s apart.
Each form runs in the buffer that was current when this macro was called.
Form 1 runs at 0.5s, form 2 at 1.0s, form 3 at 1.5s, etc."
  (declare (indent 0))
  (let ((buf (gensym "buf-")))
    `(let ((,buf (current-buffer)))
       ,@(cl-loop for form in body
                  for i from 1
                  collect `(run-at-time ,(* 0.25 i) nil
                                        (lambda ()
                                          (with-current-buffer ,buf ,form)))))))

(provide 'maf-debug)
