---
paths:
  - ".gitignore"
  - ".devcontainer/**"
  - "**/Containerfile*"
  - "**/Dockerfile*"
  - "README.md"
  - "CONTRIBUTING.md"
---

# Development tooling

- **Containers**: Podman is the prioritised engine. Podman-only tooling is an accepted limitation;
  Docker is not opposed, but working on Podman is sufficient.
- **Host**: the host carries system packages only, podman and distrobox. Development tools live
  in two boxes with homes of their own, shared across projects: `DevBox` (Fedora) for every tool
  that does not need Ubuntu, and `CompatBox` (Ubuntu) for vendors' builds that support only
  Ubuntu. `preset host` checks the machine and `preset host --install` sets it up; on a system
  other than Fedora the `host-setup` skill says how.
- **Dev container first**: a project builds, tests, and runs its gates in its dev container
  (`.devcontainer/`) by default whenever podman is reachable, even when the host has the
  toolchain. From a toolbox, podman is reached on its host (`host-spawn`, `distrobox-host-exec`,
  `flatpak-spawn`). Podman is a soft requirement: without it the work runs on the host, and the
  author is told so. Shipped or compared builds never fall back to the host.
- **Editor**: the author uses Zed. Name Zed, not JetBrains, when documentation lists editors, and do
  not add JetBrains-specific configuration.
- **Ignore files**: never prune IDE ignore templates for editors the author does not use; they keep
  contributors' IDE files out of the repository. IDE project state (`.idea/`, `.run/`, `.fleet/`) is
  never committed.
