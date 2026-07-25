# bash completion for box.
#
#   source /path/to/emacs-maf/docker/completions/box.bash
#
# `complete -C` names an external command, so bash asks box itself for
# the candidates and no shell function parses box's output. Completion
# follows the command word, so this covers `box` — put it on PATH or
# alias it; for `docker/box`, add that word too.

complete -C 'box --complete' box
