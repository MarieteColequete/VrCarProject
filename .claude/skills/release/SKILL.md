---
name: release
description: Explain or prepare a release; use when asked to release, or about releases.
---

`main` holds stable snapshots, each a merge request from `dev` with a signed tag (the git-workflow
rule). Which snapshots are releases, and what releasing one involves, the project defines in
`.claude/rules/project/releases.md`.

1. **Read the releases rule.** If it is missing or still carries `{{...}}` slots, say that the
   project has not defined releases yet, and stop.
2. **A question about releases** is answered from the rule, naming it.
3. **An order to release**: name the tagged snapshot the rule's definition selects (`git log main
   --decorate`; `git tag -l` asks), list the rule's steps for it, and draft the texts they need (release notes and
   the like). Present the plan and wait. Each outward step (a tag, a push, `glab release`) runs only
   on the author's explicit order for it, and a failure stops for the author (the git-workflow
   rule).
