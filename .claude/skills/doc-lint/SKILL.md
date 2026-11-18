---
name: doc-lint
description: Check Markdown files against the writing rule (dashes, reader-addressing phrases). Use before proposing a commit that touches documentation, or when asked to check docs.
argument-hint: "[file ...]"
allowed-tools: Bash(sh *bin/preset doc-lint*)
compatibility: Requires the preset tool (.claude/bin, built for Linux and Windows on x86_64) and git.
---

Run the checker on the given files, or with none on every Markdown file git lists under the
current directory, ignored ones left out (from the root, the whole repository):

```
sh "${CLAUDE_SKILL_DIR}/../../bin/preset" doc-lint $ARGUMENTS
```

- **Errors** (en or em dashes) must be fixed: replace with a comma, slash, semicolon, colon, or
  "to" for ranges, or restructure the sentence.
- **Warnings** (phrases such as "you should" or "as discussed") are reviewed, not fixed blindly:
  they are legitimate when quoted as examples, as in the writing rule itself. Fix the ones that
  address the reader or refer to the process in public-facing documents.
- Do not edit preserved proposals in `Proposals/`, or complex binary documents; report findings in
  them instead.
- Report the summary line and what was changed.
