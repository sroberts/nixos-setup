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
not Calamares). Follow **Phase 1 of the main plan** through
`nixos-generate-config --root /mnt`. That produces
`/mnt/etc/nixos/hardware-configuration.nix` describing the encrypted LVM-on-LUKS
layout. Then come back here.

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

```bash
# Clone into a temp location (token in URL, Option A shown)
GH_USER=scott
git clone https://$GH_USER:<TOKEN>@github.com/$GH_USER/nixos-config.git /tmp/cfg
# (Option B: git clone git@github.com:scott/nixos-config.git /tmp/cfg)

# Place the flake next to the hardware file generated in Step 2
rm /mnt/etc/nixos/configuration.nix          # drop the auto-generated stub
cp /tmp/cfg/flake.nix /tmp/cfg/configuration.nix /tmp/cfg/home.nix /mnt/etc/nixos/
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
