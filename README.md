# nixos-setup

Personal NixOS flake — one repo, one source of truth for every machine I run. The layout is multi-host: each machine is a directory under `hosts/` that `flake.nix` discovers automatically. Adding a machine is `scripts/new-host.sh` — see `hosts/README.md`.

The first machine (and currently the only one) is `sjr-fw13`, a Framework 13 AMD (Ryzen 7040) laptop running niri + Noctalia (Quickshell) on an encrypted disk with hibernation-capable swap. `INSTALL.md` is the runbook for that specific build. Other hardware works the same way structurally — pick a different `nixos-hardware` module, redo the disk/swap choices for the box, and the shared `configuration.nix` + `home.nix` layer on top.

## Files

| File | What it is |
|---|---|
| `flake.nix` | Entry point. Declares all inputs (nixpkgs, home-manager, nixos-hardware, niri, noctalia, claude-code-nix; lanzaboote is commented out — opt in via `secure-boot.md`) and auto-discovers every host under `hosts/` (no host hardcoded). |
| `configuration.nix` | Shared system-level config: bootloader, services, system packages, the `sroberts` user. Host-agnostic. |
| `home.nix` | User-level (home-manager): CLI tools, shell, Noctalia config, niri input + binds, activation hooks. Shared across hosts. |
| `hosts/<name>/` | Per-machine: `default.nix` (hostname, `nixos-hardware` model module, swap/resume) + the committed `hardware-configuration.nix` (LUKS UUID, filesystems). See `hosts/README.md`. |
| `scripts/new-host.sh` | Scaffolds a new `hosts/<name>/` on a fresh machine. |
| `flake.lock` | Pins every input to a specific commit. Generated on first build, then committed. |
| `INSTALL.md` | Single canonical install runbook (partition → encrypt → install → verify) plus rationale, gotchas, and migration notes. |
| `secure-boot.md` | lanzaboote post-install runbook (Framework-specific BIOS bits flagged inline; the `sbctl` flow itself is hardware-agnostic). |
| `CLAUDE.md` | Context for Claude Code; useful for humans too. |

## Where to start

- **Fresh install of the Framework 13 host** → `INSTALL.md`. Default path uses the
  Calamares GUI installer for an encrypted base, then layers this flake on
  top with `nixos-rebuild`. Robust and has a rollback safety net.
  Hibernation-capable install (manual LVM-on-LUKS) is documented as an
  appendix in the same file. Adapting the runbook to other hardware is
  mostly picking a different `nixos-hardware` module and revisiting
  the disk/swap/hibernate choices.
- **Adding a new host** → run `scripts/new-host.sh` on the target machine; see `hosts/README.md`. No edits to `flake.nix` needed — hosts are auto-discovered.
- **Already running, want to make a change** → edit a `.nix` file, then `sudo nixos-rebuild switch --flake .#<host>` (use the directory name under `hosts/`).
- **Enabling Secure Boot** → `secure-boot.md`. Do this only after the encrypted system boots reliably.
- **Want to know why X is the way it is** → read `configuration.nix` and `home.nix` directly; the "Stack at a glance" table in `INSTALL.md` covers the high-level decisions, and the comments in the `.nix` files cover the rest.

## Day-to-day commands

Substitute `<host>` for the directory name under `hosts/` (currently `sjr-fw13`). `nix flake show` lists every host the flake exposes.

```bash
# Apply a config change you just made
sudo nixos-rebuild switch --flake .#<host>

# Try a change without making it the default boot generation
sudo nixos-rebuild test --flake .#<host>

# Build for next boot, don't activate now
sudo nixos-rebuild boot --flake .#<host>

# Update all inputs (writes flake.lock)
nix flake update

# Update one input (Nix 2.19+)
nix flake update noctalia

# Roll back the last activation
sudo nixos-rebuild --rollback switch

# Clean up old generations + free /nix/store
nix-collect-garbage -d                   # user generations
sudo nix-collect-garbage -d              # system generations
```

After every config edit you intend to keep: `git add -A && git commit`. The repo *is* the source of truth — drift between repo and machine is the bug you're trying to avoid. Each host's `hardware-configuration.nix` is committed under `hosts/<name>/` (the LUKS UUIDs are identifiers, not secrets), so the repo fully describes every machine.

## First-time-on-this-machine prep

1. **Set your git identity in `home.nix`** if it isn't already — `programs.git.settings.user.{name,email}`. The committed values are mine (Scott J Roberts + GitHub no-reply); change if you're someone else.
2. **Commit `flake.lock`** after the first build, so the next install reproduces the same input versions.
3. Work through `~/TODO.md` (auto-generated on first activation) — credentials, firmware update, Ollama model pulls, etc. These genuinely can't be declared.

## When something breaks

- **Build fails** — read the error from the bottom up; the actual cause is usually 5-15 lines above the final `error:` line. Nix evaluates lazily, so the top of the stack is often a generic "module assertion failed."
- **System won't boot after a rebuild** — pick an older generation from the systemd-boot menu (it lists them by date). Then `sudo nixos-rebuild --rollback switch` to make that the default again. Pair with `git revert` so the repo matches the live system.
- **Disk filling up** — `nix-collect-garbage -d` removes old generations and lets the store shrink. Run as your user *and* as root (system generations live in a separate profile).
- **After firmware update breaks Secure Boot / TPM unlock** — expected; re-enroll keys or fall back to the LUKS passphrase. See `secure-boot.md`.

## Vocabulary (if you're new to Nix)

- **Flake** — a self-contained repo with pinned dependencies. Inputs go in `flake.nix`, get locked into `flake.lock`. Build by `--flake .#<host>`.
- **Module** — a `.nix` file that declares config options. `configuration.nix` is the root system module; `home.nix` is the root home-manager module. Each input above contributes additional modules (`niri.nixosModules.niri`, etc.).
- **home-manager** — manages user-scope config (dotfiles, user packages, shell) the same way NixOS manages system-scope config. Configured per-user inside the NixOS config.
- **Generation** — an immutable snapshot of the system, created on every `nixos-rebuild switch`. Visible in the boot menu and in `/nix/var/nix/profiles/system-*-link`. Rollback = boot or activate an older one.
- **`stateVersion`** — pinned to `26.05` here. Marks the schema version of stateful services (databases, etc.) so future nixpkgs updates don't surprise-migrate them. Don't bump it without reading the release notes.
