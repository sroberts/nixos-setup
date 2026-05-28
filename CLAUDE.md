# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A NixOS flake configuration for a Framework 13 AMD (Ryzen 7040) laptop running niri + Noctalia (Quickshell) on an encrypted LVM-on-LUKS disk with hibernation-capable encrypted swap. It is the **source of truth** for the system — the running machine is a function of these files. The only host today is `sjr-fw13`, but the layout is multi-host: each machine is a directory under `hosts/`, and `flake.nix` discovers them automatically.

The repo is built to be cloned onto a fresh machine from the NixOS live ISO and installed against. Each host's `hardware-configuration.nix` (generated per-machine by `nixos-generate-config`) is **committed** under `hosts/<hostname>/` — flakes only evaluate git-tracked files, and the LUKS UUIDs it carries are identifiers, not secrets. To stand up a new machine, run `scripts/new-host.sh` on it; see `hosts/README.md`.

## Commands

All builds go through the flake. The host attribute is `sjr-fw13`.

```bash
# Rebuild and switch (the default verb after any edit)
sudo nixos-rebuild switch --flake .#sjr-fw13

# Test a change without making it the default boot generation
sudo nixos-rebuild test --flake .#sjr-fw13

# Build only, don't activate
sudo nixos-rebuild build --flake .#sjr-fw13

# Bump nixpkgs / niri / noctalia / claude-code-nix
nix flake update
# Or one input at a time (Nix 2.19+ positional arg; `--update-input` is deprecated)
nix flake update noctalia

# Roll back the last activation (pair with `git revert` to keep repo + system aligned)
sudo nixos-rebuild --rollback switch

# Check the flake evaluates and outputs are well-formed
nix flake check
```

There are no tests and no linter (yet). CI runs `nix flake check --no-build` plus an eval of every discovered host's system closure on every PR and push to `main` (see `.github/workflows/check.yml`). No stubbing is needed anymore — each host's `hardware-configuration.nix` is committed, so the flake evaluates in CI as-is (device paths are just strings; evaluation never touches disks). Locally, `nix fmt` runs nixfmt — formatting has not yet been applied to existing files, so the first run will produce a churn diff.

## Architecture

Shared, host-agnostic files in the repo root; per-machine state under `hosts/`:

- **`flake.nix`** — Inputs (nixpkgs unstable, home-manager, nixos-hardware, niri-flake, noctalia, claude-code-nix) and the `nixosConfigurations` output. It does **not** hardcode a host: an `mkHost` helper builds each machine from its `hosts/<name>/` directory plus the shared `configuration.nix` + `home.nix`, and `builtins.readDir ./hosts` auto-discovers every host (so adding a machine never touches `flake.nix`). All inputs `follows = "nixpkgs"` so there is one nixpkgs in the closure. The `lanzaboote` input is **commented out** by design — see *Secure Boot* below.
- **`configuration.nix`** — Shared system-level config: bootloader, PipeWire, networking, niri + greetd/tuigreet, Docker, Ollama (ROCm), the `sroberts` user, and the system-wide GUI apps (`_1password-gui`, `chromium`, `obsidian`, …). Host-agnostic — no hostname, no per-disk UUIDs. The function signature is `{ config, lib, pkgs, inputs, … }`.
- **`home.nix`** — User-level (home-manager): Noctalia config, niri input + binds, CLI/TUI tooling, zsh + integrations (zoxide, fzf, eza, bat, starship, mise), and `home.activation.*` hooks for the imperative gaps Nix can't declare (LazyVim starter, CyberChef download, post-install TODO.md). Shared across hosts.
- **`hosts/<hostname>/`** — Everything machine-specific. `default.nix` sets `networking.hostName`, imports the `nixos-hardware` module for that exact model, and carries the hibernation swap LUKS unlock + `boot.resumeDevice`. `hardware-configuration.nix` (committed) encodes the root LUKS UUID, filesystems, and swapDevices. The only host today is `hosts/sjr-fw13/`. See `hosts/README.md` and `scripts/new-host.sh` for adding one.

### Disk layout — two supported paths

**Default (Calamares install):** ESP + LUKS-encrypted ext4 root. If the user picked "Swap with Hibernate" in Calamares, a hibernation-sized swap partition is also created and listed in `hardware-configuration.nix`'s `swapDevices`. The hibernation swap unlock + `boot.resumeDevice` live in the host module (`hosts/<hostname>/default.nix`), not in `configuration.nix` — they're per-disk LUKS UUIDs. No LVM in this layout.

**Appendix (manual LVM-on-LUKS):**

```
nvme0n1p1  ESP (FAT32, unencrypted)
nvme0n1p2  LUKS2 → LVM "vg"
             vg/swap  92 GiB  (encrypted, holds hibernation image)
             vg/root  rest    (encrypted, ext4)
```

This path is for users who specifically want the LVM layout (multi-volume management, easier resize). It requires setting `boot.resumeDevice = "/dev/vg/swap"` in the host module (`hosts/<hostname>/default.nix`) before the install, instead of the by-UUID swap unlock the Calamares path uses. The path is a stable LVM device, independent of `hardware-configuration.nix`. Hibernation needs persistent-key encrypted swap ≥ RAM, which is why swap lives *inside* LUKS rather than as a random-key swap partition.

The Calamares teardown lines in `configuration.nix` (`services.xserver.enable = false`, `services.displayManager.gdm.enable = false`, `services.desktopManager.gnome.enable = false`) are harmless on the manual path — they're disabling things that were never installed.

### niri + Noctalia wiring

System side enables `programs.niri` and `services.greetd` (tuigreet on tty1 launching `niri-session`). User side imports `inputs.noctalia.homeModules.default`, enables `programs.noctalia-shell`, and adds Noctalia to niri's `spawn-at-startup` so the shell launches with the compositor. Noctalia does **not** ship a greeter or a polkit agent — niri-flake's polkit user service is left at its default (enabled) to fill that gap, and tuigreet handles login.

The lock screen is Noctalia's own (its own PAM context, raised via `WlSessionLock`). **Noctalia does not subscribe to logind's `Lock` signal**, so `loginctl lock-session` is a no-op — locking must go through Noctalia's IPC (`noctalia-shell ipc call lockScreen lock`), which is what the `Super+Alt+L` bind and swayidle's `before-sleep` use. Media/brightness keybinds in `home.nix` still go through `wpctl`, `playerctl`, and `brightnessctl` (shell-agnostic).

Idle is driven by **Noctalia's own idle manager** (seeded in `home.activation.noctaliaConfigSeed`): a 5-min lock (`idle.lockTimeout`) plus an `idle.customCommands` entry running `systemctl suspend-then-hibernate` at 15 min. Noctalia's *built-in* idle-suspend is left disabled (`idle.suspendTimeout = 0`) because it only does a plain `systemctl suspend`; the custom command is a separate monitor that just runs the command, so it does the hibernate escalation cleanly. **swayidle** (in `home.nix`) is kept for one job only: its `before-sleep` hook locks (via Noctalia's IPC) ahead of a sleep Noctalia didn't initiate — i.e. a lid close — since Noctalia has no lock-on-external-suspend hook.

### Power on Ryzen 7040

`power-profiles-daemon` is enabled; `tlp` is **explicitly disabled**. This is Framework's recommendation for Ryzen 7040 — TLP misbehaves on this platform. Don't swap them without a reason.

## Editing patterns

- **Adding a system-wide package**: append to `environment.systemPackages` in `configuration.nix`.
- **Adding a user CLI tool**: append to `home.packages` in `home.nix`. Prefer this over system packages unless the tool needs to be on PATH for other users or services.
- **Adding an imperative install step** (something not in nixpkgs): add a `home.activation.<name>` block in `home.nix` following the existing `cyberchef` / `lazyvimStarter` patterns — guard with an existence check so reruns are idempotent.
- **Bumping niri or Noctalia independently of nixpkgs**: `nix flake update niri` (or `noctalia`). The `--update-input` form on `nix flake lock` is deprecated since Nix 2.19.
- **Adding a new host**: run `scripts/new-host.sh` on the target machine (see `hosts/README.md`). It scaffolds `hosts/<name>/` and the flake auto-discovers it — no `flake.nix` edit. Anything machine-specific (hostname, `nixos-hardware` model module, swap/resume UUIDs, `hardware-configuration.nix`) goes in that directory; shared config stays in `configuration.nix` / `home.nix`.
- **`allowUnfree` is on** (`nixpkgs.config.allowUnfree = true`) for `lmstudio`, `typora`, `1password`. Unfree additions are fine.

## Secure Boot

Lanzaboote is a deliberate **post-install** step, not part of the initial build. The `lanzaboote` flake input and its module line in `flake.nix`, plus the `boot.lanzaboote` block in `configuration.nix`, are all commented out. Enabling them before keys are enrolled in the firmware will brick the boot. The full runbook is in `secure-boot.md`; touch those commented blocks only when following it.

The lanzaboote block uses `lib.mkForce` to override systemd-boot; `lib` is already in `configuration.nix`'s function arguments (`{ config, lib, pkgs, inputs, ... }`), so no signature change is needed.

## What's *not* declarative (by design)

Listed in `home.activation.todoMd` (the generated `~/TODO.md`): authenticating Claude Code, signing into 1Password / Gmail / GitHub / Slack / Discord / Signal / Zoom, setting wallpaper in Noctalia (its Material You-style theme derives from the wallpaper), Obsidian Sync, Typora license, Chromium extensions, pulling Ollama models, `sudo fwupdmgr update`. These are credentials, account state, and firmware updates — not something Nix should own.

## Reference docs in this repo

- **`INSTALL.md`** — Single canonical install runbook for a fresh Framework 13 AMD: partition → encrypt → install → set up the working copy → verify. Includes the auth model (token for the clone, then build from the local path so Nix never sees the token), the "Stack at a glance" rationale table, known gotchas, and Arch+DankLinux migration notes.
- **`hosts/README.md`** — The per-host layout and the runbook for standing up a new machine with `scripts/new-host.sh` (deterministic config across different hardware).
- **`secure-boot.md`** — lanzaboote enrollment runbook, including optional TPM2 LUKS auto-unlock and recovery from a bricked boot.
