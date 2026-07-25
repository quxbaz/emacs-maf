# fish completion for box.
#
#   source /path/to/emacs-maf/docker/completions/box.fish
#
# or link it into ~/.config/fish/completions/box.fish to load on demand.
# -f: a feature is not a file, so do not offer filenames as well.

complete -c box -f -a '(box --names)'
