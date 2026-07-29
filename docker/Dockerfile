# maf dev box — a complete development environment in a container.
#
# The image holds the environment: shell, Emacs, git, and the agents
# (Claude Code and codex). The code is not baked in; a checkout is
# bind-mounted at /work when you run the container, so edits land on
# the host.

FROM debian:trixie-slim

# emacs-nox: terminal Emacs (30.x) — no X libs. Run under tmux it still
#   gets a real tty frame, so windows exist and execute-kbd-macro works.
# tmux: keeps Emacs on a pty while you use the shell.
# ripgrep: the agent's search tool.
# bubblewrap: codex's sandbox. It ships one bundled and falls back to it
#   with a warning on every run; the packaged binary silences that.
RUN apt-get update && apt-get install -y --no-install-recommends \
        emacs-nox \
        git \
        tmux \
        ripgrep \
        bubblewrap \
        ca-certificates \
        curl \
        gnupg \
        less \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Node for the agent, from NodeSource rather than Debian: trixie ships
# node 20, and claude-code requires >=22. npm only warns about that, so
# without this the image builds fine and fails at runtime instead.
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Both agents, from npm. The host installs codex standalone, into
# ~/.codex/packages; npm is the same binary by another route, and keeps
# the two agents on one line of install here.
RUN npm install -g @anthropic-ai/claude-code @openai/codex \
    && npm cache clean --force

# Run as a non-root user whose uid matches the host's, so files written
# into the bind-mounted checkout are owned by the host user, not root.
# (Claude Code also refuses to skip permission prompts when run as root.)
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} dev \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash dev \
    && mkdir -p /home/dev/.emacs.d/my /home/dev/.claude /home/dev/.codex \
                /home/dev/conf/agents /home/dev/.config/tmux \
    && chown -R ${UID}:${GID} /home/dev

# Everything below comes from files/ — the files baked into the image.

# The Emacs bits a box needs — private server, load the project. Not an
# init.el: with --emacsd the user's own config lands at that path, so
# this is loaded after it with -l (see files/container-init.el).
COPY files/container-init.el /etc/maf/container-init.el

# Agent config, pre-seeded so `claude` starts straight into a session:
# no onboarding, no trust prompt, no per-tool permission prompts (the
# container is the sandbox). Edit files/settings.json to tighten that.
COPY --chown=dev:dev files/claude.json /home/dev/.claude.json
COPY --chown=dev:dev files/settings.json /home/dev/.claude/settings.json

# My shell aliases, the ones that apply in a box. Debian's stock .bashrc
# sources ~/.bash_aliases if it is there, so nothing else is needed.
COPY --chown=dev:dev files/bash_aliases /home/dev/.bash_aliases

COPY --chmod=0755 files/entrypoint.sh /usr/local/bin/entrypoint

USER dev
ENV HOME=/home/dev
WORKDIR /work

# A UTF-8 locale. Debian's default is none at all, and tmux decides at
# client start whether the terminal is UTF-8 by reading LC_ALL, LC_CTYPE
# and LANG: with all three empty it falls back to ASCII and draws an
# underscore for every glyph it cannot emit, which turns the agent's box
# drawing and gutters into rows of them. C.UTF-8 is the only UTF-8
# locale the image has, so this needs no locales package.
ENV LANG=C.UTF-8

# Emacs server name inside this container. '#emacs' is what the emacs
# skill reaches for when given no name, and a container holds only one
# instance, so the skills' examples work here as written. Per-box names
# would buy nothing: the socket is not reachable from outside anyway,
# and the container name already says which feature this is.
ENV MAF_SERVER_NAME="#emacs"
# Marks the shell as a container box (the repo's CLAUDE.md keys off it).
ENV MAF_CONTAINER=1

# The entrypoint installs credentials and starts Emacs, then runs CMD.
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["bash"]
