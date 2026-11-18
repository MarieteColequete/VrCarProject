---
name: host-setup
description: Set up this machine for the work: podman and distrobox on the host, every development tool inside the DevBox and CompatBox boxes, builds in the project's dev container.
allowed-tools: Bash(sh *bin/preset host)
compatibility: Requires Linux for the boxes; the preset tool handles Fedora itself and points here for every other system.
disable-model-invocation: true
---

Set up this machine so the project's work runs, keeping the host clean.

The layout:

- **Host**: system packages only, podman and distrobox. Nothing else is installed on it.
- **DevBox** (Fedora): every development tool that does not need Ubuntu, and the author's
  terminal work.
- **CompatBox** (Ubuntu): vendors' builds that support only Ubuntu, such as Claude Code's desktop
  application.
- Each box has a home of its own under `~/.local/share/preset/boxes/<name>`, so toolchains
  (`~/.cargo`, `~/.rustup`) stay in it. The git and SSH settings, `glab`'s and Claude Code's state
  are linked from the real home, and the real home stays mounted, so work trees keep their paths.
- **Builds, tests, and coverage** run in the project's dev container, never in a box.

1. **Check.** Run `sh .claude/bin/preset host` and read every problem with its fix.
2. **Fedora, atomic or not.** The tool installs everything itself:
   `sh .claude/bin/preset host --install`. The command guard asks first; the author answers the
   password prompt (the terminal's `sudo`, or the desktop's dialog through `pkexec`). On an atomic
   system the packages are layered with `rpm-ostree`; after the reboot, run it again.
3. **Another Linux.** Install podman and distrobox as system packages, as the author, with the
   system's package manager:
   - Debian, Ubuntu, and their derivatives: `sudo apt install podman distrobox`.
   - Arch and its derivatives: `sudo pacman -S podman distrobox`.
   - openSUSE: `sudo zypper install podman distrobox`; on MicroOS or Aeon,
     `sudo transactional-update pkg install podman distrobox`, then reboot.
   - Others: podman from the system's packages, distrobox as its documentation describes.

   Give the author the command; do not run it. Then `sh .claude/bin/preset host --install`
   creates and fills the boxes, whatever the host system is.
4. **Windows or macOS.** There are no boxes. The preset's tool has no macOS build, and on
   Windows a Linux machine in WSL2 is the place for this procedure. Report this to the author.
5. **Verify.** `sh .claude/bin/preset host` reports no problems. Never install a development tool
   on the host to make a check pass: it belongs in a box, through the project's `host` data
   (`packages`, `setup`).
