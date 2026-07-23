;; -*- lexical-binding: t; -*-
;;
;; emacs-init.el
;;
;; Init file for the shared agent/human Emacs instance. Its sole job
;; is making joint operation work: a private, per-session server
;; socket the agent can reach without touching the user's main
;; session. Everything project-level — loading the package, calc
;; setup, window layout — is project-init.el's business, loaded by
;; the user's normal config.
;;
;; See docs/memory/dev-instance.md for the workflow. Launch from the
;; project root (so default-directory is the repo) with the user's
;; normal config (no -Q). The server name comes from $MAF_SERVER_NAME
;; (default "#emacs" — a joint agent/human session), allowing multiple
;; instances, e.g. one per worktree:
;;
;;   cd /home/david/lab/emacs-maf && \
;;     MAF_SERVER_NAME=maf-refactor \
;;     nohup emacs -title maf-refactor -l agent/emacs-init.el >/dev/null 2>&1 &

(setq server-name (or (getenv "MAF_SERVER_NAME") "#emacs"))
(server-start)
