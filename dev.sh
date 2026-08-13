# dev.sh — shell setup for working on maf. Source it:
#
#   . ./dev.sh
#
# Puts docker/box on PATH and turns tab completion for feature names on,
# in bash and zsh. The Emacs counterpart is project-init.el.
#
# On PATH rather than aliased on purpose: bash's `complete -C` names an
# external command and never expands aliases, so an alias would leave
# `box` completing to nothing.

# Sourcing is the whole point — run as a script this would set up a
# subshell that exits a moment later, looking like it did nothing.
_maf_sourced=0
if [ -n "${ZSH_VERSION-}" ]; then
    case $ZSH_EVAL_CONTEXT in *:file*) _maf_sourced=1 ;; esac
elif [ -n "${BASH_VERSION-}" ]; then
    (return 0 2>/dev/null) && _maf_sourced=1
fi

if [ "$_maf_sourced" = 0 ]; then
    echo "dev.sh does nothing when run; source it instead:" >&2
    echo "  . ./dev.sh   (bash or zsh)" >&2
    unset _maf_sourced
    # return when there is one to make, exit only when actually run:
    # sourced from a shell this file does not know, exit would close it.
    return 1 2>/dev/null || exit 1
fi

if [ -n "${ZSH_VERSION-}" ]; then
    _maf_self=${(%):-%x}
else
    _maf_self=${BASH_SOURCE[0]}
fi
_maf_repo=$(CDPATH= cd -- "$(dirname -- "$_maf_self")" && pwd)

case ":$PATH:" in
    *":$_maf_repo/docker:"*) ;;
    *) PATH="$PATH:$_maf_repo/docker" ;;
esac
export PATH

# Prefer the long-lived Claude setup token without exporting it to every
# child process. Fall back to Claude's normal credential lookup on machines
# that have not minted one yet (see ~/conf/install/setup.org).
claude() {
    if [ -s "$HOME/.claude/box-token" ]; then
        CLAUDE_CODE_OAUTH_TOKEN=$(<"$HOME/.claude/box-token") command claude "$@"
    else
        command claude "$@"
    fi
}

if [ -n "${ZSH_VERSION-}" ]; then
    fpath=("$_maf_repo/docker/completions" $fpath)
    # compdef arrives with compinit, which an interactive zsh has usually
    # run already. Reuse it when it is there: rerunning compinit is the
    # slow part of zsh startup, and this needs none of it.
    (( $+functions[compdef] )) || { autoload -Uz compinit && compinit; }
    autoload -Uz _box
    compdef _box box
elif [ -n "${BASH_VERSION-}" ]; then
    . "$_maf_repo/docker/completions/box.bash"
fi

unset _maf_sourced _maf_self _maf_repo
