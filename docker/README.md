# Dev boxes

One container per feature branch. The branch lives in a host git
worktree (`../maf-worktrees/<feature>`) bind-mounted at `/work`, so
edits and commits land in this repo — merging is plain `git merge`.

Each box runs its own Emacs with a private server named after the
feature, driven the same way as the host dev instance.

## Commands

Run from the repo root.

```sh
docker/box build                # build the image (once, and after editing Dockerfile)
docker/box up <feature>         # worktree + container + Emacs, ready to drive
docker/box eval <feature> SEXP  # run elisp in that box's Emacs
docker/box sh <feature>         # shell inside the container
docker/box ls                   # running boxes
docker/box down <feature>       # stop the container (worktree kept)
```

`up` creates the branch and worktree if they don't exist, and reuses
them if they do.

## Example

```sh
docker/box build
docker/box up chain-rewrite

docker/box eval chain-rewrite '(with-current-buffer "*Calculator*" maf-mode)'
docker/box eval chain-rewrite '(load-file "/work/core/maf-chain.el")'

# step a test: load it, then send SPC per form and read the cockpit
docker/box eval chain-rewrite '(load-file "/work/tests/dup.el")'
docker/box eval chain-rewrite '(with-selected-window (get-buffer-window "*maf-step*" t)
  (execute-kbd-macro (kbd "SPC SPC SPC"))
  (buffer-substring-no-properties (point-min) 200))'
```

Pass is `DONE` in the header with no `ERROR`; failures render as `;;!`
lines.

## Finishing a feature

```sh
docker/box down chain-rewrite
git merge chain-rewrite
git worktree remove ../maf-worktrees/chain-rewrite
git branch -d chain-rewrite
```

## Notes

- `box` uses `sudo docker` unless you are in the `docker` group
  (`sudo usermod -aG docker $USER`, then log back in).
- Worktree location is `../maf-worktrees` by default; override with
  `MAF_WORKTREES`.
- The container Emacs loads `docker/init.el` only — no personal config,
  so `posframe` is absent and `maf-preview` stays inert.
- All boxes share this repo's `.git`; isolation is per-worktree, not
  per-repository.
