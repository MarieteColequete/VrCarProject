---
paths:
  - "CLAUDE.md"
  - ".claude/rules/preset/**"
  - ".claude/skills/**"
  - ".claude/agents/**"
  - ".claude/preset.json"
---

# Agent configuration: preset and project files

The configuration is split into **preset** files, shared across the author's ecosystem of
repositories, and **project** files, owned by this repository. Preset files name no project; where
they need a project fact they refer to `CLAUDE.md`. Preset files are replaced as a whole when the
preset is updated (`preset update`, which says how a newer preset is checked first), so they are
never edited locally: `.claude/preset.json` records each one as installed, and an update stops at
one that was changed. To change preset behaviour, change the preset itself, not a repository's
copy.

- **Preset-owned**: `.claude/rules/preset/` (each rule's `paths:` says when it loads); the skills
  `adopt-preset`, `doc-lint`, `host-setup`, `hosting`, `land`, `propose-release`, `release`,
  `research-topic`, and `write-proposal`; `.claude/bin/`, the preset's tool (`preset help`);
  `.gitlab/ci/`, the signature check; the preset's entries of `.claude/settings.json` and lines of
  `.gitignore`; and `.claude/preset.json`, the record of what is installed.
- **Project-owned**: `CLAUDE.md`; `.claude/rules/project/` (versioning always, releasing with the
  changelog, releases read by the `release` skill, implementation by path); the `consistency`
  agent and its memory; `.claude/project.json` (`preset help project`); the project's entries of
  `.claude/settings.json`, after the preset's; `.gitlab-ci.yml`; and `.allowed_signers`.

## Extending

- A project rule: a file under `.claude/rules/project/`, with `paths:` frontmatter when it applies
  only to some files, and an "Enforced by" line naming any settings entries it adds.
- A project skill or subagent: a new directory under `.claude/skills/` or a file under
  `.claude/agents/`, with a name no preset file uses.
- Context that is needed only for some work goes in a path-scoped rule or a skill, not in an
  always-loaded rule: every always-loaded byte is paid again by each subagent.
- A skill names no `model`: a model other than the session's misses the whole prompt cache for
  that turn. Model and effort belong on subagents, which run in a cache of their own.
- A skill or agent description is one sentence with its triggers; every session loads it.
- Knowledge specific to one purpose-defined subagent goes to its own project memory
  (`memory: project`, under `.claude/agent-memory/<name>/`).
