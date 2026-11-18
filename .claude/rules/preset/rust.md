---
paths:
  - "**/*.rs"
  - "**/Cargo.toml"
  - "clippy.toml"
  - "rust-toolchain.toml"
---

# Rust conventions

- **Functional-first.** Behaviour is `fn(input) -> output`, not `&mut self` methods carrying hidden
  state. Move what you transform, borrow what you only read; the callee never clones on the
  caller's behalf. Closed sets are an `enum` plus exhaustive `match`; reserve trait objects or
  `FnMut` for genuinely open, user-extensible sets. Errors are values (`Result` and `?`), no panics
  as control flow. Keep `Rc<RefCell>` / `Arc<Mutex>` out of the pure contract and logic layers.
- **Platform code behind one seam.** OS-specific code lives behind a single seam, grouped by
  target; extend the seam rather than scattering `#[cfg]` through the tree. Target-specific
  dependencies go under a member's `[target.'cfg(unix)'.dependencies]` /
  `[target.'cfg(windows)'.dependencies]`.
- **Dependency hygiene.** Hoist shared crate versions into `[workspace.dependencies]` in the root
  `Cargo.toml`; member crates use `<dep>.workspace = true`. Prefer `cargo add` over hardcoding
  possibly-stale versions. The toolchain is pinned in `rust-toolchain.toml`.

## Doc comments

Formal and enforced by the `[workspace.lints]` table in the root `Cargo.toml` plus `clippy.toml`:

- Every item carries a doc comment, private items and fields included, opening with a one-sentence
  summary of what the item is or does.
- Failure behaviour lives only in a `# Errors` section (which `Error` variant, when), panic
  conditions only in `# Panics`, safety contracts only in `# Safety`; do not restate them inline.
- Doc links must resolve: broken or private-item links fail the doc build. Reference a private item
  from public docs as plain code text, not a link.

## Commands and gates

```
cargo build --workspace                                   # build everything
cargo test --workspace                                    # run all tests
cargo test -p <crate>                                     # test a single crate
cargo fmt --all                                           # format
cargo fmt --all -- --check                                # gate: formatting
cargo clippy --workspace --all-targets -- -D warnings     # gate: lint
RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps  # gate: doc build
```

The gates are the three commands marked above plus the build and the tests, run exactly as the
hosted CI runs them, so a local pass predicts a CI pass. If local git hooks are not wired, say
"checks run locally before pushing", not "automated hooks".

## Enforced by

`allow` entries for the cargo gate commands, so they run without prompts.
