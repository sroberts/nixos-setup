# nixos-setup

NixOS flake configuration for a Framework 13 AMD (Ryzen 7040) laptop running niri + DankMaterialShell on encrypted LVM-on-LUKS with hibernation-capable swap. The only host today is `sjr-fw13`, but the layout is multi-host: each machine is a directory under `hosts/` that `flake.nix` discovers automatically. See `hosts/README.md` to add one.

## Files

| File | What it is |
|---|---|
| `flake.nix` | Entry point. Declares all inputs (nixpkgs, home-manager, niri, DMS, lanzaboote, claude-code-nix) and auto-discovers every host under `hosts/` (no host hardcoded). |
| `configuration.nix` | Shared system-level config: bootloader, services, system packages, the `sroberts` user. Host-agnostic. |
| `home.nix` | User-level (home-manager): CLI tools, shell, DMS config, niri input, activation hooks. Shared across hosts. |
| `hosts/<name>/` | Per-machine: `default.nix` (hostname, `nixos-hardware` model module, swap/resume) + the committed `hardware-configuration.nix` (LUKS UUID, filesystems). See `hosts/README.md`. |
| `scripts/new-host.sh` | Scaffolds a new `hosts/<name>/` on a fresh machine. |
| `flake.lock` | Pins every input to a specific commit. Generated on first build, then committed. |
| `INSTALL.md` | Single canonical install runbook (partition → encrypt → install → verify) plus rationale, gotchas, and migration notes. |
| `secure-boot.md` | lanzaboote post-install runbook with Framework-specific key enrollment. |
| `CLAUDE.md` | Context for Claude Code; useful for humans too. |

## Where to start

- **Fresh install on a new Framework** → `INSTALL.md`. Default path uses the
  Calamares GUI installer for an encrypted base, then layers this flake on
  top with `nixos-rebuild`. Robust and has a rollback safety net.
  Hibernation-capable install (manual LVM-on-LUKS) is documented as an
  appendix in the same file.
- **Already running, want to make a change** → edit a `.nix` file, then `sudo nixos-rebuild switch --flake .#sjr-fw13`.
- **Enabling Secure Boot** → `secure-boot.md`. Do this only after the encrypted system boots reliably.
- **Want to know why X is the way it is** → read `configuration.nix` and `home.nix` directly; the "Stack at a glance" table in `INSTALL.md` covers the high-level decisions, and the comments in the `.nix` files cover the rest.

## Day-to-day commands

```bash
# Apply a config change you just made
sudo nixos-rebuild switch --flake .#sjr-fw13

# Try a change without making it the default boot generation
sudo nixos-rebuild test --flake .#sjr-fw13

# Build for next boot, don't activate now
sudo nixos-rebuild boot --flake .#sjr-fw13

# Update all inputs (writes flake.lock)
nix flake update

# Update one input (Nix 2.19+)
nix flake update dms

# Roll back the last activation
sudo nixos-rebuild --rollback switch

# Clean up old generations + free /nix/store
nix-collect-garbage -d                   # user generations
sudo nix-collect-garbage -d              # system generations
```

After every config edit you intend to keep: `git add -A && git commit`. The repo *is* the source of truth — drift between repo and machine is the bug you're trying to avoid. Each host's `hardware-configuration.nix` is committed under `hosts/<name>/` (the LUKS UUIDs are identifiers, not secrets), so the repo fully describes every machine.

## First-time-on-this-machine prep

1. **Set your git identity in `home.nix`** if it isn't already — `programs.git.userName` / `userEmail`. (Currently set to Scott J Roberts / scott.roberts@gmail.com — change if you're someone else.)
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
