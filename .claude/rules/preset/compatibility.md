# Compatibility layers

Compatibility mechanisms (marker lists, former-version lists, migration tables, and the parameters
that carry them) are systems meant for beta onwards.

- Keep them structurally intact in cleanups, refactors, and reviews, even while empty.
- Never add alpha-era entries to them.
- An alpha-to-alpha incompatibility, such as an older alpha install no longer being recognised, is
  intended and not a regression. Do not report it as one.
