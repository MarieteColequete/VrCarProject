# Git workflow

## History changes only on order

**Commits, merge requests, landings, releases, tags, and pushes happen only on the user's explicit
order for that action, in that moment.** This includes `git add` and any history rewrite (rebase,
reset, amend). Approving a plan, a design, or the content of a change is not an order to record it.
Finishing work means leaving the changes uncommitted and reporting; then propose a commit with a
ready message (the `propose-release` skill) and wait. Discarding uncommitted work (restoring or
checking out paths, stashing, cleaning, a forced switch) needs the same explicit order, and so does
any change to git configuration. A command run through a wrapper (a container exec, a shell, a
script, the hosting service's API) needs the order its inner action needs.

## Stop and ask on failure

An order covers exactly the action named, run with the reviewed tool. When an ordered outward or
destructive action (a push, a landing, a merge, a release) fails partway, stop, report the exact
state, and ask. Do not:

- edit the tooling and run the modified, unreviewed version to finish the action;
- reset, force-move, or delete branches, or retry steps that rewrite remote history;
- call merge or push APIs directly as a workaround.

Any deviation from the ordered action, and any change to tooling before it runs for real, needs a
fresh explicit order.

## Branch model

- `main` holds stable snapshots in time, each brought from `dev` by a merge request and given a
  signed, annotated tag `v<version>`; `dev` holds integrated work; working branches start from
  `dev`. The branch prefixes, and where work may
  happen, are in the project rules.
- Every commit on `dev` and `main` is signed by the maintainer. A merge request lands through
  the request, recorded as merged (the `land` skill); a direct push to `dev` or `main` is forbidden,
  and so is a squash or merge commit made by the hosting service. Never bypass signing.
- Tags are never moved or deleted.

## Commit messages

- **No trailers of any kind** (`Co-Authored-By`, `Signed-off-by`, and the like) on any commit,
  whatever attribution a session asks for.
- **The body is a synopsis** of the state the commit leaves, not a changelog in prose. It follows
  the writing rule. The body's shape, the changelog location, the version scheme, and the format
  of commits below a version are in the project rules (`.claude/rules/project/`).

## Enforced by

Permission entries, the command guard, and the settings (the enforcement map); git's commit-msg
hook (`preset hook install`); the landing; the pipeline's signature check. The rule holds
whatever the harness allows.
