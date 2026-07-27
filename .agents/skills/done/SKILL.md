---
name: done
description: Answer whether a task or feature is done, in plain simple words. Use when asked "is this done?", "did it work?", "is X finished?", or invoked as `/done [what]` — the answer is a short verdict, not a report.
---

# Is it done?

Say whether the thing is done. Nothing else.

## What to check

The subject is whatever follows `/done`. With no argument, it is the
last thing worked on in this session.

Check it for real before answering — do not answer from memory of what
you wrote:

- Code changes: the code is in the file, and the file is loaded in the
  dev instance (`/emacs`).
- A command or behavior: run it in the dev instance and look at the
  result. See `docs/memory/piloting-emacs.md`.
- Tests: run them.

If checking would take a long time, say what you did check and what you
did not.

## How to answer

Start with the verdict on its own line: `Done.` or `Not done.`

Then at most two or three short sentences. If done, say what works. If
not, say what is missing or broken, and nothing about how you might fix
it unless asked.

Rules for the wording:

- Short common words. No jargon, no Lisp symbols unless naming one is
  the only way to be clear.
- No preamble, no summary of the work, no bullet lists, no code blocks.
- No hedging. If it is half done, that is `Not done.` plus the reason.
- Never say done for something you did not check.

## Examples

### [EXAMPLE 1] /done

```
Done.
The new command works in the dev instance and the tests pass.
```

### [EXAMPLE 2] /done maf-frac binding

```
Not done.
The command exists but no key is bound to it yet.
```

### [EXAMPLE 3] /done selection fix

```
Not done.
It works on a whole entry but still drops the selection on a subexpr.
```
