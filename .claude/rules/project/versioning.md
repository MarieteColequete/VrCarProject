# VrCarProject branches and commits

The version step and merge requests are in the releasing rule; releases in the releases rule.

## Branches

- `dev` takes one commit per merged change.
- All work happens on a working branch off `dev`, named with a prefix and a lowercase slug:
  `feat/` for new behaviour, `fix/` for a correction, and `hotfix/` for an urgent correction.
- The commit message check is switched on once per clone: `sh .claude/bin/preset hook install`.

## Commits on a working branch

A working-branch commit title is `X.Y-<branch> - Title Case`, the branch-local version: a
patch-sized step raises `Y`, a minor-sized step raises `X` and resets `Y`, starting at `0.1` or
`1.0`. These commits never touch the project version or the changelog. A number is
used once: the last commit is amended with `sh .claude/bin/preset amend`.
