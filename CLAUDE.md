# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal NixOS flake managing every machine the owner runs. It is the **source of truth** for each system — the running machine is a function of these files. The layout is multi-host: each machine is a directory under `hosts/`, and `flake.nix` discovers them automatically.

The first (and currently only) host is `sjr-fw13`, a Framework 13 AMD (Ryzen 7040) laptop running niri + Noctalia (Quickshell) on an encrypted disk with hibernation-capable swap. Most of the shared `configuration.nix` / `home.nix` is hardware-agnostic; a future workstation or NUC would slot in as a new `hosts/<name>/` without touching shared files. (When a non-laptop host actually lands, expect to revisit laptop-specific bits — lid-switch handling, hibernation timing, fingerprint, `power-profiles-daemon` — and move what doesn't apply into per-host modules.)

The repo is built to be cloned onto a fresh machine from the NixOS live ISO and installed against. Each host's `hardware-configuration.nix` (generated per-machine by `nixos-generate-config`) is **committed** under `hosts/<hostname>/` — flakes only evaluate git-tracked files, and the LUKS UUIDs it carries are identifiers, not secrets. To stand up a new machine, run `scripts/new-host.sh` on it; see `hosts/README.md`.

## Commands

All builds go through the flake. Substitute `<host>` for the directory name under `hosts/` (currently `sjr-fw13` — `nix flake show` lists every host the flake exposes).

```bash
# Rebuild and switch (the default verb after any edit)
sudo nixos-rebuild switch --flake .#<host>

# Test a change without making it the default boot generation
sudo nixos-rebuild test --flake .#<host>

# Build only, don't activate
sudo nixos-rebuild build --flake .#<host>

# Update everything, the PR way: branch chore/flake-update-YYYY-MM-DD from
# origin/main in a temporary worktree, `nix flake update`, `nom build` the host,
# print `nvd diff /run/current-system <new>` + an input-rev table, then (on y)
# push + open a PR carrying both. It never activates: it prints the branch
# switch + `sudo nixos-rebuild switch` (or `nh os switch`) to run next, then
# test and `gh pr merge --merge`. Refuses on uncommitted tracked changes.
os-update

# What did the last rebuild change? nvd diff, previous generation -> running.
# `os-diff N` = generation N -> running; `os-diff N M` = N -> M.
os-diff

# nh (programs.nh, NH_FLAKE = ~/nixos-setup): rebuild without `.#<host>`,
# with nom progress and a package diff before it elevates
nh os switch

# Bump nixpkgs / niri / noctalia / claude-code-nix by hand
nix flake update
# Or one input at a time (Nix 2.19+ positional arg; `--update-input` is deprecated)
nix flake update noctalia

# Roll back the last activation (pair with `git revert` to keep repo + system aligned)
sudo nixos-rebuild --rollback switch

# Check the flake evaluates and outputs are well-formed
nix flake check
```

There are no tests — a NixOS config is verified by evaluating and rebuilding it, not by a suite. CI runs three gates on every PR and push to `main` (see `.github/workflows/check.yml`): `nix flake check` (no `--no-build` — niri's package needs IFD), `nix fmt --check` over every `.nix` file, and an eval of every discovered host's system closure. No stubbing is needed — each host's `hardware-configuration.nix` is committed, so the flake evaluates in CI as-is (device paths are just strings; evaluation never touches disks).

`os-update` / `os-diff` are `writeShellApplication`s in `home.nix`'s `let` block (rationale in the comment above them); `nh` is `programs.nh` in `configuration.nix` with `clean` deliberately off — `nix.gc` stays the one GC mechanism (weekly, `--delete-older-than 30d`), and the nh module warns if both run.

Formatting **is** enforced: nixfmt is the linter, the tree is already clean, and CI fails on any drift. Run `nix fmt` after editing a `.nix` file — it is a no-op unless you actually introduced drift, so it will not produce a churn diff.

## Architecture

Shared, host-agnostic files in the repo root; per-machine state under `hosts/`:

- **`flake.nix`** — Inputs (nixpkgs unstable, home-manager, nixos-hardware, niri (niri-nix), noctalia, noctalia-greeter, claude-code-nix, herdr, nix-index-database) and the `nixosConfigurations` output. It does **not** hardcode a host: an `mkHost` helper builds each machine from its `hosts/<name>/` directory plus the shared `configuration.nix` + `home.nix`, and `builtins.readDir ./hosts` auto-discovers every host (so adding a machine never touches `flake.nix`). Every input `follows = "nixpkgs"` to keep one nixpkgs in the closure, **including `niri`**. niri comes from BANanaD3V/niri-nix (codeberg), not sodiboo/niri-flake: niri-flake pinned `libdisplay-info_0_2` (removed from nixpkgs) so it could not follow, and the resulting glibc skew against the system mesa niri dlopens black-screened login. niri-nix builds against `libdisplay-info_0_3`, so following works and niri/mesa/glibc share one nixpkgs by construction. Cost: no niri-nix.cachix.org hits, so niri builds from source. `programs.niri.package` in `configuration.nix` is niri-nix's `niri-unstable`, unmodified — niri-nix's recipe already skips the sandbox-hostile EGL tests, so the old niri-flake-era `doCheck` opt-out is gone on purpose. niri-nix's package reads `Cargo.lock` from the fetched source, so evaluating it is import-from-derivation — that is why CI's `nix flake check` runs without `--no-build`. The `lanzaboote` input is **commented out** by design — see *Secure Boot* below.
- **`configuration.nix`** — Shared system-level config: bootloader, PipeWire, networking, niri + noctalia-greeter, Docker, Ollama (ROCm), the `sroberts` user, and the system-wide GUI apps (`_1password-gui`, `chromium`, `obsidian`, …). Host-agnostic — no hostname, no per-disk UUIDs. The function signature is `{ config, lib, pkgs, inputs, … }`.
- **`home.nix`** — User-level (home-manager): Noctalia config, niri input + binds, voxtype dictation, CLI/TUI tooling, zsh + integrations (zoxide, fzf, eza, bat, starship, mise, nix-index command-not-found + `comma` from the prebuilt nix-index-database — NixOS's channel-based `programs.command-not-found` is disabled in `configuration.nix` so there is one handler), and `home.activation.*` hooks for the imperative gaps Nix can't declare (LazyVim starter, CyberChef download, post-install TODO.md). Shared across hosts.
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

Noctalia is on the **v5** line (`flake.nix` pins the `v5.3.0` tag). v5 renamed the home-manager module from `programs.noctalia-shell` to `programs.noctalia`, replaced the `noctalia-shell ipc call <target> <fn>` surface with `noctalia msg <command…>`, and moved config from a hand-seeded `settings.json` to a declarative `config.toml`. Assume any v4-shaped snippet you find elsewhere is stale.

System side enables `programs.niri` and `services.displayManager.noctalia-greeter` (renamed from `programs.noctalia-greeter` upstream) — a Quickshell greeter that mirrors Noctalia Shell's palette, whose own NixOS module sets `services.greetd` with `mkDefault` (so there is no explicit greetd block here). User side imports `inputs.noctalia.homeModules.default` and enables `programs.noctalia`, with `programs.noctalia.systemd.enable = true` so the shell runs as a **systemd user unit** tied to `wayland.systemd.target` — *not* a niri `spawn-at-startup`. That is deliberate: `nixos-rebuild switch` doesn't kill a compositor-spawned shell, which used to leave a stale store-path bar alive and produce duplicate bars. The polkit agent is Noctalia's own native one (`programs.noctalia.settings.shell.polkit_agent = true`); niri-nix ships no agent of its own, so nothing else competes for the PolicyKit1 bus name. On the home-manager side niri-nix's module is `wayland.windowManager.niri.*` (imported explicitly in `home.nix`), and its `settings` is freeform KDL-in-Nix (`_args` / `_props`, binds as `"Mod+Q".close-window = [ ]`), checked by `niri validate` at build time rather than a typed schema at eval time.

The lock screen is Noctalia's own (its own PAM context, raised via `WlSessionLock`). **Noctalia does not subscribe to logind's `Lock` signal**, so `loginctl lock-session` is a no-op — locking must go through `noctalia msg session lock`, which is what the `Super+Alt+L` bind and swayidle's `before-sleep` use. Media/brightness keybinds in `home.nix` still go through `wpctl`, `playerctl`, and `brightnessctl` (shell-agnostic).

App binds are **launch-or-focus** (Omarchy-style `Super+Shift+<letter>`: B Chromium, O Obsidian, S Slack, G Signal, M Spotify, N Nautilus). niri has no native action for this, so `launchOrFocus` in `home.nix`'s `let` block is a `writeShellApplication` over `niri msg -j windows` + jq: arg 1 is a case-insensitive, anchored `.app_id` regex, the rest is the launch command. A match is focused (`focus-window --id`; repeat presses cycle through matches by window id), otherwise niri spawns the command (`niri msg action spawn --`). Electron apps report a different app_id on native Wayland vs. XWayland, so the regexes alternate between both spellings — check `niri msg -j windows` with the app open before changing one. Each bind carries a `hotkey-overlay-title` prop (`_props` in niri-nix) so the `Super+Shift+/` overlay shows a name instead of the store-path command.

The keybind cheat sheet is niri's own hotkey overlay (`Mod+Shift+/`; the startup splash is off via `hotkey-overlay.skip-at-startup`). The overlay shows every spawn bind, as its raw argv unless the bind has a title, so **every spawn bind carries `_props.hotkey-overlay-title = "…"`** — give any new one a title too. `Mod+Alt+Space` opens the **system menu** (`systemMenu` in `home.nix`'s `let` block): a `writeShellApplication` that feeds a list of actions (lock, keybinds, power profile, keep-awake via `keepawake --toggle` — deliberately not Noctalia's caffeine, which blocks the idle lock too — backup now, open nixos-setup, suspend, log out, reboot, power off) to `noctalia dmenu`, Noctalia's launcher in dmenu mode (stdin items → stdout pick, exit 1 on cancel), so the picker is the same themed panel as `Mod+Space` rather than a second launcher. Nothing in it needs sudo; "Run backup now" starts a system unit and so raises Noctalia's polkit agent.

Screen capture comes in two layers. `Print` / `Ctrl+Print` / `Alt+Print` are niri's native screenshot actions and stay that way. On top of those, **Noctalia owns annotation and recording**, so no satty, grim or wf-recorder is involved:
- `Super+Alt+S` runs `noctalia msg screenshot-region`. With `shell.screenshot.annotate = true`, the capture opens in Noctalia's built-in annotation editor, and Done saves the PNG to `~/Pictures/Screenshots` and copies it to the clipboard.
- `Super+Alt+R` toggles recording of the focused output and `Super+Alt+Shift+R` toggles recording of a slurp-picked region. Both go through Noctalia's **official `noctalia/screen_recorder` plugin** (`plugins.enabled` plus `plugin_settings."noctalia/screen_recorder"` in `home.nix`), which also supplies a bar indicator that shows only while recording. Recordings land in `~/Videos/Recordings`.
- The plugin shells out to gpu-screen-recorder. It captures over KMS, so `programs.gpu-screen-recorder.enable` in `configuration.nix` is required for the setcap `gsr-kms-server` wrapper. KMS capture ignores niri's `block-out-from "screencast"` rules.
- The plugin code is **not Nix-pinned**: Noctalia fetches it at runtime from its `official` git source, the same model as the community theme templates.
- The build-time `noctalia config validate` warns that the `screen_recorder` widget type and `plugin_settings` id are unknown. That is expected, because the build sandbox has no materialized plugins.

Idle is driven by **Noctalia's own idle manager**, declared in `programs.noctalia.settings.idle.behavior` in `home.nix`: a named `lock` behavior at `timeout = 600` (10 min) using Noctalia's native `action = "lock"` (not `command = "noctalia:session lock"` — that v4 syntax runs as a shell command in v5 and silently never locks), a `screen-off` behavior at `timeout = 660` (`locked_timeout = 60`) using Noctalia's native `screen_off` action, plus a named `hibernate` behavior at `timeout = 900` (15 min) running `suspend-unless-on-ac`. On battery that is `systemctl suspend-then-hibernate`, which suspends to RAM and hibernates `HibernateDelaySec` later (3h, set in `configuration.nix`), so hibernate lands at 3h 15m total idle. **On AC the sleep step is skipped but lock and screen-off still run** — the machine stays up for long jobs without sitting unlocked or lit. Lid close: on battery logind suspends (`HandleLidSwitch`); on AC it is ignored (`HandleLidSwitchExternalPower = "ignore"`), so niri's `switch-events.lid-close` locks instead. **swayidle** (in `home.nix`) is kept for one job only: its `before-sleep` hook locks (via `noctalia msg session lock`, resolved by absolute store path because the unit's PATH is minimal) ahead of a sleep Noctalia didn't initiate — i.e. a lid close on battery — since Noctalia has no lock-on-external-suspend hook.

**Keep-awake** (`keepawake` in `home.nix`'s let block, on PATH): `keepawake <cmd…>` runs a job under a logind `sleep:handle-lid-switch` **block** inhibitor that is released when the job exits; `Mod+Alt+I` (`keepawake --toggle`) holds the same inhibitor indefinitely in a transient `keepawake.service` user unit, with a notification on each change. While held, the 15-min idle step's `systemctl suspend-then-hibernate` is refused once by logind (benign — Noctalia runs a behavior's command once per idle period, no retry) and a battery lid close does not suspend, but the session **still locks and blanks** (niri's lid-close bind and Noctalia's lock/screen-off are unaffected). It deliberately does **not** take `idle`, and it is deliberately **not** Noctalia's caffeine (`noctalia msg caffeine-toggle`): Noctalia treats any logind `idle` block — which is exactly what caffeine takes — as suppressing every idle behavior, the lock included.

### Voice dictation (voxtype)

Local, offline push-to-talk-style dictation via **voxtype** (the tool Omarchy uses), declared with home-manager's own `services.voxtype` module in `home.nix`. The package is nixpkgs' `voxtype-vulkan` (whisper.cpp on the 780M via Vulkan — not ROCm, which would need `HSA_OVERRIDE_GFX_VERSION` for gfx1103 and a from-source build). The Whisper model (`ggml-small.en.bin`) is a `pkgs.fetchurl` with a pinned hash in `home.nix`'s `let` block (`voxtypeModel`), passed to `whisper.model` as a store path — **not** the module's `loadModels`, which downloads imperatively at service start. The daemon is a systemd user unit on `graphical-session.target` and keeps the model loaded. niri binds fire on key press only (no release events), so `Mod+Ctrl+X` is a **toggle** (`voxtype record toggle`: start listening / stop, transcribe and type) and `Mod+Ctrl+Shift+X` discards (`voxtype record cancel`). Text is typed with `wtype` (niri implements `zwp_virtual_keyboard_v1`), falling back to the clipboard; `audio.max_duration_secs = 300` caps a forgotten toggle. The evdev hotkey stays off — it would need the `input` group.

### Power (Framework 13 / Ryzen 7040)

`power-profiles-daemon` is enabled in shared `configuration.nix`; `tlp` is **explicitly disabled**. This is Framework's recommendation for Ryzen 7040 — TLP misbehaves on this platform. Don't swap them without a reason on `sjr-fw13`. When a non-Framework / non-7040 host lands, this is one of the things to move out of shared config and into that host's `default.nix` (or override there): TLP is the more common pick on other hardware, and a headless box may want neither.

## Editing patterns

- **Adding a system-wide package**: append to `environment.systemPackages` in `configuration.nix`.
- **Adding a user CLI tool**: append to `home.packages` in `home.nix`. Prefer this over system packages unless the tool needs to be on PATH for other users or services.
- **Adding a web app** (a site in its own Chromium `--app` window with a launcher entry): add one attr to `webApps` in `home.nix`'s `let` block — `name`, `url` (or `tailnetHost` + `path` for a self-hosted service; the tailnet suffix is read from tailscaled at launch because this repo is public), and an `icon` from `pkgs.fetchurl` at a pinned commit. `xdg.desktopEntries` generates `webapp-<key>.desktop`, launched via the `webapp-launch` script. The window's Wayland app-id is `chrome-<host>_<path>-Default` with `/` → `_` (e.g. `chrome-claude.ai__-Default`) — the path is part of it, so actions must stay on the start path. Don't use Chromium's "Install page as app": it writes non-reproducible `chrome-<extid>-Default.desktop` files.
- **Adding an imperative install step** (something not in nixpkgs): add a `home.activation.<name>` block in `home.nix` following the existing `cyberchef` / `lazyvimStarter` patterns — guard with an existence check so reruns are idempotent.
- **Bumping niri or Noctalia independently of nixpkgs**: `nix flake update niri` (or `noctalia`). The `--update-input` form on `nix flake lock` is deprecated since Nix 2.19.
- **Adding a new host**: run `scripts/new-host.sh` on the target machine (see `hosts/README.md`). It scaffolds `hosts/<name>/` and the flake auto-discovers it — no `flake.nix` edit. Anything machine-specific (hostname, `nixos-hardware` model module, swap/resume UUIDs, `hardware-configuration.nix`) goes in that directory; shared config stays in `configuration.nix` / `home.nix`.
- **`allowUnfree` is on** (`nixpkgs.config.allowUnfree = true`) for `lmstudio`, `typora`, `1password`. Unfree additions are fine.

## Secure Boot

Lanzaboote is a deliberate **post-install** step, not part of the initial build. The `lanzaboote` flake input and its module line in `flake.nix`, plus the `boot.lanzaboote` block in `configuration.nix`, are all commented out. Enabling them before keys are enrolled in the firmware will brick the boot. The full runbook is in `secure-boot.md`; touch those commented blocks only when following it.

The lanzaboote block uses `lib.mkForce` to override systemd-boot; `lib` is already in `configuration.nix`'s function arguments (`{ config, lib, pkgs, inputs, ... }`), so no signature change is needed.

## What's *not* declarative (by design)

Listed in `home.activation.todoMd` (the generated `~/TODO.md`): authenticating Claude Code, signing into 1Password / Gmail / GitHub / Slack / Discord / Signal / Zoom, joining Tailscale, setting wallpaper in Noctalia (its Material You-style theme derives from the wallpaper), syncing noctalia-greeter to the shell palette, Obsidian Sync, Typora license, Chromium extensions, `sudo fwupdmgr update`. These are credentials, account state, and firmware updates — not something Nix should own.

Ollama models are **not** on that list: `services.ollama.loadModels` in `configuration.nix` pulls them declaratively on first start via `ollama-model-loader.service`.

## Reference docs in this repo

- **`INSTALL.md`** — Single canonical install runbook for the Framework 13 AMD host (`sjr-fw13`): partition → encrypt → install → set up the working copy → verify. Other machines follow the same shape (Calamares base → `scripts/new-host.sh` → `nixos-rebuild`) with different hardware-specific values; `INSTALL.md` is the template. Includes the auth model (token for the clone, then build from the local path so Nix never sees the token), the "Stack at a glance" rationale table, known gotchas, and Arch+DankLinux migration notes.
- **`hosts/README.md`** — The per-host layout and the runbook for standing up a new machine with `scripts/new-host.sh` (deterministic config across different hardware).
- **`secure-boot.md`** — lanzaboote enrollment runbook (hardware-agnostic for the `sbctl` steps; Framework-specific BIOS quirks flagged inline), including optional TPM2 LUKS auto-unlock and recovery from a bricked boot.
- **`backup.md`** — Backup runbook for the restic-to-USB-drive setup configured in `configuration.nix`: running a backup on demand, verifying one landed, browsing snapshots as directories (`restic mount`), restoring a single file or the whole home, preparing a replacement drive, and troubleshooting. Note the two things Nix does not own here — a labelled physical drive and the password at `/etc/restic/home-password`, which is the only key to the repo.
- **`CONTRIBUTING.md`** — Branch/PR workflow and the per-merge checks. Every change goes through a feature branch and a PR; the repo blocks squash and rebase merges, so use `gh pr merge --merge`.
