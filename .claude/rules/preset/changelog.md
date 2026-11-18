---
paths:
  - "CHANGELOG.md"
  - "**/CHANGELOG.md"
---

# Changelog

The changelog lists, per version, the changes a consumer meets. Usage belongs in the README and
rationale in the commits; neither goes here, and neither does a list of commits.

- Newest version first, headed `## v<version> - YYYY-MM-DD`.
- At most one notice per version, a single sentence, for example for a first release.
- Categories in this order, empty ones left out: `### Changed`, `### Added`, `### Removed`,
  `### Fixed`.
- One line per change, imperative and readable without its heading; breaking changes first in
  their category, prefixed `**Breaking:**`.
- When drafting, read only the newest entry.

## Versions

- Each commit landed on `dev` is titled `v<MAJOR>.<MINOR>.<PATCH>[-<stage>] - <Title Case Summary>`,
  a short Title Case noun phrase after a spaced hyphen, with its dated entry here, which the
  landing checks.
- Semantic Versioning 2.0. State why a bump is major, minor, or patch when it is not obvious.
- Hosted CI on merge requests to `dev` and `main` is the authoritative gate where the project has
  one; the gates run locally on the working branch before the request is opened.
