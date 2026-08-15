# Dev boxes

A container holding the development environment — shell, Emacs with maf
loaded, git, and the agents (Claude Code and codex) — for working a
feature branch.
One box per feature, several at once.

The code is *not* in the image. A worktree is bind-mounted at `/work`,
so everything the agent writes lands on the host and merging is plain
git.

## Commands

```sh
box <feature>          start a box, making its worktree and branch if new
box --bare <feature>   the same, with stock Emacs instead of my config
box --close <feature>  done and merged: container, worktree, branch
box -d <feature>       discard it instead: the same three, work and all
box                    list the worktrees you can name
box --names            those names alone, for completion
box --rebuild          rebuild the image, for newer agents
box --help             usage
. ./dev.sh             put box on PATH with tab completion
```

Spelled `docker/box` until `dev.sh` is sourced.

## Quick start

1. Build the image (once per machine; `box` does it for you the first
   time it is needed):

   ```sh
   sudo docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t maf docker/
   ```

   The agents are installed into the image, so every box runs the
   versions of the day it was built. `docker/box --rebuild` refreshes
   them, keeping the old image as `maf-old`; `box` says so itself once
   the image is a month old. Boxes already made keep the image they
   were made from until closed and made again.

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
   Start an agent in the shell and instruct it — either one, both
   already authed:

   ```sh
   claude
   codex
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
  -e CLAUDE_CODE_OAUTH_TOKEN="$(< ~/.claude/box-token)" \
  -v ~/.claude.json:/seed/claude.json:ro \
  -v ~/.codex/auth.json:/seed/codex-auth.json:ro \
  -v ~/.gitconfig:/home/dev/.gitconfig:ro \
  -v ~/conf/claude/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro \
  -v ~/conf/claude/keybindings.json:/home/dev/.claude/keybindings.json:ro \
  -v ~/conf/agents/AGENTS.md:/home/dev/conf/agents/AGENTS.md:ro \
  -v ~/conf/agents/AGENTS.md:/home/dev/.codex/AGENTS.md:ro \
  -v ~/conf/codex/config.toml:/home/dev/.codex/config.toml:ro \
  -v ~/conf/tmux/tmux.conf:/home/dev/.config/tmux/tmux.conf:ro \
  -v ~/.emacs.d:/seed/emacs.d:ro \
  maf
```

| flag | why |
|---|---|
| `-it` | interactive shell; drop it and add docker's own `-d` to run detached |
| no `--rm` | the box outlives the shell, so you can come back to it; `docker rm maf-<feature>` when done |
| `-v ...worktrees/my-feature:/work` | the worktree this box works on — the one line that assigns the branch |
| `-v ...emacs-maf/.git:<same path>` | the main `.git`, at its *host path*: a worktree's `.git` file names that path absolutely, so git inside only resolves if the path matches exactly |
| `-e CLAUDE_CODE_OAUTH_TOKEN=...` | Claude auth: the long-lived token from `~/.claude/box-token` (minted by `claude setup-token`, per machine — see `conf/install/setup.org`). It never rotates, so boxes cannot log each other — or the host — out. Without the file, `box` falls back to `-v ~/.claude/.credentials.json:/seed/credentials.json:ro`, a copy of the live session; copies rotate independently and fight, so expect login prompts |
| `-v ~/.claude.json:/seed/claude.json:ro` | which models Claude offers: its `/model` menu is built from entitlement caches in this file that only a login fills in, and a token is not a login — without this a box's menu is the built-in list, no Fable (though `--model fable` still works). The entrypoint copies those cache keys, and only those, into the box's own `.claude.json` on every start; nothing else in the host file is taken |
| `-v ~/.codex/auth.json:/seed/...:ro` | codex auth, seeded as a copy. Optional: without it a box still starts and codex asks you to sign in there |
| `-v ~/.gitconfig:...:ro` | your name/email, so commits from inside are attributed |
| `-v ~/conf/claude/...:ro` (×6) | your agent config, each file where its agent reads it — on the host these paths are symlinks into `~/conf`, a box takes the real files. `AGENTS.md` appears twice: for codex, and at the path `CLAUDE.md` imports. Any that is missing is skipped; `$MAF_CONF` names another `conf` |
| `-v ~/.emacs.d:/seed/emacs.d:ro` | my Emacs config, copied in at startup by the entrypoint rather than mounted, since Emacs writes into it. `--bare` swaps this for `-v ~/.emacs.d/my/calc:...:ro` alone — the legacy Calc config the `port` skill reads, at the path that skill names |
| (no `-e MAF_SERVER_NAME`) | the image names the Emacs server `#emacs`, the name the `emacs` skill uses when given none — a container holds one instance, so the skills' examples work in a box unchanged |

## Inside the box

```sh
claude                      # agent, already authed — instruct it from here
codex                       # the other one, likewise (cc / cx are aliases)
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
- The agents themselves are as old as the image: npm-installed at build,
  root-owned, so they cannot update themselves in a box. `box --rebuild`
  refreshes them (the previous image stays as `maf-old`), and `box`
  points that out on its own once the image is past a month. Nothing
  else in the image goes stale the same way — the code is mounted, and
  your config is mounted or seeded — so a rebuild is only ever about the
  agents. Existing boxes keep their image; close and remake one to move
  it over.
- Claude's `/model` menu in a box lists what the host's does — Fable
  included — because the entrypoint seeds the model-entitlement caches
  from the host's `~/.claude.json` on every start. Those caches are
  filled in only by a real login, which the token auth below is not; a
  box left to itself shows the built-in list. Should the menu lag the
  host, `--model fable` (or any name) works regardless.
- Claude auth is a long-lived token (`~/.claude/box-token`, from `claude
  setup-token`), fixed into the environment when the container is
  created: nothing refreshes, so a box never invalidates another's
  session — a re-minted token reaches only boxes made after it. Codex
  auth is a copy: its refresh inside the box updates only the
  container's copy, lost on exit and re-seeded on every start. Claude
  falls back to the same copy scheme when the token file is absent, but
  copies of a rotating session invalidate one another — the first box
  (or the host) to refresh logs the rest out. To run a box on a
  different account, swap the token / credentials source.
- Agent config is brought over two different ways. Claude's is layered:
  the box bakes its own `claude.json` and `settings.json` (onboarding
  done, `/work` trusted, permissions bypassed) and mounts only
  `CLAUDE.md` and `keybindings.json` from `~/conf` — your host
  `settings.json` is deliberately *not* mounted, so a box does not
  inherit its permission rules or hooks. Codex has no baked box config
  at all: `config.toml` is mounted from `~/conf` verbatim, so a box gets
  your host settings whole. That file needs a `[projects."/work"]`
  trust entry, since none of its host paths exist in a container.
- Which box is this? The feature is the container's hostname, so it is
  in the shell prompt (`dev@my-feature:/work$`) and at both ends of
  tmux's status bar — the session is called `emacs` in every box, so the
  status line shows the hostname instead.
- `LANG=C.UTF-8` is set in the image. Without a locale tmux starts its
  client in ASCII mode and draws `_` for every glyph it cannot emit,
  which shreds the agent's boxes and gutters.
- A box runs my Emacs config: `~/.emacs.d` is copied in at startup,
  packages and all, minus `eln-cache` (keyed to an Emacs version and ABI
  that are not the box's) and `.git`. Emacs writes to the copy, so
  nothing a box does reaches the host config. `box --bare` skips it for
  stock Emacs plus the legacy Calc config alone.
- Emacs in a box has a tmux pane, not a frame, so `display-graphic-p` is
  nil: child frames cannot show, so `maf-preview` falls back to drawing
  its panel inside the calc window (posframe is installed but unusable
  here), and `maf-hl-verify`'s screenshot check reports `skipped`.
- All boxes share this repo's `.git`; isolation is per-worktree, not
  per-repository.
- Worktrees live in `.worktrees/`, git-ignored, so they never show up as
  untracked files in the main checkout.
