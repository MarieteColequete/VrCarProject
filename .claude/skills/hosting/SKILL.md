---
name: hosting
description: Check the hosting service against the settings the preset requires, area by area (merge requests, pipelines, CI security, protection, account, audit), and apply what differs on order.
argument-hint: "[--apply] [--verbose] [--only <area>]"
allowed-tools: Bash(sh *bin/preset hosting*)
compatibility: Requires git and glab signed in as a maintainer.
disable-model-invocation: true
---

1. Check, which changes nothing: `sh "${CLAUDE_SKILL_DIR}/../../bin/preset" hosting`, with any
   `--verbose` (lists the `ok` findings too) or `--only <area>` (`merge_requests`, `pipelines`,
   `ci_security`, `protection`, `account`, `audit`) of **$ARGUMENTS**. Each area prints its
   counts and every finding that is not `ok`: `differs` (`name: is → wants`), `missing`, `held`
   (the pipeline requirement waits for `.allowed_signers` on `dev` and `main` and
   `.gitlab-ci.yml` on `dev`), `refused` (fix in the web interface), `warning`, `info` (audit).
   The closing line says what `--apply` would set and what is left to the author.
2. Only when **$ARGUMENTS** includes `--apply`, or the author orders it after seeing the check,
   run it again with `--apply`: changing the service is an outward action that needs that order.
   Account and audit findings are never applied; they are the author's to fix.
3. Report what was set, what failed with the service's reason, and what was held, refused, or
   left to the author. A failure is not worked around (the git-workflow rule): no direct API
   call in place of the check.

## What the service enforces

The required settings are in `<provider>/settings.json` beside this skill, by area. Without push
rights a direct push to `dev` or `main` is refused by the server; the landing still works, as it
moves the branch through the merge request. Maintainers can still delete a protected tag in the
web interface or the API, so the command guard denies the agent that form.

Push rules, which could reject unsigned commits, are a paid feature and never cover tags, so the
signature check runs in CI and a merge needs a passing pipeline: `.gitlab/ci/signatures.yml` runs
`verify-signatures.sh` on requests into `dev` and `main` and on `v*` tags, against
`.allowed_signers` read from a protected branch (the target, or `main` for a tag), never from the
change under test. `dev` and `main` run no pipeline of their own: they only fast-forward to a
request's head, which its pipeline verified and `preset land --prepare` made, so a request runs
one pipeline. A branch without the file blocks requests into it: the first request into each
branch brings it and fails the check, so the requirement is held until then (step 1), and where
it is already on, the author lifts it for that one landing. A request can still change the
pipeline, so the check catches mistakes; the landing's own checks and review remain.
