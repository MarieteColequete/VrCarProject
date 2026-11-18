---
paths:
  - "CHANGELOG.md"
---

# VrCarProject version step and merge requests

Loaded with the changelog and read by the `propose-release` skill; the branch and commit rules
are in the versioning rule.

## Versions and the changelog

- The project version (`vX.Y.Z-alpha`) and `CHANGELOG.md` change once per merge request,
  as the branch's last step: a `feat/` branch bumps the minor, a `fix/` or `hotfix/` branch the patch, and the
  version is the new changelog entry's heading, since no manifest carries it. A breaking change bumps the minor whatever its
  prefix while the major is 0.
- The changelog entry is written before review, in the changelog rule's format.
- Tags are made only when `dev` is merged into `main`, so versions between those merges carry no
  tag by design.

## Merge requests into dev

- Opened as a draft, and updated after each later commit, by the landing's prepare step:
  `sh .claude/bin/preset land --prepare --title '<title>' --description '<text>'` (without the two
  options once the request exists). It squashes the branch onto `dev` into the one signed commit
  that lands and pushes it as the request's head, so the request's pipeline tests exactly what
  lands and the landing pushes nothing.
- The title is `vX.Y.Z-alpha - Name`, the name in Title Case, which the landing checks. The
  description becomes the landed commit's message: a
  single short paragraph of prose, three to five sentences, that says what the update is about and
  names its overall changes as a user meets them. No internals, no bullet lists, no second
  paragraph, no verification line.
- Once the author marks it ready in the web interface, it lands with the `land` skill: one signed commit,
  fast-forwarded onto `dev` through the request, which then shows as merged.

## Merge requests into main

- Opened as a draft:
  `glab mr create --draft --source-branch dev --target-branch main --title 'Snapshot vX.Y.Z-alpha' --description '<text>'`.
- A merge request from `dev` into `main` brings a stable snapshot: `dev`'s head, which is a version
  commit. Its title is `Snapshot vX.Y.Z-alpha`, naming that version.
- It lands with the `land` skill: `main` fast-forwards to `dev` through the request, never squashed, and
  the commit gets a signed, annotated tag `vX.Y.Z-alpha` with the message
  `YYYY-MM-DD - <commit title>`.
- Whether a snapshot is also a release is decided by the releases rule, read by the `release`
  skill; a merge into `main` is not by itself a release.

## Enforced by

None beyond the preset git-workflow entries. The landing and the merge requests need GitLab and
are inactive while the project is on GitHub (`CLAUDE.md`, Hosting).
