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

;; The agent launches this instance from its own shell, whose
;; SSH_AUTH_SOCK is a snapshot from wherever that session began — often
;; a dead socket by launch time. Git under magit then finds no agent
;; and falls back to prompting for the key's passphrase, which the
;; user's normally-started Emacs (inheriting the live session socket)
;; never does. Repoint at a live agent socket whenever the inherited
;; one is unset or stale, probing the standard per-user locations:
;; gpg-agent's ssh interface, gnome-keyring, the systemd ssh-agent.
(let ((sock (getenv "SSH_AUTH_SOCK")))
  (unless (and sock (file-exists-p sock))
    (let* ((runtime (or (getenv "XDG_RUNTIME_DIR")
                        (format "/run/user/%d" (user-uid))))
           (live (seq-find #'file-exists-p
                           (list (expand-file-name "gnupg/S.gpg-agent.ssh" runtime)
                                 (expand-file-name "keyring/ssh" runtime)
                                 (expand-file-name "ssh-agent.socket" runtime)))))
      (when live
        (setenv "SSH_AUTH_SOCK" live)))))
