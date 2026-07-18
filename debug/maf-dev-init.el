;; -*- lexical-binding: t; -*-
;;
;; maf-dev-init.el
;;
;; Init file for the dedicated maf development/test Emacs instance.
;; See docs/memory/dev-instance.md for the workflow. Launch from the
;; project root (so default-directory is the repo) with the user's normal
;; config (no -Q). The server name comes from $MAF_SERVER_NAME (default
;; "duo" — a joint agent/human session), allowing multiple instances,
;; e.g. one per worktree:
;;
;;   cd /home/david/lab/emacs-maf && \
;;     MAF_SERVER_NAME=maf-refactor \
;;     nohup emacs -title maf-refactor -l debug/maf-dev-init.el >/dev/null 2>&1 &

(setq server-name (or (getenv "MAF_SERVER_NAME") "duo"))
(server-start)
(defconst maf-dev--root
  (expand-file-name ".." (file-name-directory (or load-file-name
                                                  buffer-file-name)))
  "Repo root, resolved from this file's location.")
(load (expand-file-name "maf.el" maf-dev--root))
(calc)
(with-current-buffer "*Calculator*"
  (maf-mode 1))
;; Starting layout: maf.org on the left, calc on the right.
(delete-other-windows)
(find-file (expand-file-name "docs/maf.org" maf-dev--root))
(set-window-buffer (split-window-right) "*Calculator*")
