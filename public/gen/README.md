# Site data generators

The site under `public/` is static HTML, CSS and JS. Its two data files are
generated, and both generators are run from the repository root.

- `crawl-commits.py` walks every commit and writes `public/data/commits.json`
  and `commits.js`: per commit the hash, date, subject, body, parents, files
  added, modified and deleted, a size stat, the top-level areas touched, the
  commands added (new `maf-defcmd` forms, new mafcmd table rows, and new
  interactive `defun`s found in the patch), modules and step tests added, the
  tag if any, and a type: addition, change, fix, refactor, docs, tests, revert,
  merge, or note (the file-list note commits). A summary counts by type and by
  month.

      python3 public/gen/crawl-commits.py

- `export-bindings.el` asks a live Emacs with maf loaded for every profile's
  groups, as the `*maf-keys*` buffer renders them, and writes
  `public/data/bindings.json`; `finish-bindings.py` then normalizes it and emits
  `bindings.js`.

      emacsclient -s '#emacs' --eval '(load-file "public/gen/export-bindings.el")'
      python3 public/gen/finish-bindings.py

The pages load the `.js` files, so they work when opened straight from disk.
