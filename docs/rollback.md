# System rollback (btrfs + snapper)

## Layout

| Subvolume    | Mounted at              | Rolled back? |
|--------------|-------------------------|--------------|
| `@`          | `/`                     | yes          |
| `@snapshots` | `/.snapshots`           | no           |
| `@home`      | `/home`                 | no           |
| `@var_log`   | `/var/log`              | no           |
| `@pkg`       | `/var/cache/pacman/pkg` | no           |

snap-pac takes a pre/post snapshot of `@` around every pacman transaction
(snapper config `root`, `NUMBER_LIMIT=10`). `/boot` (ESP, FAT32) is not part of
any snapshot.

`snapper rollback` is not used: it only changes the btrfs default subvolume,
but `/` is mounted explicitly with `subvol=@` (kernel cmdline and fstab).

## Rolling back

```bash
sudo ~/dotfiles/bin/snapshot-rollback        # list snapshots
sudo ~/dotfiles/bin/snapshot-rollback <N>    # roll back to snapshot N
reboot
```

The script renames `@` to `@broken-<timestamp>`, creates a writable copy of
snapshot N as the new `@` and rebuilds the boot files from the kernels inside
the new `@` (via mkinitcpio's pacman hook script).

### If the system does not boot at all

Boot the Arch ISO, then:

```bash
cryptsetup open /dev/nvme0n1p6 cryptroot
mount -o subvol=@home /dev/mapper/cryptroot /mnt
/mnt/user/dotfiles/bin/snapshot-rollback        # list
/mnt/user/dotfiles/bin/snapshot-rollback <N>
umount /mnt
reboot
```

### Undoing a rollback

From the ISO (or any running system), with the top level mounted:

```bash
mount -o subvolid=5 /dev/mapper/cryptroot /mnt
mv /mnt/@ /mnt/@rolledback-unwanted
mv /mnt/@broken-<timestamp> /mnt/@
umount /mnt
```

Kernel files in `/boot` may then not match `@` any more; rebuild them from the
running system with `sudo mkinitcpio -P` after copying the kernel
(`sudo pacman -S linux linux-lts` does both).

### Cleanup

```bash
sudo mount -o subvolid=5 /dev/mapper/cryptroot /mnt
sudo btrfs subvolume delete /mnt/@broken-<timestamp>
sudo umount /mnt
```
