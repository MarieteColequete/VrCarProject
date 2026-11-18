---
paths:
  - ".claude/settings.json"
  - ".claude/project.json"
  - ".claude/bin/**"
---

# Enforcement map

Rules instruct; `.claude/settings.json` and the hooks enforce. Each preset entry belongs to the
rule below, by the start of its pattern. An update replaces the preset's list entries as a whole
and keeps the project's, which follow them and are named on the "Enforced by" line of the
project rule that owns them; a single value the project changed is kept and named. `ask` and
`deny` entries exist for `Bash` and `PowerShell` alike; `allow` for `Bash` only. A trailing ` *`
matches the bare command too, and an `ask` outranks any `allow`.

| Owner | Decision | Patterns starting |
|---|---|---|
| git-workflow: history, branches, configuration, the hosting service, the landing | `ask` | `git `, `glab `, `sh *bin/preset ` |
| git-workflow: signing and hooks, direct pushes to `dev` and `main` | `deny` | `git ` |
| git-workflow: inspection | `allow` | `git ` |
| configuration: self-protection | `ask` | `Edit(/.claude/`, `Edit(/.gitlab`, `Edit(/.allowed_signers)`, `Edit(/.git/` |
| enforcement: credentials | `ask` | `Read(` |
| documents: complex documents | `deny` | `Edit(*.` |
| rust: gates | `allow` | `cargo ` |

- Patterns match a command as written, so `git -c *` and `git -C *` ask, both spellings of
  `gpgsign` are denied, and `git config *` asks for reads too. They are a backstop; the rules are
  the authority, and the command guard reads what they miss (`preset help guard`).
- `blockWritesOutsideWorkingDirectories` keeps the file tools inside the working directories
  (Claude Code 2.1.314 or newer); `true` from any settings file holds, and a directory the work
  needs is added with `additionalDirectories`. `attribution` is empty and
  `includeGitInstructions` off (git-workflow).
- Every hook is the preset's tool, through its launcher with a timeout (`preset help hook`). The
  command guard blocks the command when it cannot run (Claude Code 2.1.295 or newer; `preset
  doctor` checks both versions). A settings change that would leave the guard out is refused.
  Settings changes, auto mode's denials, and instruction loads are recorded in
  `preset/events.log` in the git directory.
- The project data's format is `preset help project`.

## Where the settings do not run

The permission entries and the hooks are read from this repository's `.claude/settings.json` by
Claude Code on the author's machine, and by a cloud session that holds this one repository. In a
cloud thread of a project, and in a cloud session with several repositories, they are not applied:
no entry asks or denies, and the command guard, the dash checks, and the stop gate do not run.
What still holds there is on git's side: signed commits, the commit-msg hook where installed,
the pipeline's signature check, and the protected branches. Work that changes history is
therefore done where the settings run.
