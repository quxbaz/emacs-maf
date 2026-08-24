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
(unless (server-running-p server-name)
  (server-start))

;; The agent launches this instance from its own shell, whose
;; SSH_AUTH_SOCK may be stale or point at a different, empty agent. Git
;; under magit then falls back to prompting for the key's passphrase,
;; which the user's normally-started Emacs (inheriting the login
;; session's populated agent) never does. Probe the inherited socket,
;; standard per-user sockets, and sockets made by a conventional
;; ssh-agent, preferring the first one that actually has identities.
(let* ((inherited (getenv "SSH_AUTH_SOCK"))
       (runtime (or (getenv "XDG_RUNTIME_DIR")
                    (format "/run/user/%d" (user-uid))))
       (candidates
        (delete-dups
         (delq nil
               (append
                (list inherited
                      (expand-file-name "gnupg/S.gpg-agent.ssh" runtime)
                      (expand-file-name "keyring/ssh" runtime)
                      (expand-file-name "ssh-agent.socket" runtime))
                (file-expand-wildcards "/tmp/ssh-*/agent.*" t)))))
       (populated
        (seq-find
         (lambda (socket)
           (and (file-exists-p socket)
                (let ((process-environment
                       (copy-sequence process-environment)))
                  (setenv "SSH_AUTH_SOCK" socket)
                  (eq 0 (call-process "ssh-add" nil nil nil "-l")))))
         candidates)))
  (when populated
    (setenv "SSH_AUTH_SOCK" populated)))
