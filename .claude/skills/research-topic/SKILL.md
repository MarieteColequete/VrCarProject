---
name: research-topic
description: Research a question into the research cache (Research/<topic>/), which survives session resets. Use to research or compare options, cache a long source, or resume research.
argument-hint: "<topic>"
---

Research **$ARGUMENTS** into `Research/<topic>/`, using a short kebab-case topic folder.

1. **Resume first.** If `Research/<topic>/brief.md` exists, read it, then `sources.md`, and
   continue from the recorded state. Do not redo research that the cache already holds.
2. **Rehydrate on the project.** Read the parts of the project's authoritative documents and
   decision record (named in `CLAUDE.md`) that bound the question, and note which decisions
   constrain it.
3. **Gather sources, primary first.** Specifications, official documentation, and source code
   before blogs or summaries. Record each in `sources.md` in the format of the research-cache rule,
   which loads with the first file in `Research/`. Verify any claim a summary tool returns against
   the source text where possible, since summaries can invent details. Note contradictions with
   existing project documents explicitly, because they are flags for the author.
4. **Write the brief** as the rule describes, with the findings that drive the design and an empty
   "Author decisions" section.
5. **Index it.** Add or update the topic row and any open flags in `Research/README.md`.

Nothing here decides; the author decides. A cache ready to become a proposal is the author's cue
to run `/write-proposal`.
