# Plan: quick recall ring (`maf-recall`)

Replaces the TODO in [maf.org](../maf.org) ("quick recall command, bind to
M-[n/p]"). Written up rather than left in conversation because the design turns
on one distinction that is easy to lose: **this ring holds what you *typed*; the
timeline holds what the stack *held*.**

**Status: landed** as `modules/maf-recall.el`, with the step tests below. Where
the code and this document disagreed, the document is fixed in place rather than
quietly rewritten: *(corrected)* marks what it had simply got wrong before the
code was written — the digit-entry hook point, and a guard the stack cycle needs
— and *(revised)* marks a decision that was right as stated and later changed
on purpose: algebraic entry now feeds the ring, and recall may overwrite an
entry that came from the stack.

## Goal

Stop the defensive pattern of duplicating or storing an entry before a
calculation just in case the calculation mangles it. `M-p` / `M-n` walk back
through entries you typed and put one back, either into the edit session you are
in or onto the stack as a fresh entry.

## The dividing line

Two different losses hide inside "in case you screw up a calculation":

1. You typed something expensive, used it, mangled it. What you want back is
   *your source text*, in the unsimplified form you wrote it.
2. A *computed* result got consumed. It was never typed.

This feature is case 1 only. Case 2 belongs to `maf-timeline`, which already
records every stack state and pushes any past entry back
(`maf-timeline-insert`). A recall ring that tried to cover case 2 would be a
worse timeline: it would fill with every intermediate result, and values
re-rendered to text are lossy — the reason `maf-edit-commit` never reparses
untouched entries.

Consequence: **only brand-new entries feed the ring.** Not modifications of
existing ones, not results of commands.

## Confirmed design decisions

1. **Bare edit entries feed the ring.** An entry overlay with `maf-edit-val` nil
   (`modules/maf-edit.el:951`) was started from empty — already decidable at
   commit time, no new bookkeeping.
2. **Discards do not feed the ring.** Discarding means it. Recording therefore
   happens strictly at commit points, one per input path.
3. **Digit entries feed the ring**, even though they are cheap to retype.
4. **Algebraic entry (`'`) feeds the ring too.** *(revised after the first
   version landed; it was originally out as barely used and obviated by
   maf-edit.)* It takes the same rule as digit entry: an expression the command
   leaves on the stack as an entry of its own is recorded, one built out of what
   was already there (`' 2+$` consumes the top) is not.
5. **Contextual commits are out.** A number committed into the sub-formula at
   point (SPC) modifies an existing entry; so does a number consumed as a
   command's argument (`2 +`, `5 e`). Neither is a new entry.
6. **A ring item is a (TEXT . VALUE) pair.** Stack-mode recall pushes VALUE
   (lossless, no reparse); edit-mode recall inserts TEXT. This also settles the
   π case below without a format/reparse round-trip.
7. **Recall never reorders the ring.** Only newly typed entries feed it, so
   `M-p M-p M-p` lands on the same item every time instead of churning under
   you. Recording dedupes: an identical TEXT is deleted and re-pushed to front.
8. **No wraparound.** Running off either end stops with a message, as minibuffer
   history does.
9. **No numeric prefix argument.**

## Which digit entries

`maf-digit-start`'s cond (`src/minibuffer.el:662-700`) classifies every
termination already. Mapping decisions 3 and 5 onto it:

| branch | record? | why |
|---|---|---|
| `t` — RET / C-RET push | **yes** | the canonical new entry |
| `below` — S-RET, new entry mid-stack | **yes** | also a new entry |
| `maf--digit-contextual` — SPC / `n` | no | edits the sub-formula at point |
| `maf--digit-entry-handoff` — command key (`2 +`, `5 e`) | no | an argument, consumed immediately |
| `stringp val` — escaped to algebraic | **yes** | still an entry typed from nothing |
| `dots` — interval entry | no | a half-built object, not an entry |

*(corrected)* The two "yes" rows are **not** reachable by advising
`maf--digit-push`. That cond is only half of `maf-digit-start`: it runs when
point is on a sub-formula, and everywhere else — at home above all, the common
case — the command hands the entry to calc's own `calcDigit-start`
(`src/minibuffer.el:623-638`), which pushes without ever calling maf's push.

So the hook is an `:around` on `maf-digit-start` itself, which both routes pass
through. It compares the stack before and after: exactly one value inserted
means the entry became an entry of its own, and that value is what gets
recorded. Comparing rather than reading level 1 also survives S-`<return>`,
which rolls its push down to the level below point after the fact. The skips
are then `maf--digit-entry-handoff` (the arg push, whose pop-push would fail the
one-insertion test anyway) and an `incomplete` value mid-construction (the `..`
interval). An entry that escapes to algebraic on its own (`2*x` typed into a
digit entry) is recorded here, and the `'` command is covered by an advice of
its own (decision 4).

The one-insertion test is what carries the whole rule, so both entry commands
share it: `maf-recall--record-inserted`. It is also why `' 2+$` needs no test of
its own — consuming the top and pushing a result is not an insertion.

**TEXT for a digit entry is the formatted value, not the keystrokes.** The typed
string is a local of `maf-digit-start` and out of reach from the push, and
formatting is the more correct choice anyway: `maf-digit-pi` turns a typed `5`
into 5π, and a string recorded as `"ff"` under hex entry would not reparse in
another radix. Format with `math-format-flat-expr` (reparseable) rather than
`math-format-value` (display form). The visible consequence is that recall
offers the canonical form of a number rather than your literal keystrokes:
`.5` comes back as `0.5`.

## UX

### In a maf-edit session

`M-p` / `M-n` in `maf-edit-mode-map` replace the text of the entry point is in.

- *(revised after landing)* Any entry, not only a bare one. The first version
  refused on an entry that came from the stack, on the grounds that recall
  authors new entries rather than overwriting existing ones; overwriting one is
  in fact a thing worth doing, so it is allowed and the entry it displaces is
  **banked as the ring's newest item**.
- That banking is the one place something the stack held enters the ring, and it
  does not blur the rule the design rests on: it is there because *you* chose to
  overwrite that entry, and being able to get it back is what makes choosing to
  safe. It carries the entry's value along when the session had not touched it,
  so a later recall restores the object rather than a reading of its text.
  Nothing is banked for a bare entry — half-typed fragments stay out of the ring
  and the stash alone covers them.
- Banking happens at the start of the cycle, before the first replacement, so
  the entry is then showing ring item 0 and the cycle starts standing on it —
  otherwise the first `M-p` would replace the entry with what it already holds.
- Text typed before the first `M-p` is stashed as slot 0, so `M-n` back past the
  newest item restores work in flight (comint's rule).
- The replacement is one undo step.
- The cycle index resets when the entry text changes by anything but a recall.
- *(revised after landing)* **At home in a session** there is no entry to fill,
  so `M-p` opens a blank one at the bottom and the cycle runs in it — the same
  thing `M-p` means at home out on the stack. It reuses maf-edit's own opening
  gesture (`maf-edit--open-at-dot`, extracted from `maf-edit-add-entry` for the
  purpose) rather than a second copy of it. `M-n` at home opens nothing: there
  is no cycle to walk back through, and an empty entry left behind would be a
  surprise. Slot 0 for such a cycle is the empty text the entry started as, so
  walking back past the newest item empties it again and a commit then drops
  it — the stack ends up as it was.

### At home, in stack mode

`M-p` / `M-n` in `maf-mode-map`, no edit session involved.

- `M-p` pushes the newest item as a real stack entry **at home** — always at
  home, whatever level point was on.
- Repeated `M-p` / `M-n` *replace* that entry in place with the neighbouring
  ring item. `yank` / `yank-pop` semantics: any other command ends the cycle and
  the entry simply stays.
- *(corrected)* `last-command` alone is not enough to decide "still cycling".
  The cycle also remembers the value it put at level 1 and continues only while
  that value is still on top, so a press whose `last-command` says cycle but
  whose stack has moved on — undone, or changed by something that never ran as
  a command — pushes fresh instead of pop-pushing over an entry it does not
  own. Driving the keys from a keyboard macro reaches exactly that state, which
  is how it turned up.
- Point homes with a mark left behind, following the RET-push precedent. This
  matters because the entry can appear far from where point was.
- The whole cycle collapses to **one undo step**, so a single undo removes the
  recalled entry rather than walking back through candidates. Precedent:
  `maf--undo-amalgamate-digit-entry` (`core/maf-lib.el:256`).

## Architecture

A new module, `modules/maf-recall.el`, registered as `maf-recall`. It is
cross-cutting — two input paths feed it — so it cannot live in `maf-editplus`,
whose charter is keys inside an edit session. It packages neatly all the same:
two advices, two keymap entries, one toggle.

```
maf-recall--ring          list of (TEXT . VALUE), newest first
maf-recall-size           defcustom, 100 (matches maf-timeline-size)
maf-recall--record        dedupe by TEXT, push front, truncate
```

**Recording, edit path.** `:around` advice on `maf-edit-commit`: snapshot the
bare entries' texts from `maf-edit--overlays` *before* calling the original
(the session, and its overlays, are gone afterwards), then record only if the
call returned without signalling. A failed commit signals `user-error` and
leaves you in the session, so decision 2 falls out for free. VALUE is nil on
this path; stack-mode recall parses TEXT with `math-read-expr` on demand, which
is what commit does with that same text anyway.

**Recording, entry-command paths.** `:around` advice on `maf-digit-start` (see
the correction above) and on `calc-algebraic-entry`, both ending in
`maf-recall--record-inserted`: the one value the command inserted into the stack
becomes VALUE, and TEXT is its `math-format-flat-expr` rendering — flat form, so
`5 pi` is recorded as the reparseable `5 * pi`. The digit advice adds the one
check the stack cannot make for itself, skipping an entry that ended in a
command key (`2 +`), whose number is pushed as an entry before the command
consumes it. Recording is wrapped in a `condition-case` that reports and gets
out of the way: a working entry is worth more than a ring item.

The escape from a digit entry into algebraic goes through `calc-alg-entry`, not
`calc-algebraic-entry`, so the two advices never both fire on one entry.

**Bindings**, installed by the toggle and removed when it is off:

```
maf-mode-map        M-p  maf-recall-previous     M-n  maf-recall-next
maf-edit-mode-map   M-p  maf-recall-previous     M-n  maf-recall-next
```

Both keys are free in both maps today (`M-p`/`M-n` are bound only in the
timeline and formulas buffers' own major-mode maps).

**Pushing.** `calc-pop-push-record-list` with a `"rcl"` trail prefix — 0 popped
to start a cycle, 1 popped to replace during one, following the idiom in
`modules/maf-formulas.el:306`. The prefix also gives `maf-timeline` a sensible
label for the operation, since it takes the trail prefix when there is one
(`modules/maf-timeline.el:162`).

**Persistence.** `(with-eval-after-load 'savehist (add-to-list
'savehist-additional-variables 'maf-recall--ring))`. One global ring, not
per-buffer: `maf-persist` saves stacks per session, but typed text is worth
carrying across all of them.

## Edge cases

- **Empty ring.** `M-p` messages and does nothing, in both modes.
- **Cycle interrupted by an error** (a ring item that no longer parses under
  current input modes, on the nil-VALUE edit path): message, leave the cycle,
  leave the stack alone.
- **A recalled entry is itself committed again** through an edit session — it
  gets recorded like any other bare entry, moving to the front. Decision 7 is
  about *recall* not reordering; a fresh commit is a new authoring event.
- **`maf-edit-add-vector`** produces a bare entry like any other; `[]` committed
  untouched enters the ring, which is harmless and consistent.
- **Multi-line entries** need no special handling: `maf-edit--entry-text`
  (`modules/maf-edit.el:257`) is prefix-stripped and joined to a single line, so
  every TEXT is one line by construction.
- **Selections** do not block the stack-mode push; recall always acts at home.

## Implementation order

1. `modules/maf-recall.el`: ring, `maf-recall--record`, defcustom, module
   registration and toggle. No recording yet — verify the module loads and
   toggles cleanly.
2. Edit-path recording advice. Check the ring fills from bare entries only, and
   that a failed commit and a discard both leave it alone.
3. Digit-path recording advice. Check the table above branch by branch: RET and
   S-RET record, SPC / `2 +` / `5 e` / `'` / `..` do not.
4. Edit-session recall (`M-p` / `M-n`), slot-0 stash, and banking the entry a
   recall displaces.
5. Stack-mode recall: first push, then in-place cycling, then undo
   amalgamation.
6. `savehist` hookup.

## Tests

Step tests in `tests/`, per [tests/README.md](../../tests/README.md):

- `recall-record.el` — what feeds the ring: bare entry in, modified entry out,
  discard out, failed commit out, emptied entry out, dedupe to the front.
- `recall-digit.el` — the branch table: RET, C-`<return>` and the pi shortcut
  in; contextual commit and command-key handoff out.
- `recall-algebraic.el` — the `'` path: an expression typed from nothing in,
  one that consumes the stack top (`' 2+$`) out.
- `recall-edit.el` — cycling inside a session: replacement, slot-0 stash,
  typing over a recall starting a fresh cycle, overwriting a stack-backed entry
  and banking what it displaced, opening an entry at home, ends of the ring.
- `recall-stack.el` — home cycling: push at home from a mid-stack point,
  in-place replacement, one undo removes the whole cycle, mark left behind.

A cycle only lives inside one `execute-kbd-macro` run — across separate runs
the macro machinery decides `last-command`, not the test — so each cycle and
whatever interrupts it are delivered in one macro, `C-b` standing in for "the
user did something else".

## Docs

- Check off the TODO in `docs/maf.org` and note the module.
- Module description string for the modules manager, in the register call.
- Header commentary in `maf-recall.el` carrying the "what you typed vs what the
  stack held" split, which is the thing a reader needs to not blur this back
  into the timeline.
