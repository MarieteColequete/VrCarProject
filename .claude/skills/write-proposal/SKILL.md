---
name: write-proposal
description: Write a decision proposal (options and evidence, no verdict) from the research cache into Proposals/, with IEEE citations rendered by the preset tool, then review it. Use when a researched design or tooling question is ready to be put to the author.
argument-hint: "<topic> <Pnn> <Title>"
allowed-tools: Bash(sh *bin/preset renum*)
compatibility: Requires the preset tool (.claude/bin, built for Linux and Windows on x86_64).
disable-model-invocation: true
---

Write proposal **$ARGUMENTS**. A proposal asks: it sets out the options for one decision and does
not decide. It is preserved unchanged once decided.

## Before writing

- The topic must have a research cache (`Research/<topic>/brief.md` and `sources.md`). If it does
  not, run the `research-topic` skill first.
- Every factual claim must trace to a `sources.md` entry in state V or V2.
- Pick the next free proposal number from `Proposals/README.md`; the first proposal, P01, creates
  that index (id, title, status, decision).

## Structure

A header table (proposal id, version, date, author, status, related decisions), then:

1. Abstract (about 150 words).
2. Introduction: problem, scope (and what is out of scope), contribution, structure.
3. Background and constraints: the decisions that bound the space, defined terms.
4. Requirements and criteria: each drawn from the problem and labelled universal, project-specific,
   or contestable.
5. Survey of precedents, each on its own terms, with a factual table and no verdict column.
6. The design space, one subsection per question: options, precedents, bearing on the criteria.
7. Synthesis: dependencies between questions, options that revise existing decisions (a table),
   and coherent configurations, each defined on its own terms.
8. Limitations. 9. Conclusion, conditional on the criteria.
10. References. Appendix with worked examples where useful.

Follow the evaluation-and-comparison rule throughout: neutral names, every option's case stated as
strongly as its costs, no option framed as the answer.

## Citations and rendering

Write the source as `Research/<topic>/<Pnn>.keyed.md` using `[@key]` citations in the text and a
`## References` section whose lines read `[@key] <IEEE entry>`. Every listed key must be cited and
every cited key listed. Render with:

```
sh "${CLAUDE_SKILL_DIR}/../../bin/preset" renum < Research/<topic>/<Pnn>.keyed.md > Proposals/<Pnn>_<Title>.md
```

The tool numbers citations in order of first appearance, rewrites the reference list to match,
and fails on a cited key with no entry. The appendix (from `## Appendix A`) is left untouched.

## Review and hand-over

1. Run the `doc-lint` skill on the rendered file.
2. Run the project's read-only review subagent (named in `CLAUDE.md`) on it: drift from the
   invariants, mischaracterised decisions, any lean toward a verdict, internal consistency. Fix in
   the keyed source and re-render.
3. Add the row to `Proposals/README.md` and update the topic's `brief.md` status.
4. Hand it to the author. The decision goes to the project's decision record (named in
   `CLAUDE.md`), never back into the proposal.
