# dotfiles (riptide)

Arch Linux on riptide: LUKS2 + TPM2, btrfs + snapper, Limine, NVIDIA,
Hyprland + Quickshell as an own macOS-style system. See `docs/os-plan.md`, `ROADMAP.md`;
for Claude sessions: `home/claude/CLAUDE.md`, linked to `~/CLAUDE.md` (rules, map, how to work here).

| Path              | Content                                                     |
|-------------------|-------------------------------------------------------------|
| `packages.txt`    | package list (official repos)                               |
| `bin/`            | user-invoked helper scripts                                 |
| `system/files/`   | files installed to `/` (root-owned copies, never symlinks)  |
| `system/secure-boot/` | staged Secure Boot setup scripts                        |
| `docs/`           | how-tos (rollback, secure boot)                             |

Files under `system/files/` are copied, not linked: root must never execute or
read boot configuration from a user-writable location.
