;; -*- lexical-binding: t; -*-
;;
;; maf-dev-init.el
;;
;; Init file for the dedicated maf development/test Emacs instance.
;; See docs/memory/dev-instance.md for the workflow. Launch from the
;; project root (so default-directory is the repo) with the user's normal
;; config (no -Q):
;;
;;   cd /home/david/lab/emacs-maf && \
;;     nohup emacs -title maf-dev -l debug/maf-dev-init.el >/dev/null 2>&1 &

(setq server-name "maf-dev")
(server-start)
(load (expand-file-name "../maf.el"
                        (file-name-directory (or load-file-name
                                                 buffer-file-name))))
(calc)
(with-current-buffer "*Calculator*"
  (maf-mode 1))
