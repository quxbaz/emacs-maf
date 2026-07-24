# maf dev box — one container per feature branch.
#
# The image carries only the toolchain: emacs, git, tmux. The code is
# NOT baked in; a worktree is bind-mounted at /work when the container
# runs, so edits land on the host and merging stays plain git.

FROM debian:trixie-slim

# emacs-nox: terminal Emacs (30.x on trixie) — no X libs, so the image
#   stays small. Run under tmux it still gets a real tty frame, which
#   means windows exist and execute-kbd-macro works like the GUI instance.
# tmux: keeps Emacs attached to a pty inside the container.
# git: branch/worktree work from inside the box.
RUN apt-get update && apt-get install -y --no-install-recommends \
        emacs-nox \
        git \
        tmux \
        ca-certificates \
        less \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root user whose uid matches the host's, so files written
# into the bind-mounted worktree are owned by the host user, not root.
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} dev \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash dev

USER dev
WORKDIR /work

# The container's Emacs config: private server + load the project.
COPY --chown=dev:dev init.el /home/dev/.emacs.d/init.el

# Default server name; override per container with -e MAF_SERVER_NAME=...
ENV MAF_SERVER_NAME=maf

CMD ["bash"]
