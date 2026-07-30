# sandbox

Scratch space for work in progress. Files here are drafts: a place to
drive a command while it is still being worked out, before it has a
shape worth keeping.

They are written in the same `maf-step` form as the suite (see
`tests/README.md`), which makes them easy to mistake for tests. They are
not. **Nothing sweeps this directory**, so a file here rots quietly — it
may drive a command that has since been renamed, or assert an answer the
command no longer gives. Never cite a sandbox file as evidence of how
maf behaves today without running it first.

The way out is `tests/`: once a draft passes against current `main`,
states its expectations, and covers something no other file does, it is a
test and belongs there. Move it with `git mv` so there is one home per
check.

What is left here is either still being written or has been superseded
and not yet thrown away. If a file fails and the behavior it describes is
gone, it has no further use — delete it rather than leaving it to be
rediscovered.
