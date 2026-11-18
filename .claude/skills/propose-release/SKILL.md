---
name: propose-release
description: Draft working-branch commits, the version step, and the merge request text, without staging or committing. Use when work is ready to record or a branch may be ready to merge.
---

Prepare, never perform. Staging, committing, pushing, and opening merge requests happen only on the
user's explicit instruction in that moment (the git-workflow rule); this skill ends by presenting
the proposal and waiting.

1. **Inspect** the working tree read-only: the current branch, `git status --short`,
   `git diff --stat`, and the diffs of the changed files. Note untracked files, and name any that
   look like they are not part of the work.
2. **Check the branch** against the project's versioning rule (`.claude/rules/project/`). Work is
   committed on a working branch off `dev`, never on `dev` or `main`; if the tree is on the wrong
   branch, propose the branch (prefix and slug) first.
3. **Group** the changes into working-branch commits, each with a single purpose, titled with the
   branch-local version the project rule gives (`X.Y-<branch> - Title Case`), continuing the
   numbering from the branch's existing commits.
4. **Draft the version step** when the branch is ready to merge, after reading
   `.claude/rules/project/releasing.md`: the next project version after `dev`'s, the changelog
   entry, and the merge request title and description in that rule's shape. Write the changelog
   entry into the file only if the user asks; otherwise show it. Where the rule names no other
   command, `sh "${CLAUDE_SKILL_DIR}/../../bin/preset" version minor --dry-run` (or `patch`) shows
   the next version and the manifests it would set, without changing them.
5. **Present** the commits with the files each covers and the full messages, the version step, and
   the merge request text, then stop and wait. On the go-ahead, stage exactly the listed files (no
   `git add -A`) and commit with the agreed messages; pushing, the merge request, and landing are
   separate orders. A request into `dev` is opened or updated with `preset land --prepare` (the
   releasing rule), never with a plain push.
