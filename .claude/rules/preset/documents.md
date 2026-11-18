---
paths:
  - "Proposals/**"
  - "Papers/**"
  - "Research/**"
  - "Documents/**"
  - "docs/**"
  - "**/*.outdated.md"
  - "**/*.pdf"
  - "**/*.odt"
  - "**/*.docx"
  - "**/*.pptx"
  - "**/*.xlsx"
---

# Document classes

| Folder | Class | Purpose |
|---|---|---|
| Named in `CLAUDE.md` | Authoritative | The project's own description, decisions, and methods. The source of truth |
| `Proposals/` | Proposal | Asks. Sets out a decision's options and evidence without deciding. Preserved unchanged after the decision, for backtracking |
| `Papers/` | Paper | Explains. An open statement of what happened, or a description of what something does |
| `Research/` | Internal cache | Working notes, source cache, briefs. Optimised for resuming work; not public-facing |

- A decision taken on a proposal goes to the project's decision record (named in `CLAUDE.md`),
  never back into the proposal. Do not edit a proposal once it is decided.
- A paper states facts sourced to the repository or cited material; it does not weigh options.
- Proposals and papers use IEEE numbered references (the `write-proposal` skill renders them).

# Complex documents

ODT, PDF, DOCX, PPTX, XLSX, and other binary formats are never regenerated or edited in place. When
their content goes stale, leave the file untouched and maintain a sibling `<name>.outdated.md`
that marks the document outdated and lists, under `Outdated` and `Up next`, the items that no
longer hold and the changes pending. The editable
Markdown documents stay the source of truth; the binary document is corrected only when its owner
deliberately regenerates it.

## Enforced by

`deny` entries on `Edit` for the binary formats.
