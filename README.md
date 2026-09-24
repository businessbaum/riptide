# dotfiles (riptide)

Arch Linux on riptide: LUKS2 + TPM2, btrfs + snapper, Limine, NVIDIA,
Hyprland + Quickshell (planned). See `ROADMAP.md`.

| Path              | Content                                                     |
|-------------------|-------------------------------------------------------------|
| `packages.txt`    | package list (official repos)                               |
| `bin/`            | user-invoked helper scripts                                 |
| `system/files/`   | files installed to `/` (root-owned copies, never symlinks)  |
| `system/secure-boot/` | staged Secure Boot setup scripts                        |
| `docs/`           | how-tos (rollback, secure boot)                             |

Files under `system/files/` are copied, not linked: root must never execute or
read boot configuration from a user-writable location.
