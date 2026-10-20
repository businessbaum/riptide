# Security model

How riptide protects the machine, checked against the code and, where it matters, against
Hyprland 0.56's source. It names what is **not** protected yet as plainly as what is.

## Who could attack, and how well riptide stands

| # | Attacker | Rating | Why |
|---|---|---|---|
| 1 | Physical access, machine **off** | weak until Secure Boot is on | the TPM unlocks the disk by itself, bound to PCR 7 while Secure Boot is still off |
| 2 | Physical access, machine **on and locked** (also right after boot) | good | one door: the password on the lock screen |
| 3 | A **sandboxed app** | good | bubblewrap + filtered D-Bus + Hyprland's protocol whitelist for sandboxed clients |
| 4 | A **program outside the sandbox** (terminal, file manager, anything started from a terminal) | medium | it has the user's rights |
| 5 | Root | good | one helper, fixed actions, password for anything that changes the system |
| 6 | Network | good | firewall on, SSH off, local network per app |

## 1. Machine off: the boot chain

- The disk is LUKS2, unlocked by the TPM against PCR 7. With Secure Boot **off**, PCR 7 only
  records "Secure Boot off" – a system booted from a USB stick sees the same value. `/boot`
  is not encrypted and could be changed the same way.
- Already closed: Limine's editor is off (`editor_enabled: no`). Before, adding
  `init=/bin/sh` at the boot menu would have given a root shell without any password.
- **The fix is Secure Boot** (`system/secure-boot/`, four stages; stage 1 – unified kernel
  images – is done). Then only images signed with the machine's own keys start, Limine's
  config is sealed by its checksum, and PCR 7 also records which certificate allowed the
  boot: a stick signed by someone else gets a different value and the TPM releases nothing.
  Clearing the firmware or turning Secure Boot off changes PCR 7 too – the disk then asks
  for its passphrase (safe).
- In addition: a firmware administrator password, and a LUKS recovery key kept offline.

## 2. Machine on and locked

The only way in is the password on the lock screen (PAM `login` with `pam_faillock`: three
wrong passwords, ten minutes' wait; `pam_gnome_keyring` opens the keyring).

- Before the password, only Hyprland and the lock screen run. No shortcut is bound while
  the `start-locked` marker exists; the menu bar and dock are created only under a
  confirmed session lock (`Lock.qml`, fail-closed: nothing counts as unlocked until it is
  certain); login items and reopened apps wait; the keyring is locked.
- No drive is mounted while locked or before the first login – a stick plugged in at the
  lock screen never reaches the kernel's filesystem code.
- A crashed lock screen: Hyprland stays locked, the shell's service restarts it and it takes
  the lock back (`allow_session_lock_restore`). A crashed Hyprland while locked starts again
  with `--locked`. No crash opens the desktop.
- No text consoles to switch to (`srvrkeys:none`). Every emergency way in (⌃⌥F2, "other
  user", rescue mode, the greeter's text login) asks for a password.
- Nothing shows through the lock (`session_lock_xray` off); notifications do not appear on it.
- Watchdog: no lock screen within 40 s of a locked start → the session ends and greetd's
  login screen follows.
- Accepted trade-off: before the password, Hyprland and the lock screen already run as the
  user (not as the unprivileged greeter) – that is what makes the seamless "one passage"
  login possible. A bug in those two could give the user's rights, never root.

## 3. Sandboxed apps

- bubblewrap: only the app's own data folders and what was allowed. Other apps' data,
  `~/.ssh`, the keyring files and riptide's files are not there.
- Runtime folder: a fresh tmpfs with only the app's Wayland connection (a security
  context), a filtered D-Bus (xdg-dbus-proxy), sound when allowed and its documents.
  Hyprland's control socket, the shell's IPC and the session socket are unreachable – no way
  to run commands outside.
- Hyprland gives security-context clients only a fixed whitelist of protocols: no screen
  capture, no virtual keyboard or pointer, no background clipboard reading, no layer
  surfaces (fake overlays), no session lock, no list of other windows.
- Microphone, camera, screen, files, notifications, local network: asked once, revocable.
- Links and files an app opens leave the sandbox through the portal. Before this, an app
  that asked GIO for a browser found none inside and started any program that knew the
  scheme – a browser inside the mail client's sandbox, with the mail client's data. Now the
  default app opens it, in its own sandbox.
- Apps from release archives (the Zen browser): HTTPS to GitHub and the SHA-256 GitHub
  publishes for the file are required; the program folder is read-only in the sandbox and the
  app's own updater is off, so a hijacked app cannot rewrite itself.
- Web apps (WhatsApp, Word, PowerPoint in Chromium's app mode) are sandboxed like any app,
  each with its own profile. A root-owned Chromium policy hands every page outside the web
  app's own sites to the default browser.
- Open: notifications are attributed by what the app says about itself (the
  `desktop-entry` hint), so an app allowed to notify could send one under another app's name.
  Attributing by the sandbox's own D-Bus connection would close this.
- Residual risk: kernel or bubblewrap bugs; there is no seccomp filter yet.

## 4. Programs outside the sandbox

System apps (file manager, terminal, System Settings, task manager) and everything started
from a terminal run with all of the user's rights.

- riptide's own software is moving to root: the pacman package `riptide` installs it to
  `/usr/lib/riptide`, every file checkable with `pacman -Qkk riptide`. While **developer
  mode** is on, the repository is bound read-only over that path – the path cannot be
  written, but the repository can. System Settings → Privacy & Security says so.
- Still open: the home folder links into the system tree, user units in
  `~/.config/systemd/user` win over system ones, and the session environment can be
  changed by the user (`LD_PRELOAD`). Closing these needs the session to refuse user
  overrides of its parts.
- Screen capture by unsandboxed programs is not asked yet (Hyprland `enforce_permissions`
  is written but off).
- The clipboard history skips entries a password manager marks as secret.

## 5. Root

- `riptide-helper` (pkexec): fixed areas and actions, names checked by pattern, packages
  only from the official repositories, protected system packages cannot be removed.
  Packages, firewall and remote login ask for the password (`auth_admin_keep`); only adding
  or removing LAN rules for one of the user's own running app scopes needs none.
- polkit: the login screen's user may restart greetd and nothing else.
- `relock` (root, greetd's `ExecStartPre`) reads two files written by unprivileged users,
  accepts only plain numbers and acts only when both match, the logout is under two minutes
  old and the request under 15 s. Worst case: the session starts *locked* again.
- Files under `system/files/` are copied root-owned, never symlinked: root never executes or
  reads boot configuration from a user-writable place.

## 6. Network

firewalld on, SSH off and closed, only mDNS in (printers); local network per app blocked
unless allowed (nftables on the app's cgroup).

## Order of work

1. Secure Boot – closes the one way around the password while the machine is off.
2. System files owned by root – the remaining steps (entry points from the system, no home
   links, refusing user overrides, developer mode off).
3. Screen-capture permission for programs outside the sandbox.
4. Firmware administrator password; LUKS recovery key kept offline.
