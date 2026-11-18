---
name: land
description: Land a ready merge request through the request, so it is recorded as merged: into dev as one commit signed with the maintainer's key, into main as a snapshot with its signed tag.
argument-hint: "[merge request number]"
allowed-tools: Bash(sh *bin/preset land*)
compatibility: Requires git with a signing key and glab signed in.
disable-model-invocation: true
---

Invoking this skill is the order to land. Land **$ARGUMENTS** (or the open merge request of the
current branch):

1. Run the plan alone and show it:

   ```
   sh "${CLAUDE_SKILL_DIR}/../../bin/preset" land --dry-run $ARGUMENTS
   ```

2. If the plan passes, land:

   ```
   sh "${CLAUDE_SKILL_DIR}/../../bin/preset" land $ARGUMENTS
   ```

3. Report the landed commit, or the landing's failure and the state it left, then stop. A failure
   is never worked around (the git-workflow rule): no direct push to `dev`, no rebuilt tool, no
   manual merge.

The landing refuses a draft: the author marks the request ready in the web interface first. A
head made by `preset land --prepare` lands as it is; any other is squashed and pushed first, as
the plan reports. A request from `dev` into `main` is a snapshot, complete only once its signed
tag is on `main`. `preset help land` has the rest.
