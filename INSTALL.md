# Installing NixOS + DankMaterialShell on a Framework 13 AMD

Single canonical runbook for installing this flake onto a fresh Framework 13
AMD (Ryzen 7040). Top-to-bottom; you should not need to switch docs while
installing. For Secure Boot, work through this guide first, then see
`secure-boot.md` as a follow-up. For the *why* behind specific Nix options,
read `configuration.nix` / `home.nix` directly — they're the source of truth.

> **Two install paths.** The default path uses the Calamares graphical
> installer to get an encrypted base (with optional hibernation-sized
> swap), then layers this flake on top with `nixos-rebuild`. It's robust
> and has a rollback safety net. The appendix at the end covers a manual
> LVM-on-LUKS install for anyone who wants the LVM layout specifically;
> hibernation is no longer the reason to take that path — Calamares' new
> "Swap with Hibernate" option handles it for the default flow.

---

## Bottom Line

Install NixOS unstable (26.05) with an encrypted disk via the Calamares
graphical installer (with the "Swap with Hibernate" option for
suspend-to-disk support), sign into the user account it created, then
point `nixos-rebuild` at this flake. The rebuild replaces GNOME with
niri + DMS and installs everything else.

Three facts drive the sequencing:

- **Encryption is install-time.** Calamares' "Encrypt system" checkbox is
  what you want; opting out later means a reinstall.
- **Set the root and user passwords in the GUI.** This is where the manual
  install path most commonly fails (locked accounts → emergency mode with
  no recovery shell). Calamares can't proceed without both passwords being
  set, so you get a guaranteed-working base.
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
| Disk (default) | LUKS-encrypted ext4 + swap-with-hibernate (via Calamares) | Encrypted root + hibernation-sized swap, no LVM |
| Disk (appendix path) | LUKS2 + LVM, 92 GiB swap | Same encryption + hibernation, with LVM for multi-volume management |
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

Download the **NixOS unstable graphical (GNOME) ISO** from nixos.org and flash
it with `dd` or Rufus — don't use Etcher from a NixOS host, it's no longer
packaged. The graphical ISO ships Calamares, which is the installer this
guide uses.

### 3. Set your git identity in `home.nix`

`programs.git.settings.user.{name,email}` are committed values. Set them on
your current machine before you push, so the target machine's commits go out
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

## Step 1 — Install the base with Calamares

Boot the graphical ISO, wait for the GNOME live session to load, then launch
**Install NixOS** from the desktop. Click through to the *Storage* step.

**Critical choices:**

- **Storage:** "Erase disk" (the whole disk gets reformatted).
- **Encrypt:** check **"Encrypt system."** Set a strong LUKS passphrase —
  you'll type it at every boot.
- **Swap:** select **"Swap (with Hibernate)"**. This creates a swap
  partition sized for the hibernation image. Without it, suspend-to-disk
  won't work; suspend-to-RAM still will. If you don't care about
  hibernation, any swap option (or none) is fine.
- **User account:** username `sroberts` (must match the `sroberts` referenced
  throughout `configuration.nix` and `home.nix`). Set **both** the user
  password and the root password in the GUI. Don't leave root blank — that's
  what causes the locked-emergency-mode dead-end in the manual path.
- **Locale / timezone:** whatever you want.
- **Desktop:** leave the default (GNOME). It's what Calamares installs;
  we'll replace it with niri + DMS in Step 3.

Click through to install. Calamares writes an encrypted ext4 root, an
unencrypted FAT32 ESP, and (if you picked Swap with Hibernate) a swap
partition sized for the RAM image.

When it finishes, reboot. Pull the USB out.

## Step 2 — First boot

At the LUKS passphrase prompt, type the passphrase you set in Calamares.
GNOME's GDM should appear; sign in as `sroberts`. You now have a working
NixOS install — this is the base that the rest of this guide builds on.

If anything goes wrong from here, you can always boot back into this
generation from the systemd-boot menu (it gets named "default" + the
date). That's the safety net.

## Step 3 — Layer this flake on top

Open a GNOME terminal. Make sure NetworkManager has Wi-Fi (use the GNOME
status menu if needed), then:

```bash
# Pull the repo (graphical ISO and Calamares-installed GNOME both ship git)
git clone https://github.com/sroberts/nixos-setup.git ~/nixos-setup
cd ~/nixos-setup
```

Bring the machine-specific hardware file Calamares generated into the
working copy. `.gitignore` keeps it out of commits.

```bash
sudo cp /etc/nixos/hardware-configuration.nix ~/nixos-setup/
sudo chown $USER:users ~/nixos-setup/hardware-configuration.nix
```

Make `~/nixos-setup` the live config so `nixos-rebuild` finds your edits:

```bash
sudo rm -rf /etc/nixos
sudo ln -s ~/nixos-setup /etc/nixos
```

Now the big rebuild. This replaces GNOME with niri + DMS, installs all the
CLI/GUI packages, sets up shell integrations and activation hooks, and
generates `~/TODO.md` for the things Nix can't declare.

```bash
sudo nixos-rebuild switch --flake .#framework13
```

Expect 15–40 minutes depending on bandwidth — niri, DMS, Claude Code, and
home-manager are all in the closure. The download buffer is bumped to
256 MiB in `configuration.nix`, so you won't see the "download buffer is
full" warnings you'd otherwise hit.

When it finishes, log out of GNOME (or just reboot). At the dms-greeter,
sign in as `sroberts` and you'll land in niri + DMS.

**If the rebuild fails or the new session won't start**, this is where the
Calamares base saves you. From the systemd-boot menu, pick the older
generation (it'll still boot GNOME with the GDM greeter). Then debug from
there, or `sudo nixos-rebuild --rollback switch` to drop back permanently.

## Step 4 — Lock in the lock file

If `flake.lock` didn't exist in the repo when you cloned, the rebuild just
generated one. Commit it so the next machine reproduces this one:

```bash
cd ~/nixos-setup
git add flake.lock
git commit -m "Pin flake inputs from first install"
git push
```

## Step 5 — Verify

```bash
# Encryption: root sits under cryptroot
lsblk
sudo cryptsetup status cryptroot   # name may differ; check `lsblk` output

# Hibernation (if you picked Swap with Hibernate in Calamares)
swapon --show                      # swap device should be listed
cat /sys/power/resume              # non-zero device path
systemctl hibernate                # should power off fully, then restore on unlock

# Power profiles working, TLP not loaded
powerprofilesctl get
systemctl status tlp 2>&1 | head -2

# Kernel 6.12+ floor for Ryzen 7040
uname -r

# Firmware
fwupdmgr get-devices
sudo fwupdmgr update

# DMS health
dms doctor -v

# Docker available without sudo
docker run --rm hello-world

# Ollama up (if rocm caused a crash, swap to pkgs.ollama-vulkan or pkgs.ollama in configuration.nix)
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

1. **niri-flake niri-stable is on 25.08 but DMS needs 25.11.** This config
   pins `programs.niri.package` to `niri-unstable` from the flake (see
   `configuration.nix`). We also `.overrideAttrs (doCheck = false)` to skip
   niri's in-build cargo tests, which can SIGABRT in the Nix build sandbox
   even when the runtime binary is fine. Don't drop the override unless
   you've verified niri's upstream test suite passes in a sandbox.
2. **Native module vs flake module for DMS:** nixpkgs-unstable's
   `programs.dank-material-shell` works; the flake gives DMS git head and
   `niri.enableKeybinds`. This repo uses the flake.
3. **Empty `binds.kdl` on flake install** (AvengeMedia/DankMaterialShell
   #1586): let `niri.enableKeybinds = true` handle it; if binds are still
   empty, copy DMS's default `binds.kdl` manually.
4. **Keep a recovery USB.** With an encrypted root, a broken boot chain
   means recovering from the live ISO: `cryptsetup open` → `mount` →
   `nixos-enter` → roll back. `secure-boot.md` has the exact commands;
   substitute the LVM steps with plain mount if you used the Calamares
   layout.
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
10. **Don't reference this repo as a flake input.** It would force a token
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

## Appendix — manual LVM-on-LUKS install

Use this path only if you specifically want the LVM layout (e.g. for
multi-volume management, easier resize later, or a deliberately sized
encrypted swap LV inside the same LUKS container). Hibernation is *not*
a reason to take this path anymore — Calamares' "Swap with Hibernate"
option in Step 1 gives you that on the default flow.

The trade-off is no built-in rollback safety net during install — if it
goes wrong, you're recovering from the live ISO.

You'll also need to **uncomment** `boot.resumeDevice = "/dev/vg/swap"` at
the bottom of the `boot.resumeDevice` block in `configuration.nix`
before the rebuild in Step 3, so the kernel resumes from the LVM swap LV.

Boot the live ISO (minimal or graphical), connect Wi-Fi, then:

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

# 5. Generate the hardware config
nixos-generate-config --root /mnt
```

Verify before installing:

```bash
ls /mnt/etc/nixos/
# expected: configuration.nix  hardware-configuration.nix

grep -A3 swapDevices /mnt/etc/nixos/hardware-configuration.nix
# must list /dev/disk/by-uuid/... pointing at the swap LV
```

Then clone this repo, copy the flake files in, and run `nixos-install`:

```bash
# Minimal ISO needs nix-shell -p git; graphical ISO has git pre-installed
nix-shell -p git --run "git clone https://github.com/sroberts/nixos-setup.git /tmp/cfg"

rm /mnt/etc/nixos/configuration.nix          # drop the auto-generated stub
for f in flake.nix flake.lock configuration.nix home.nix; do
  [ -f /tmp/cfg/$f ] && cp /tmp/cfg/$f /mnt/etc/nixos/
done

# IMPORTANT: uncomment boot.resumeDevice before installing
sed -i 's|^  # boot.resumeDevice = "/dev/vg/swap";|  boot.resumeDevice = "/dev/vg/swap";|' /mnt/etc/nixos/configuration.nix

nixos-install --flake /mnt/etc/nixos#framework13 \
  --option experimental-features 'nix-command flakes'
# Set the root password when prompted — DO NOT skip
reboot
```

Then proceed to Step 4 (`flake.lock`) and Step 5 (verify), plus add a
hibernation check:

```bash
swapon --show                  # 92G swap present
cat /sys/power/resume          # non-zero device
systemctl hibernate            # should power off fully, then restore on unlock
```

Known additional gotchas for this path:

- **Hibernation needs swap ≥ RAM image.** 92 GiB covers ~64 GB RAM
  comfortably (relies on compression above that). If you have 96 GB and
  routinely run RAM hot, bump the swap LV before installing.
- **Don't use random-key swap** (`randomEncryption`). It can't survive
  the power cycle hibernation requires. Swap must live inside the
  persistent LUKS container.
- **Don't skip the root-password prompt at `nixos-install`.** Empty
  password = locked account = no recovery shell from emergency mode.

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
