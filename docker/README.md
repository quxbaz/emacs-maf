# Dev boxes

A container holding the development environment — shell, Emacs with maf
loaded, git, and the Claude Code agent — for working a feature branch.
One box per feature, several at once.

The code is *not* in the image. A worktree is bind-mounted at `/work`,
so everything the agent writes lands on the host and merging is plain
git.

## Quick start

1. Build the image (once per machine):

   ```sh
   sudo docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t maf-dev docker/
   ```

2. Make a worktree for the feature — the branch is named after the
   directory, created from HEAD if it does not exist yet:

   ```sh
   git worktree add .worktrees/my-feature
   ```

3. Start the box on it:

   ```sh
   docker/box my-feature
   ```

   `docker/box -b my-feature` does steps 2 and 3 in one, making the
   worktree and branch before starting the box. Run `docker/box` with no
   arguments to list the worktrees you can name, `docker/box --help` for
   usage.

4. You land in a shell at `/work`, Emacs already running. Start the
   agent and instruct it:

   ```sh
   claude
   ```

5. Repeat 2–4 in another terminal for each additional feature.

6. When the feature is done, exit the shell (the container is removed)
   and merge on the host:

   ```sh
   git merge my-feature
   git worktree remove .worktrees/my-feature
   git branch -d my-feature
   ```

## The run command, flag by flag

`docker/box` creates nothing — it takes the feature name and derives the
`docker run` below from it, so a worktree that does not exist is an error
rather than a guess. Run it by hand if you want a box shaped differently:

```sh
sudo docker run -it --rm --name maf-my-feature \
  -v ~/lab/emacs-maf/.worktrees/my-feature:/work \
  -v ~/lab/emacs-maf/.git:/home/david/lab/emacs-maf/.git \
  -v ~/.claude/.credentials.json:/seed/.credentials.json:ro \
  -v ~/.gitconfig:/home/dev/.gitconfig:ro \
  -e MAF_SERVER_NAME=my-feature \
  maf-dev
```

| flag | why |
|---|---|
| `-it` | interactive shell; drop it and add `-d` to run detached |
| `--rm` | delete the container on exit (the code is on the host, nothing to lose) |
| `-v ...worktrees/my-feature:/work` | the worktree this box works on — the one line that assigns the branch |
| `-v ...emacs-maf/.git:<same path>` | the main `.git`, at its *host path*: a worktree's `.git` file names that path absolutely, so git inside only resolves if the path matches exactly |
| `-v ...credentials.json:/seed/...:ro` | agent auth; copied in at startup, read-only so the container can't touch your host token |
| `-v ~/.gitconfig:...:ro` | your name/email, so commits from inside are attributed |
| `-e MAF_SERVER_NAME=` | names the Emacs server, one per box |

## Inside the box

```sh
claude                      # agent, already authed — instruct it from here
tmux attach -t emacs        # the live Emacs (C-b d to detach)
emacsclient -s my-feature --eval '(calc-stack-size)'
git commit -am '...'        # lands on the host branch
```

Emacs is already up when the shell appears: `project-init.el` loaded,
maf-mode on in `*Calculator*`, `maf.org | *Calculator*` layout. The
agent knows to use the running instance — `$MAF_CONTAINER` is set, which
the repo's `CLAUDE.md` keys off.

## Notes

- `docker/box` adds `sudo` only when the docker socket needs it. Drop it
  everywhere by joining the docker group: `sudo usermod -aG docker $USER`,
  then log back in.
- `. ./dev-init.sh` at the repo root puts `box` on `PATH` and turns on
  tab completion for feature names, so the commands above shorten to
  `box my-feature`. Completion alone lives in `docker/completions/`
  (bash, zsh, fish) — each shim asks `box --names` for the candidates
  rather than parsing the listing, and says how to load it.
- The agent runs with permission prompts off (`docker/files/settings.json`,
  `defaultMode: bypassPermissions`) — the container is the sandbox. Change
  that file and rebuild to tighten it.
- Auth is a copy: a token refresh inside the box updates only the
  container's copy, and is lost when it exits. Re-seeded from the host
  file on every start. To run a box on a different account, mount that
  account's credentials file instead.
- No personal Emacs config in the box — no `posframe`, so `maf-preview`
  is inert, and `maf-hl-verify`'s screenshot check reports `skipped`.
- All boxes share this repo's `.git`; isolation is per-worktree, not
  per-repository.
- Worktrees live in `.worktrees/`, git-ignored, so they never show up as
  untracked files in the main checkout.
