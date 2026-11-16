# Writing

These apply to every piece of prose that lands in the repository: documentation, proposals, papers,
commit messages, changelog entries, and doc comments.

- **EU English.**
- **No en dashes or em dashes.** Use a comma, slash, semicolon, or colon, or restructure the
  sentence. Write ranges with "to" ("1 August to 18 December").
- **Public-facing.** A document stands on its own for a reader who was not in the room. That does
  not mean non-technical. Specifically:
  - Do not reference the conversation, the prompts, or the process that produced the work.
  - Do not address the reader or hand them recommendations or next-step summaries ("you should",
    "I suggest", "what we did"). Documentation describes the thing, not the task of building it.
  - No puns, lore in-jokes, or asides. State facts plainly.
  - Say each fact once. Do not restate it in different words to pad a section.
- Internal working notes (the research cache) may be dense and bulleted, but follow the dash rule.

## Enforced by

The dash check hook before and after each Markdown edit, and the stop gate when a turn ends. The
`doc-lint` skill checks a set of files on demand.
