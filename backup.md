# Backups

Time Machine-shaped backups of `/home/sroberts` to an attached USB drive, using
[restic](https://restic.net/). Plug the drive in and it backs up; unplug it and
nothing complains.

Snapshots are versioned, deduplicated, and encrypted. Everything is local — no
cloud account, no credentials, no third party.

Configured in the *Backups* section of `configuration.nix`.

---

## Read this first

**The password in `/etc/restic/home-password` is the only key to the repo.**
There is no recovery path. If this laptop dies and that file existed nowhere
else, the backup drive is 465 GB of unreadable noise.

Keep a copy in 1Password. Do it before you rely on any of this.

---

## The shortcut

Every restic command needs the repo path and the password file. Export this
once per shell and the rest of this document is copy-pasteable:

```bash
export R="sudo restic -r /mnt/backup/restic/$(hostname) --password-file /etc/restic/home-password"
```

Then `$R snapshots`, `$R mount /mnt/restore`, and so on.

---

## How it works

| Piece | Behaviour |
|---|---|
| Drive found by **filesystem label** `timemachine` | Any port or enclosure works — no device paths |
| fstab entry is `noauto,nofail` | Never attempted at boot, never blocks boot when absent |
| udev rule → `mnt-backup.mount` | Plugging the drive in *is* the trigger |
| `restic-backups-home.service` is `WantedBy` that mount | Backup starts the moment the drive mounts |
| `ConditionPathIsMountPoint` | Hourly timer skips **silently** when unplugged |
| `Persistent = true` | A window missed while asleep runs once on the next mount |
| Retention: 24 hourly, 14 daily, 8 weekly, 12 monthly | Dense recent history, sparse older |

`/home/sroberts` is backed up minus caches, model weights, chat-app state, and
build artefacts — see `exclude` in `configuration.nix`. As measured on
2026-09-05 that trims ~31 GB down to ~5 GB of genuinely irreplaceable data.

---

## Initiating a backup

### Automatically (the normal path)

Plug the drive in. udev mounts it and the backup starts. While it stays
attached, the timer runs hourly.

### On demand

```bash
sudo systemctl start restic-backups-home
```

Watch it as it goes:

```bash
journalctl -u restic-backups-home -f
```

The first run creates the repo and copies everything — a few minutes for ~5 GB.
Subsequent runs are incremental and usually finish in seconds.

---

## Verifying a backup

**Did the last run succeed?**

```bash
systemctl status restic-backups-home
```

`Active: inactive (dead)` with a clean exit is success — this is a oneshot
service, so it is *not* supposed to stay running.

With the drive unplugged you will see **`condition failed`** rather than
`failed`. That is the intended quiet skip, not an error.

**Are the snapshots really there?**

```bash
$R snapshots
```

One row per snapshot with time and host. If this lists nothing after a run,
the backup did not actually happen — check the journal.

**When does it next run?**

```bash
systemctl list-timers restic-backups-home
```

**Is the repo internally sound?**

```bash
$R check                  # structure only, fast
$R check --read-data      # re-reads every byte; slow, worth doing occasionally
```

**How much space is it using?**

```bash
$R stats latest           # size of the newest snapshot
$R stats --mode raw-data  # actual on-disk size after dedup
df -h /mnt/backup
```

---

## Restoring

### Browse it like Time Machine

The one to remember. Every snapshot appears as an ordinary directory tree you
can `cd` into and copy out of with normal tools:

```bash
sudo mkdir -p /mnt/restore
$R mount /mnt/restore
```

Look in `/mnt/restore/snapshots/` — one directory per snapshot, named by
timestamp, plus a `latest` symlink. `Ctrl-C` unmounts.

### One file back

```bash
# Recover somewhere safe first and diff before overwriting — do this
# whenever you are not certain.
$R restore latest --target /tmp/restore --include /home/sroberts/Documents/notes.md
diff /tmp/restore/home/sroberts/Documents/notes.md /home/sroberts/Documents/notes.md

# Or straight back to its original path:
$R restore latest --target / --include /home/sroberts/Documents/notes.md
```

### A whole directory

```bash
$R restore latest --target /tmp/restore --include /home/sroberts/Developer/subrosa
```

### From an older snapshot

```bash
$R snapshots                       # copy the short ID you want
$R restore <snapshot-id> --target /tmp/restore --include /path/you/want
```

### Find which snapshot has the version you want

```bash
$R find 'notes.md'                 # every snapshot containing it
$R diff <older-id> <newer-id>      # what changed between two snapshots
```

### Full recovery after disk loss

1. Reinstall NixOS from this flake — see `INSTALL.md`.
2. Recreate `/etc/restic/home-password` from your 1Password copy.
3. Attach the drive and restore:

```bash
$R restore latest --target /
```

The system comes back from the flake; the data comes back from here.

---

## Maintenance

Pruning runs automatically after each backup with the retention above, so
there is normally nothing to do.

```bash
$R forget --prune --keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12
```

If a backup is interrupted — drive yanked mid-run, laptop suspended — the repo
can be left locked. The service clears stale locks on its next run, or:

```bash
$R unlock
```

---

## Troubleshooting

**The drive is plugged in but nothing happens.**

Confirm the kernel sees it and the label is intact:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,TRAN
ls -l /dev/disk/by-label/timemachine
```

No device at all means it is not enumerating — that is a hardware problem, not
a config one. Watch `journalctl -k -f` while replugging. `error -71` plus a
`full-speed` negotiation means a bad or charge-only USB-C cable; a drive should
come up high-speed or SuperSpeed.

If the label is missing the drive was never formatted for this, or was
reformatted. See *Preparing a new drive* below.

**The label exists but it did not mount.**

```bash
systemctl status mnt-backup.mount
sudo systemctl start mnt-backup.mount
```

**The service says `condition failed`.** The drive is not mounted. That is the
designed behaviour, not a fault.

**`repository is already locked`.** Run `$R unlock`.

**`wrong password or no key found`.** The password file does not match the repo
— usually a repo created under a different password. Restore the original from
1Password; there is no way around this by design.

---

## Preparing a new drive

Destroys everything on the target. Check `lsblk` twice — confirm the size and
model match the drive you mean, and that you are not looking at `nvme0n1`.

```bash
sudo wipefs -n /dev/sdX          # read-only probe: anything listed is data
sudo mkfs.ext4 -L timemachine /dev/sdX1
```

The label is how the config finds the drive, so it must be exactly
`timemachine`.

Creating the password file, if this is a fresh machine:

```bash
sudo install -d -m 0700 /etc/restic
sudo sh -c 'umask 077; head -c 32 /dev/urandom | base64 > /etc/restic/home-password'
sudo chmod 0400 /etc/restic/home-password
```

Then save it in 1Password. The repo itself is created automatically on the
first backup (`initialize = true`).

The drive's filesystem is deliberately *not* LUKS-encrypted: restic already
encrypts everything in the repo, so a lost or stolen drive leaks nothing
without the password.

---

## Test your restores

A backup you have never restored from is a hypothesis, not a backup. Once a
quarter, recover a file to `/tmp` and diff it against the original. It takes a
minute and it is the only way to know this works before you need it to.
