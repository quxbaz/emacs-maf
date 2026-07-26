;; -*- lexical-binding: t; -*-
;;
;; container-init.el
;;
;; Loaded with -l, so it runs after whatever init files a box has: none
;; by default, the user's own when the box was started with --emacsd.
;; Either way it supplies the two things a box needs — a private server
;; to drive Emacs through, and the project itself.
;;
;; Started under tmux inside the container:
;;
;;   tmux new-session -d -s emacs 'emacs -nw -l /etc/maf/container-init.el'
;;
;; and driven from outside with:
;;
;;   docker exec <box> emacsclient -s '#emacs' --eval '(calc-stack-size)'

(setq inhibit-startup-screen t)

;; Private server, one per container (name from the env, as on the host).
(setq server-name (or (getenv "MAF_SERVER_NAME") "#emacs"))
(server-start)

;; The user's config loads a project's project-init.el the first time a
;; file from that root is visited, and remembers the root so it happens
;; once. Claim /work/ before loading it below, or a later find-file loads
;; it a second time. Without that config the variable is simply unbound.
(when (boundp 'my/project-init-loaded-roots)
  (add-to-list 'my/project-init-loaded-roots "/work/"))

;; The bind-mounted worktree. project-init.el loads maf.el, enables
;; maf-mode in calc buffers, and picks the layout — calc alone in a
;; container, where Emacs has a tmux pane rather than a frame.
(let ((project-init "/work/project-init.el"))
  (when (file-exists-p project-init)
    (load project-init)))
