---
paths:
  - "Research/**"
---

# Research cache

`Research/` is internal working material and cold storage, one folder per topic. It exists so work
can resume after a session reset without rereading sources.

- `brief.md` is the resume point: the open questions with options, evidence ids, dependencies,
  status (OPEN or DECIDED), and the author's decisions once taken. Read it first.
- `sources.md` is the source cache. Every fact a proposal or paper cites is logged there first,
  with an id, title, URL, access date, paraphrased facts, and a verification state:
  **V** read in the primary source, **V2** confirmed by two independent secondary sources,
  **U** unverified and not citable.
- Quotes stay under 15 words; everything else is paraphrased.
- `<id>.keyed.md` holds a proposal's source with `[@key]` citations before rendering.
- `README.md` at the root indexes the topics and lists open flags for the author.

The `research-topic` skill runs the procedure.
