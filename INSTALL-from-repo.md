# Hosting & Installing the NixOS Config from a Private GitHub Repo

## Bottom Line

A private GitHub repo holds `flake.nix`, `configuration.nix`, `home.nix`, and the
docs. The new machine authenticates once to clone it, you drop in the locally
generated `hardware-configuration.nix`, and install with `nixos-install` from the
live ISO. The repo is the source of truth; the hardware file is the one piece born
on the target machine and never committed.

Two constraints drive the workflow:
- **`hardware-configuration.nix` stays out of the repo.** It encodes this disk's
  UUIDs and LUKS device — machine-specific and a liability to share. It's
  `.gitignore`d and lives only on the machine.
- **A private repo needs auth on a fresh machine.** The live ISO has no
  credentials, so you fetch with a short-lived token (or SSH key) and then build
  from the local clone, so Nix's fetcher never needs repo auth.

Why a private repo over a Gist: real access control (a "secret" Gist is just an
unguessable URL, not access-controlled), readable diffs, branches, issues, and
clean rollback paired with git history. For a config that touches your SSH and
1Password setup, that access control is the point.

---

## Step 1 — Create the private repo (on your current machine)

```bash
cd ~/nixos-config   # the directory holding the files
git init
echo "hardware-configuration.nix" > .gitignore
git add flake.nix configuration.nix home.nix .gitignore \
        nixos-danklinux-framework13-amd-install-plan.md secure-boot.md
git commit -m "Initial Framework 13 AMD config"
gh repo create nixos-config --private --source=. --push
```

`gh` creates the repo and pushes. Confirm `hardware-configuration.nix` is NOT in
the repo: `git ls-files | grep hardware` should return nothing.

Before you commit, set the two placeholders:
- In `home.nix`, uncomment + set `userName` / `userEmail` in `programs.git`.
- Confirm the username is `scott` across all three files (it appears in the user
  block, greeter paths, and home-manager). Find-and-replace if yours differs.

---

## Step 2 — On the target machine: partition + encrypt

Boot the live ISO (minimal or graphical — either works; you'll use a terminal,
not Calamares). Get on Wi-Fi (`nmtui` on minimal, applet on graphical).

> **This erases the disk.** Confirm `lsblk` shows `nvme0n1` as your target
> first. If your NVMe is named differently (e.g., `nvme1n1`), substitute it
> in every command below.

```bash
sudo -i

# 1. Partition: 1 GiB ESP + LUKS container for the rest
sgdisk --zap-all /dev/nvme0n1
sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:ESP         /dev/nvme0n1
sgdisk -n 2:0:0     -t 2:8309 -c 2:cryptsystem /dev/nvme0n1
mkfs.fat -F32 -n BOOT /dev/nvme0n1p1

# 2. LUKS2 (set a strong passphrase — this unlocks the machine at every boot)
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptsystem

# 3. LVM inside LUKS: 92 GiB swap + root on the remainder
pvcreate /dev/mapper/cryptsystem
vgcreate vg /dev/mapper/cryptsystem
lvcreate -L 92G       -n swap vg
lvcreate -l 100%FREE  -n root vg

# 4. Filesystems + mount. Swap MUST be active when config is generated, so
#    nixos-generate-config writes it into hardware-configuration.nix.
mkfs.ext4 -L nixos /dev/vg/root
mkswap   -L swap   /dev/vg/swap
mount /dev/vg/root /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
swapon /dev/vg/swap

# 5. Generate the hardware config — this is what creates /mnt/etc/nixos/
nixos-generate-config --root /mnt
```

**Verify before moving on:**

```bash
ls /mnt/etc/nixos/
# expected: configuration.nix  hardware-configuration.nix
```

`hardware-configuration.nix` must list your LUKS UUID and the swap entry. If
either is missing, swap wasn't on when you ran step 5 — re-run `swapon
/dev/vg/swap` followed by `nixos-generate-config --root /mnt`.

> **Why this and not Calamares' "encrypt" checkbox:** the checkbox encrypts
> root but doesn't give you a deliberately sized encrypted swap wired for
> resume. Manual LVM-on-LUKS gives encrypted root + 92 GiB swap under a
> single passphrase, with hibernation working out of the box. The full
> rationale is in `nixos-danklinux-framework13-amd-install-plan.md` (Phase 1).

---

## Step 3 — Authenticate to the private repo

The live ISO has no GitHub credentials. Pick one:

### Option A — Fine-grained token (fastest for one-time install)

On GitHub: Settings → Developer settings → Fine-grained tokens → generate one
scoped to **only** `nixos-config`, **Contents: Read-only**, expiring in a few days.

### Option B — SSH key (durable; best if the machine stays in your fleet)

On the live ISO or after first boot:
```bash
ssh-keygen -t ed25519 -C "framework13"
cat ~/.ssh/id_ed25519.pub   # paste into GitHub -> Settings -> SSH keys
```

---

## Step 4 — Clone + install (from the live ISO)

> **Pre-flight:** `/mnt/etc/nixos/hardware-configuration.nix` must exist
> before you start this step. If `ls /mnt/etc/nixos/` errors, Step 2 didn't
> complete — go back and run it; do **not** create `/mnt/etc` by hand.

The minimal ISO does **not** ship `git` — pull it into an ephemeral shell with
`nix-shell -p git`. (The graphical ISO has it pre-installed, so you can skip
the wrapper there.)

```bash
# Clone into a temp location (token in URL, Option A shown)
GH_USER=scott
nix-shell -p git --run "git clone https://$GH_USER:<TOKEN>@github.com/$GH_USER/nixos-config.git /tmp/cfg"
# (Option B: nix-shell -p git --run "git clone git@github.com:scott/nixos-config.git /tmp/cfg")

# Place the flake next to the hardware file generated in Step 2.
# flake.lock is optional on the very first install (it doesn't exist
# in the repo yet); on every install after that, it MUST come along
# or you won't get the same input versions as last time.
rm /mnt/etc/nixos/configuration.nix          # drop the auto-generated stub
for f in flake.nix flake.lock configuration.nix home.nix; do
  [ -f /tmp/cfg/$f ] && cp /tmp/cfg/$f /mnt/etc/nixos/
done
# hardware-configuration.nix is already in /mnt/etc/nixos from Step 2 — leave it

# Install
nixos-install --flake /mnt/etc/nixos#framework13 \
  --option experimental-features 'nix-command flakes'

# Set root password when prompted
reboot
```

First build pulls niri, DMS, Claude Code, and home-manager — expect 15–40 minutes.
At boot you get the LUKS passphrase prompt, then the dms-greeter.

Building from the **local copy** in `/mnt/etc/nixos` (a path, not `github:...`)
means Nix never authenticates to the repo itself — the token only did the clone.

---

## Step 5 — Set up the working copy for ongoing changes

After first boot:

```bash
GH_USER=scott
# Option A clone, then immediately scrub the token from the stored remote:
git clone https://$GH_USER:<TOKEN>@github.com/$GH_USER/nixos-config.git ~/nixos-config
cd ~/nixos-config
git remote set-url origin https://github.com/$GH_USER/nixos-config.git
# (Option B: clone git@... and the remote is already token-free)

# Bring the machine's hardware file into the working copy (never commit it)
sudo cp /etc/nixos/hardware-configuration.nix ~/nixos-config/
sudo chown $USER:users ~/nixos-config/hardware-configuration.nix
# .gitignore already lists it from Step 1
```

Set `~/nixos-config` as your live config so `nixos-rebuild` uses it:
```bash
sudo rm -rf /etc/nixos
sudo ln -s ~/nixos-config /etc/nixos
```

---

## Ongoing workflow

```bash
cd ~/nixos-config
git pull                                   # grab changes from any machine
nix flake update                           # bump nixpkgs / niri / dms
sudo nixos-rebuild switch --flake .#framework13

# commit your edits (hardware file stays gitignored)
git add -A && git commit -m "..." && git push
```

Roll back a bad change with `sudo nixos-rebuild --rollback switch`, and pair it
with `git revert` so the repo and the running generation stay in sync.

---

## Auth trap to avoid

Do **not** reference the private repo as a flake input
(`inputs.config.url = "github:scott/nixos-config"`). It forces a GitHub token into
`nix.settings.access-tokens` (a committed credential leak), and the `github:`
fetch won't include your local `hardware-configuration.nix`, so evaluation fails.
Always build from the local clone. Reference-as-input only earns its complexity
when managing many machines from one pinned source, and even then auth is handled
out-of-band.

---

## File inventory

| File | In repo? | Why |
|---|---|---|
| `flake.nix` | Yes | Entry point, declares inputs |
| `configuration.nix` | Yes | System config — no secrets |
| `home.nix` | Yes | User config — no secrets |
| `secure-boot.md` | Yes | Post-install lanzaboote runbook |
| `nixos-danklinux-framework13-amd-install-plan.md` | Yes | Full plan |
| `hardware-configuration.nix` | **No** | Machine-specific disk UUIDs + LUKS device |
| `flake.lock` | Yes (recommended) | Pins inputs for reproducibility across machines |
