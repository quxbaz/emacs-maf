# maf dev box — a complete development environment in a container.
#
# The image holds the environment: shell, Emacs, git, and the Claude
# Code agent. The code is not baked in; a checkout is bind-mounted at
# /work when you run the container, so edits land on the host.

FROM debian:trixie-slim

# emacs-nox: terminal Emacs (30.x) — no X libs. Run under tmux it still
#   gets a real tty frame, so windows exist and execute-kbd-macro works.
# tmux: keeps Emacs on a pty while you use the shell.
# ripgrep: the agent's search tool.
RUN apt-get update && apt-get install -y --no-install-recommends \
        emacs-nox \
        git \
        tmux \
        ripgrep \
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

RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

# Run as a non-root user whose uid matches the host's, so files written
# into the bind-mounted checkout are owned by the host user, not root.
# (Claude Code also refuses to skip permission prompts when run as root.)
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} dev \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash dev \
    && mkdir -p /home/dev/.emacs.d /home/dev/.claude /home/dev/.codex \
                /home/dev/conf/agents \
    && chown -R ${UID}:${GID} /home/dev

# Everything below comes from files/ — the files baked into the image.

# Emacs config: private server + load the project (see files/init.el).
COPY --chown=dev:dev files/init.el /home/dev/.emacs.d/init.el

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

# Emacs server name inside this container; override with -e per box.
ENV MAF_SERVER_NAME=maf
# Marks the shell as a container box (the repo's CLAUDE.md keys off it).
ENV MAF_CONTAINER=1

# The entrypoint installs credentials and starts Emacs, then runs CMD.
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["bash"]
