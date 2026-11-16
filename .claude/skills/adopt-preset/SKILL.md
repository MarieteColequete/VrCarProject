---
name: adopt-preset
description: Fill the project-owned skeleton files that `preset init` wrote, replacing every {{...}} slot from the repository and the author's answers, then remove the slots and their adopt guidance comments. Use once, right after `preset init`.
argument-hint: "[file ...]"
allowed-tools: Bash(sh *bin/preset adopt*) Bash(sh *bin/preset host)
compatibility: Requires the preset tool (.claude/bin, built for Linux and Windows on x86_64) and git.
disable-model-invocation: true
---

Adopt the template in this repository, or only in the files given: **$ARGUMENTS**

Every value a project supplies is a `{{NAME}}` slot, and the guidance for it is an HTML comment
that starts with `<!-- adopt:` directly above or beside it. Preset files carry neither.

0. **Machine.** `sh .claude/bin/preset host` checks that this machine can do the work (podman,
   distrobox, and the development boxes). Report its problems to the author; setting the machine
   up is the `host-setup` skill, run when the author asks.
1. **Inventory.** List what is left to fill, each slot and each guidance comment with its file
   and line:

   ```
   sh .claude/bin/preset adopt
   ```

   With file arguments it reads only those files, and `--json` prints the list as data.

2. **Derive before asking.** Read the repository first: the README, manifests (`Cargo.toml`,
   `package.json`, and the like), `CONTRIBUTING.md`, the documentation folder, CI files, `git log`,
   and the remotes. Fill every slot the repository answers.
3. **Ask for the rest.** Put the remaining questions to the author with the question tool, at most
   four at a time, each with the options the repository suggests. Decisions are the author's: the
   decision record, the MSC document, the branch prefixes and version stage, the gate command, and
   what counts as drift for the reviewer.
4. **Fill and clean.** Replace each slot with its value and delete its `<!-- adopt: ... -->`
   comment. Remove a skeleton item that does not apply instead of leaving it empty, and remove a
   whole section when none of it applies. Keep the "Enforced by" lines true to the settings.
5. **Project data.** In `.claude/project.json`, list under `commands` each project tool that wraps
   other commands or acts on the outside world (`program`, the subcommands to `ask` for, and
   `ask_with` for subcommands that ask only with a flag), and set `gate` to one fast check command,
   or leave it `null`. Set each other key whose default does not fit (`preset help project`):
   `changelog`, `version`, `branches`, `hosting`, `host`. Add the matching `allow` and `ask` entries to `.claude/settings.json` after
   the preset entries, and name them in the project rule that owns them.
6. **Verify.** `sh .claude/bin/preset adopt` exits 0, which also means `.claude/project.json`
   and `.claude/settings.json` parse as JSON; the `doc-lint` skill reports 0 errors.
7. **Report** the filled files and the answers taken, then propose the commit with the
   `propose-release` skill. Nothing is staged or committed here. Once the configuration is pushed,
   the `hosting` skill checks the hosting service settings the landing flow needs; they are
   applied before the first landing, which refuses a project that would add merge or squash
   commits, and on a new project `main`'s default protection is changed in the web interface.
