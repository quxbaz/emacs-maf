---
name: merge
description: Merge a named maf feature branch or box worktree into the current branch, then close its box with `box --close NAME` only after the merge succeeds. Use when asked to merge, land, integrate, or finish a feature branch/worktree and clean up its box.
---

# Merge and close a feature

Given a feature name, merge its branch into the current branch and close the
corresponding box only after the merge is complete.

## Workflow

1. From the repository root, inspect the current branch and working tree with
   `git status --short --branch`. Confirm the named feature branch exists.
2. Run `git merge NAME`.
3. If the merge conflicts, resolve them while preserving the intended changes
   from both sides, validate the result in proportion to the changes, and
   complete the merge commit. Do not close the box while the merge is unresolved
   or failed.
4. After a successful merge, run:

   ```sh
   box --close NAME
   ```

5. Report the merge result and exactly what `box --close` removed.

Treat an already-up-to-date merge as successful. If `box --close` refuses
because the feature worktree is dirty or for any other safety check, stop and
report the reason. Never substitute `box -d`; uncommitted work must not be
discarded.
