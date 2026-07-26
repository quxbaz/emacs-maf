# Dev boxes

A container holding the development environment — shell, Emacs with maf
loaded, git, and the Claude Code agent — for working a feature branch.
One box per feature, several at once.

The code is *not* in the image. A worktree is bind-mounted at `/work`,
so everything the agent writes lands on the host and merging is plain
git.

## Commands

```sh
box <feature>          start a box, making its worktree and branch if new
box --close <feature>  done and merged: container, worktree, branch
box -d <feature>       discard it instead: the same three, work and all
box                    list the worktrees you can name
box --names            those names alone, for completion
box --help             usage
. ./dev.sh             put box on PATH with tab completion
```

Spelled `docker/box` until `dev.sh` is sourced.

## Quick start

1. Build the image (once per machine):

   ```sh
   sudo docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t maf docker/
   ```

2. Start a box on the feature:

   ```sh
   docker/box my-feature
   ```

   First time out that makes `.worktrees/my-feature` and a branch of the
   same name from HEAD; if the branch already exists it is checked out
   instead. After that the same command comes back to the box. Run
   `docker/box` with no arguments to list the worktrees you can name,
   `docker/box --help` for usage.

3. You land in tmux: a shell at `/work` on the left, Emacs on the right.
   Start the agent in the shell and instruct it:

   ```sh
   claude
   ```

   tmux is yours: `~/conf/tmux/tmux.conf` is mounted, so the box answers
   to the same keys as anywhere else — prefix `C-t`, `|` and `_` to
   split, `j`/`k` to cycle windows, `l` to list them. `C-t o` moves
   between panes, `C-t z` zooms one full-screen. `C-t d` detaches tmux
   and drops you to a plain shell in the same box, with Emacs still up
   behind it; `tmux attach -t emacs` returns. Your `C-t C-t` is
   `last-window` rather than send-prefix, so nothing reaches the pane as
   a literal `C-t` — Emacs's `transpose-chars` is out of reach in there.

   Detaching from the *container* is `C-q C-q`, not docker's `C-p C-q`
   default — `C-p` is `previous-line`, which the client would otherwise
   swallow in the Emacs pane while it waited to see if `C-q` followed.
   It leaves the box running; `docker/box <feature>` comes back.

4. Repeat 2–3 in another terminal for each additional feature.

5. Exiting the shell leaves the box behind, stopped. `docker/box
   my-feature` again picks it up where you left it — the same container,
   its filesystem intact, Emacs started fresh. While one is running, the
   same command opens another shell inside it.

6. When the feature is done, close it out from the host — the box has
   only its own worktree and no key to push with, so integrating is the
   main checkout's job. Merge first: until it lands, the box is still
   there to go back to if something turns out to be wrong.

   ```sh
   git merge my-feature            # from the main checkout
   docker/box --close my-feature   # container, worktree, branch
   ```

   `--close` reports each of the three, and refuses before touching
   anything if the branch is not merged, the worktree holds changes, or
   you are standing in it. What is already gone counts as done, so a
   half-cleaned feature can be finished off.

   `docker/box -d my-feature` is the same three steps for work you are
   throwing away: it forces past uncommitted changes and an unmerged
   branch, so nothing survives but the reflog. By hand:

   ```sh
   sudo docker rm -f maf-my-feature
   git worktree remove .worktrees/my-feature && git branch -d my-feature
   ```

   Discarding by hand is the same with `--force` on the worktree remove
   and `-D` on the branch.

## The run command, flag by flag

`docker/box` derives the `docker run` below from the feature name, but
only for a name docker has never seen: an existing box it joins with
`docker exec` if it is running, or restarts with `docker start -ai` if it
is not, and makes the worktree when the feature has none yet. Run it by
hand if you want a box shaped differently:

```sh
sudo docker run -it --name maf-my-feature \
  -v ~/lab/emacs-maf/.worktrees/my-feature:/work \
  -v ~/lab/emacs-maf/.git:/home/david/lab/emacs-maf/.git \
  -v ~/.claude/.credentials.json:/seed/.credentials.json:ro \
  -v ~/.gitconfig:/home/dev/.gitconfig:ro \
  -v ~/conf/claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro \
  -v ~/conf/claude/keybindings.json:/home/dev/.claude/keybindings.json:ro \
  -v ~/conf/agents/AGENTS.md:/home/dev/conf/agents/AGENTS.md:ro \
  -v ~/conf/agents/AGENTS.md:/home/dev/.codex/AGENTS.md:ro \
  -v ~/conf/codex/config.toml:/home/dev/.codex/config.toml:ro \
  -v ~/conf/tmux/tmux.conf:/home/dev/.config/tmux/tmux.conf:ro \
  -v ~/.emacs.d/my/calc:/home/dev/.emacs.d/my/calc:ro \
  maf
```

| flag | why |
|---|---|
| `-it` | interactive shell; drop it and add docker's own `-d` to run detached |
| no `--rm` | the box outlives the shell, so you can come back to it; `docker rm maf-<feature>` when done |
| `-v ...worktrees/my-feature:/work` | the worktree this box works on — the one line that assigns the branch |
| `-v ...emacs-maf/.git:<same path>` | the main `.git`, at its *host path*: a worktree's `.git` file names that path absolutely, so git inside only resolves if the path matches exactly |
| `-v ...credentials.json:/seed/...:ro` | agent auth; copied in at startup, read-only so the container can't touch your host token |
| `-v ~/.gitconfig:...:ro` | your name/email, so commits from inside are attributed |
| `-v ~/conf/claude/...:ro` (×6) | your agent config, each file where its agent reads it — on the host these paths are symlinks into `~/conf`, a box takes the real files. `AGENTS.md` appears twice: for codex, and at the path `CLAUDE.md` imports. Any that is missing is skipped; `$MAF_CONF` names another `conf` |
| `-v ~/.emacs.d/my/calc:...:ro` | the legacy Calc config the `port` skill reads, at the path that skill names — without it, porting has nothing to port from |
| (no `-e MAF_SERVER_NAME`) | the image names the Emacs server `#emacs`, the name the `emacs` skill uses when given none — a container holds one instance, so the skills' examples work in a box unchanged |

## Inside the box

```sh
claude                      # agent, already authed — instruct it from here
tmux attach -t emacs        # back to Emacs beside a shell (C-t d to detach)
emacsclient -s '#emacs' --eval '(calc-stack-size)'
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
- `. ./dev.sh` at the repo root puts `box` on `PATH` and turns on
  tab completion for feature names, so the commands above shorten to
  `box my-feature`. Completion alone lives in `docker/completions/`
  (bash, zsh, fish) — each shim asks `box --names` for the candidates
  rather than parsing the listing, and says how to load it.
- The agent's defaults are `docker/files/settings.json`: Opus as the
  model, and permission prompts off (`defaultMode: bypassPermissions`) —
  the container is the sandbox. Change that file and rebuild to alter
  either.
- Auth is a copy: a token refresh inside the box updates only the
  container's copy, and is lost when it exits. Re-seeded from the host
  file on every start. To run a box on a different account, mount that
  account's credentials file instead.
- Which box is this? The feature is the container's hostname, so it is
  in the shell prompt (`dev@my-feature:/work$`) and at both ends of
  tmux's status bar — the session is called `emacs` in every box, so the
  status line shows the hostname instead.
- `LANG=C.UTF-8` is set in the image. Without a locale tmux starts its
  client in ASCII mode and draws `_` for every glyph it cannot emit,
  which shreds the agent's boxes and gutters.
- No personal Emacs config in the box — no `posframe`, so `maf-preview`
  is inert, and `maf-hl-verify`'s screenshot check reports `skipped`.
- All boxes share this repo's `.git`; isolation is per-worktree, not
  per-repository.
- Worktrees live in `.worktrees/`, git-ignored, so they never show up as
  untracked files in the main checkout.
