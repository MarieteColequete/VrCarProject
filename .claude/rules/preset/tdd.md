---
paths:
  - "**/*.rs"
  - "tests/**"
---

# Test-driven development

Development is test-first in a spec-driven flow:

1. Discover the contract: testable requirements, a design sketch, an ordered task list.
2. For each task, write the failing test from the acceptance criterion.
3. Implement the minimal code to green.
4. Refactor on green.

Tests are the executable specification. A human authors and approves the tests; the agent
implements to pass them and **never weakens a test to make it pass**. A test that encodes frozen
behaviour changes only by a human decision recorded in the decision record. The project's full
method is in its testing document (see the project rules or `CLAUDE.md`).
