#!/bin/sh
#
# Container startup: make the agent usable and the Emacs instance live,
# then hand over to the command (a shell, by default).

set -e

# Auth. The host's Claude credentials are mounted read-only at /seed;
# copy them in so the agent's token refresh writes to the container's
# own copy and can never corrupt the host file.
if [ -f /seed/.credentials.json ]; then
    cp /seed/.credentials.json "$HOME/.claude/.credentials.json"
    chmod 600 "$HOME/.claude/.credentials.json"
fi

# The dev Emacs, on a tmux pty so it has a real tty frame. Beside it, a
# shell in a second pane: the two things a box is for, visible at once.
# Drive Emacs from either with `emacsclient -s $MAF_SERVER_NAME`.
if [ -f /work/project-init.el ] && ! tmux has-session -t emacs 2>/dev/null; then
    tmux new-session -d -s emacs 'emacs -nw'
    # -b puts the new pane before the current one: shell on the left,
    # Emacs on the right with the larger share.
    tmux split-window -h -b -l 40% -t emacs:0 -c /work
    tmux select-pane -t emacs:0.0
fi

exec "$@"
