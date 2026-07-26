#!/bin/sh
#
# Container startup: make the agent usable and the Emacs instance live,
# then hand over to the command (a shell, by default).

set -e

# Auth. The host's Claude credentials are mounted read-only at /seed;
# copy them in so the agent's token refresh writes to the container's
# own copy and can never corrupt the host file.
if [ -f /seed/credentials.json ]; then
    cp /seed/credentials.json "$HOME/.claude/.credentials.json"
    chmod 600 "$HOME/.claude/.credentials.json"
fi

# The user's Emacs config, when the box was started with --emacsd: it is
# mounted read-only at /seed and copied in, so everything Emacs writes
# from here on — elpa, eln-cache, custom.el — stays in the container.
# Left behind: eln-cache, keyed by an Emacs version and ABI that are not
# this Emacs's, and .git, which is 20M of history a box has no use for.
# Skipped once the copy is there, so restarting a box costs nothing.
if [ -d /seed/emacs.d ] && [ ! -e "$HOME/.emacs.d/init.el" ]; then
    tar -C /seed/emacs.d --exclude=./eln-cache --exclude=./.git -cf - . \
        | tar -C "$HOME/.emacs.d" -xf -
fi

# The dev Emacs, on a tmux pty so it has a real tty frame. Beside it, a
# shell in a second pane: the two things a box is for, visible at once.
# Drive Emacs from either with `emacsclient -s $MAF_SERVER_NAME`.
if [ -f /work/project-init.el ] && ! tmux has-session -t emacs 2>/dev/null; then
    tmux new-session -d -s emacs 'emacs -nw -l /etc/maf/container-init.el'
    # -b puts the new pane before the current one: shell on the left,
    # Emacs on the right with the larger share.
    tmux split-window -h -b -l 40% -t emacs:0 -c /work
    tmux select-pane -t emacs:0.0
    # Which box is this? The session is called emacs in every one of
    # them, so the status line says the hostname instead — box sets that
    # to the feature name.
    tmux set -g status-left '[#h] '
fi

exec "$@"
