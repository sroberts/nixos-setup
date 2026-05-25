# Installing NixOS + DankMaterialShell on a Framework 13 AMD

Single canonical runbook for installing this flake onto a fresh Framework 13
AMD (Ryzen 7040). Top-to-bottom; you should not need to switch docs while
installing. For Secure Boot, work through this guide first, then see
`secure-boot.md` as a follow-up. For the *why* behind specific Nix options,
read `configuration.nix` / `home.nix` directly — they're the source of truth.

---

## Bottom Line

Install NixOS unstable (26.05) with a **manually partitioned, fully encrypted
LVM-on-LUKS** disk (encrypted root + a 92 GiB encrypted swap sized for
hibernation), then build the system from this flake. Three facts drive the
sequencing:

- **Encryption is install-time and irreversible.** Bolt-on later means
  reinstall. Happens in Step 2.
- **Hibernation needs persistent-key encrypted swap ≥ RAM image size.**
  Random-key swap can't survive a power cycle, so swap lives inside the same
  LUKS container as root.
- **Secure Boot is post-install only.** lanzaboote layers signing onto a
  booting system. Enabling Secure Boot in BIOS before keys are enrolled
  leaves you unbootable. Do it after this guide; see `secure-boot.md`.

Plus: BIOS 3.05+ (else multi-watt standby drain), Secure Boot **off** during
install, and `power-profiles-daemon` (not TLP) on Ryzen 7040.

---

## Stack at a glance

| Layer | Choice | Why |
|---|---|---|
| Distro | NixOS unstable (26.05) | Required for `programs.dank-material-shell` and `services.displayManager.dms-greeter` |
| Channel mgmt | Flakes + home-manager | Reproducible; pins DMS/niri independently |
| Hardware module | `nixos-hardware.nixosModules.framework-13-7040-amd` | Maintained quirks (lid wake, sensors, GPU) |
| Power | `power-profiles-daemon` | Framework's official recommendation for Ryzen 7040; do NOT use TLP |
| Compositor | niri via `niri-flake` (sodiboo) | DMS-compatible; declarative |
| Shell/UI | DankMaterialShell flake + home-manager module | Faster updates than nixpkgs; `niri.enableKeybinds` shortcut |
| Greeter | `dms-greeter` (unstable nixpkgs) | Theme-synced with DMS |
| Disk | LUKS2 + LVM | One passphrase unlocks root + swap; required for encrypted hibernation |
| Swap | 92 GiB LV inside LUKS | Persistent-key encrypted swap; holds the hibernation image |
| Bootloader | systemd-boot → lanzaboote (post-install) | Layered Secure Boot signing; see `secure-boot.md` |

If you have a Ryzen AI 300 (not 7040), swap the hardware module to
`framework-amd-ai-300-series` in `flake.nix`.

---

## Pre-install (do once, on your current machine)

### 1. BIOS

Update BIOS to **3.05 or later** before installing — older firmware causes
multi-watt standby drain on the 7040. Then in BIOS:

1. Set a UEFI admin password.
2. **Disable Secure Boot** in "Administer Secure Boot."

### 2. USB media

Download the **NixOS unstable minimal or graphical ISO** from nixos.org. The
minimal ISO is fine (we partition by hand from a terminal). Flash with `dd`
or Rufus — don't use Etcher from a NixOS host, it's no longer packaged.

### 3. Set your git identity in `home.nix`

`programs.git.userName` / `userEmail` are committed values. Set them on your
current machine before you push, so the target machine's commits go out
under the right author.

### 4. Push the repo to GitHub (if you haven't)

```bash
cd ~/nixos-setup
git add -A && git commit -m "ready to install"
git push
```

`.gitignore` already excludes `hardware-configuration.nix`, so machine
secrets stay local.

---

## Step 1 — Partition + encrypt (on the target machine)

Boot the live ISO, connect Wi-Fi (`nmtui` on minimal, applet on graphical).

> **This erases the disk.** Run `lsblk` first and confirm `nvme0n1` is your
> target. If your NVMe is named differently (e.g., `nvme1n1`), substitute it
> in every command below.

```bash
sudo -i

# 1. Partition: 1 GiB ESP + LUKS container for the rest
sgdisk --zap-all /dev/nvme0n1
sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:ESP         /dev/nvme0n1
sgdisk -n 2:0:0     -t 2:8309 -c 2:cryptsystem /dev/nvme0n1
mkfs.fat -F32 -n BOOT /dev/nvme0n1p1

# 2. LUKS2 (this passphrase unlocks the machine at every boot — make it strong)
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

`hardware-configuration.nix` must list your LUKS UUID **and** the swap entry.
If swap is missing, swap wasn't on when you ran step 5 — re-run `swapon
/dev/vg/swap` followed by `nixos-generate-config --root /mnt`.

> **Why this and not the Calamares "encrypt" checkbox:** the checkbox
> encrypts root but doesn't give you a deliberately sized encrypted swap
> wired for resume. Manual LVM-on-LUKS gives encrypted root + 92 GiB swap
> under a single passphrase, with hibernation working out of the box.

---

## Step 2 — Authenticate to the private repo

The live ISO has no GitHub credentials. Pick one:

### Option A — Fine-grained token (fastest for one-time install)

On GitHub: Settings → Developer settings → Fine-grained tokens → generate one
scoped to **only** this repo, **Contents: Read-only**, expiring in a few days.

### Option B — SSH key (durable; best if the machine stays in your fleet)

On the live ISO or after first boot:

```bash
ssh-keygen -t ed25519 -C "framework13"
cat ~/.ssh/id_ed25519.pub   # paste into GitHub → Settings → SSH keys
```

---

## Step 3 — Clone the repo and install

> **Pre-flight:** `/mnt/etc/nixos/hardware-configuration.nix` must exist
> before you start. If `ls /mnt/etc/nixos/` errors, Step 1 didn't complete —
> go back and run it; do **not** create `/mnt/etc` by hand.

The minimal ISO does **not** ship `git` — pull it into an ephemeral shell
with `nix-shell -p git`. (The graphical ISO has it pre-installed, so you can
skip the wrapper there.)

```bash
# Clone into a temp location (token in URL, Option A shown)
GH_USER=scott
nix-shell -p git --run "git clone https://$GH_USER:<TOKEN>@github.com/$GH_USER/nixos-setup.git /tmp/cfg"
# (Option B: nix-shell -p git --run "git clone git@github.com:$GH_USER/nixos-setup.git /tmp/cfg")

# Place the flake next to the hardware file generated in Step 1.
# flake.lock is optional on the very first install (it may not exist
# in the repo yet); on every install after that, it MUST come along
# or you won't get the same input versions as last time.
rm /mnt/etc/nixos/configuration.nix          # drop the auto-generated stub
for f in flake.nix flake.lock configuration.nix home.nix; do
  [ -f /tmp/cfg/$f ] && cp /tmp/cfg/$f /mnt/etc/nixos/
done
# hardware-configuration.nix is already in /mnt/etc/nixos — leave it

# Install
nixos-install --flake /mnt/etc/nixos#framework13 \
  --option experimental-features 'nix-command flakes'

# Set the root password when prompted
reboot
```

First build pulls niri, DMS, Claude Code, and home-manager — expect 15–40
minutes depending on bandwidth.

> **Why we build from the local copy** (`/mnt/etc/nixos`, a path) **rather
> than `github:user/repo`:** Nix never authenticates to GitHub for the build,
> so the token only had to last for the `git clone`. Building from the
> `github:` URL would force a token into `nix.settings.access-tokens` (a
> committed credential leak) and wouldn't include your local
> `hardware-configuration.nix`.

At boot you'll get the LUKS passphrase prompt, then the dms-greeter.
Hibernation works immediately — `boot.resumeDevice = "/dev/vg/swap"` in
`configuration.nix` points the resume at the encrypted swap.

---

## Step 4 — Set up the working copy for ongoing changes

After first boot, in your user shell:

```bash
GH_USER=scott

# Option A: clone with the token, then immediately scrub it from the stored remote
git clone https://$GH_USER:<TOKEN>@github.com/$GH_USER/nixos-setup.git ~/nixos-setup
cd ~/nixos-setup
git remote set-url origin https://github.com/$GH_USER/nixos-setup.git
# (Option B: clone git@... and the remote is already token-free)

# Bring the machine's hardware file into the working copy (never commit it;
# .gitignore already lists it)
sudo cp /etc/nixos/hardware-configuration.nix ~/nixos-setup/
sudo chown $USER:users ~/nixos-setup/hardware-configuration.nix
```

Make `~/nixos-setup` the live config so `nixos-rebuild` finds your edits:

```bash
sudo rm -rf /etc/nixos
sudo ln -s ~/nixos-setup /etc/nixos
```

If `flake.lock` didn't exist in the repo when you installed, the install
generated one in `/etc/nixos/flake.lock`. Commit it now so the next machine
reproduces this one:

```bash
cd ~/nixos-setup
git add flake.lock
git commit -m "Pin flake inputs from first install"
git push
```

---

## Step 5 — Verify the install

```bash
# Encryption: confirm root + swap are LUKS-backed under one container
lsblk                          # vg-root and vg-swap sit under cryptsystem (LUKS)
sudo cryptsetup status cryptsystem

# Hibernation: resume target set, swap active and large enough
cat /sys/power/resume          # non-zero device
swapon --show                  # 92G swap present
systemctl hibernate            # should power off fully, then restore on unlock

# Power profiles working, TLP not loaded
powerprofilesctl get
systemctl status tlp 2>&1 | head -2

# Kernel 6.12+ floor
uname -r

# Firmware
fwupdmgr get-devices
sudo fwupdmgr update

# DMS health
dms doctor -v

# Docker available without sudo
docker run --rm hello-world

# Ollama up
curl -s http://localhost:11434/api/version

# AI CLIs on PATH
claude --version
gemini --version
```

Work through `~/TODO.md` (auto-created on first activation) for the
credential / sign-in steps Nix can't declare.

---

## Migrating from Arch + DankLinux (optional)

Two configs carry over cleanly from the previous install, if relevant:

- **DMS settings.** Copy `~/.config/DankMaterialShell/settings.json` and
  `dms-colors.json` from Arch. Drop them in the same path on NixOS; the
  greeter's `configFiles` will sync them.
- **niri config.** Copy `~/.config/niri/config.kdl`. With
  `enableKeybinds = true`, DMS overwrites the bind section — back up first if
  you had custom binds.

What doesn't carry: any `dankinstall`-managed system packages. On NixOS
those live in the flake, not on disk.

---

## Ongoing workflow

```bash
cd ~/nixos-setup
git pull                                      # grab changes from any machine
nix flake update                              # bump all inputs
# Or: nix flake update dms                    # bump one input
sudo nixos-rebuild switch --flake .#framework13

# commit your edits (hardware-configuration.nix stays gitignored)
git add -A && git commit -m "..." && git push
```

Roll back a bad change with `sudo nixos-rebuild --rollback switch` and pair
it with `git revert` so the repo and running generation stay in sync.

---

## Known gotchas

1. **niri-flake niri-stable is on 25.08 but DMS needs 25.11.** Use
   `niri-unstable` from the flake or the version in nixpkgs unstable. Don't
   mix.
2. **Native module vs flake module for DMS:** nixpkgs-unstable's
   `programs.dank-material-shell` works; the flake gives DMS git head and
   `niri.enableKeybinds`. This repo uses the flake.
3. **Empty `binds.kdl` on flake install** (AvengeMedia/DankMaterialShell
   #1586): let `niri.enableKeybinds = true` handle it; if binds are still
   empty, copy DMS's default `binds.kdl` manually.
4. **Keep a recovery USB.** With an encrypted root, a broken boot chain
   means recovering from the live ISO: `cryptsetup open` → `vgchange -ay` →
   mount → roll back. `secure-boot.md` has the exact commands.
5. **lmstudio is unfree** — `nixpkgs.config.allowUnfree = true` is mandatory
   (already set).
6. **Ollama ROCm on Radeon 780M** is hit-or-miss. If you see crashes, swap
   `services.ollama.package` to `pkgs.ollama` (CPU) or `pkgs.ollama-vulkan`.
   The older `services.ollama.acceleration = "rocm"` option was removed
   upstream; the working API is `services.ollama.package = pkgs.ollama-rocm`.
7. **Claude Code via Nix bundles its own Node** — your project's
   `npm`/`node` from mise stays untouched. Intentional; prevents the "wrong
   shell" error that affected earlier Nix packaging.
8. **Activation hooks run as the user, not root.** Use absolute Nix store
   paths for any binary in a hook (the existing hooks do).
9. **Secure Boot is a separate project.** See `secure-boot.md`. Get the
   encrypted system booting reliably first, then enable lanzaboote. Never
   flip Secure Boot ON in BIOS before keys are enrolled.
10. **Hibernation needs swap ≥ RAM image.** 92 GiB covers ~64 GB RAM
    comfortably (relies on compression above that). If you have 96 GB and
    routinely run RAM hot, bump the swap LV before installing.
11. **Don't use random-key swap** (`randomEncryption`). It can't survive
    the power cycle hibernation requires. Swap must live inside the
    persistent LUKS container, which Step 1's layout ensures.
12. **Don't reference this repo as a flake input.** It would force a token
    into `nix.settings.access-tokens` (a committed credential leak), and the
    `github:` fetch wouldn't include your local `hardware-configuration.nix`.
    Always build from the local clone.

---

## File inventory

| File | In repo? | Why |
|---|---|---|
| `flake.nix` | Yes | Entry point, declares inputs |
| `configuration.nix` | Yes | System config — no secrets |
| `home.nix` | Yes | User config — no secrets |
| `flake.lock` | Yes (after first install) | Pins inputs for reproducibility |
| `secure-boot.md` | Yes | Post-install lanzaboote runbook |
| `INSTALL.md` | Yes | This file |
| `README.md` | Yes | Orientation and day-to-day commands |
| `CLAUDE.md` | Yes | Context for AI coding agents working in this repo |
| `hardware-configuration.nix` | **No** | Machine-specific disk UUIDs + LUKS device |

---

## References

- [NixOS on the Framework Laptop 13 (Framework Guides)](https://guides.frame.work/Guide/NixOS+on+the+Framework+Laptop+13/400)
- [NixOS Wiki — Hardware/Framework/Laptop 13](https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_13)
- [nixos-hardware framework-13-7040-amd module](https://github.com/NixOS/nixos-hardware/tree/master/framework/13-inch/7040-amd)
- [DankMaterialShell — NixOS Flake install](https://danklinux.com/docs/dankmaterialshell/nixos-flake)
- [DankGreeter — NixOS install](https://danklinux.com/docs/dankgreeter/nixos)
- [niri-flake (sodiboo)](https://github.com/sodiboo/niri-flake)
- [niri Getting Started](https://niri-wm.github.io/niri/Getting-Started.html)
- [lanzaboote (Secure Boot)](https://github.com/nix-community/lanzaboote)
- [claude-code-nix (sadjow) — hourly-updated flake](https://github.com/sadjow/claude-code-nix)
- [home-manager manual](https://nix-community.github.io/home-manager/)
