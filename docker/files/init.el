;; -*- lexical-binding: t; -*-
;;
;; init.el (container)
;;
;; Emacs config for a maf dev container. Plays the part the host setup
;; splits between agent/emacs-init.el (private server socket) and the
;; user's personal config (which loads project-init.el on find-file):
;; here there is no personal config, so the project is loaded directly.
;;
;; Started under tmux inside the container:
;;
;;   tmux new-session -d -s maf emacs -nw
;;
;; and driven from outside with:
;;
;;   docker exec <box> emacsclient -s maf --eval '(calc-stack-size)'

(setq inhibit-startup-screen t)

;; Private server, one per container (name from the env, as on the host).
(setq server-name (or (getenv "MAF_SERVER_NAME") "maf"))
(server-start)

;; The bind-mounted worktree. project-init.el loads maf.el, enables
;; maf-mode in calc buffers, and lays out maf.org | *Calculator*.
(let ((project-init "/work/project-init.el"))
  (when (file-exists-p project-init)
    (load project-init)))
