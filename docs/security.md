# Security

How riptide protects the PC, and what is still open. I checked all of this against the
code.

## Overview

| Who could attack | How safe | Why |
|---|---|---|
| Someone at the PC while it is **off** | weak for now | The disk is encrypted, but the TPM chip unlocks it by itself. Until Secure Boot is on, a USB stick could get the key |
| Someone at the PC while it is **locked** | good | The password is the only way in |
| An app in the sandbox | good | It only sees its own files and has to ask for everything else |
| A program outside the sandbox | medium | It has all the rights of the user |
| Getting root | good | Only one small helper with a fixed list of actions |
| The network | good | Firewall on, SSH off, local network blocked per app |

## Locked PC

- Before the password, only the window manager and the lock screen run. There are no
  shortcuts, no dock, no apps, and USB drives are not mounted.
- If the lock screen crashes, the screen stays locked. A crash never opens the desktop.
- After three wrong passwords you have to wait ten minutes.
- There are no text consoles to switch to, and every emergency login asks for the password.
- If the lock screen does not show up within 40 seconds, the session ends.

## Apps in the sandbox

- An app only sees its own data folders. It can not reach other apps' data, SSH keys, the
  password keyring or riptide's own files.
- It can not talk to the window manager, the shell or the background service, so it can not
  run commands outside its sandbox.
- The window manager does not let sandboxed apps record the screen, fake keyboard or mouse
  input, read the clipboard in the background or draw fake overlays.
- Microphone, camera, screen, folders, notifications and the local network are asked for
  once and can be taken back at any time.
- Links and files open in the default app, in that app's own sandbox.
- Apps from GitHub releases (the Zen browser) are checked with SHA-256 and can not update
  themselves.
- Not perfect yet: an app that may send notifications could pretend to be another app.
  Bugs in the Linux kernel or in bubblewrap could break the sandbox, and there is no
  seccomp filter yet.

## Programs outside the sandbox

- The terminal, the file manager and System Settings run with all rights of the user.
- riptide's own code is moving into a root-owned package in `/usr/lib/riptide`. Right now
  developer mode is on, so the code can still be changed by the user. System Settings
  says this openly.
- Programs outside the sandbox can still take screenshots without asking. This is planned.

## Root

- Root actions only go through one helper (`riptide-helper`, started with pkexec). It has a
  fixed list of actions and checks every argument. Apps only come from the official Arch
  repositories, and important system packages can not be removed. Everything that changes
  the system asks for the password.
- Files in `system/files/` are copied as root-owned files and never linked, so root never
  reads its config from a folder the user can change.

## Network

The firewall is on, SSH is off, and only mDNS (for printers) is allowed in. Every app is
blocked from the local network until it is allowed.

## PC turned off

- The disk is encrypted (LUKS2) and the TPM chip unlocks it. Right now the TPM only checks
  "Secure Boot is off", which a USB stick can also show. The boot partition is not
  encrypted.
- Already fixed: the editor in the boot menu is off. Before, you could get a root shell
  there without any password.
- The fix is Secure Boot. It is prepared in four steps, and step one is done. After that,
  only my own signed system can start, and the TPM only gives the key to that system.

## Next steps

1. Turn on Secure Boot
2. Finish moving riptide's files to root
3. Ask before programs outside the sandbox record the screen
4. Set a BIOS admin password and keep a recovery key for the disk offline
