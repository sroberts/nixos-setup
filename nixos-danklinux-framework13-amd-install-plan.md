# NixOS + DankLinux on Framework 13 AMD — Install & Setup Plan

## Bottom Line

Install NixOS unstable (26.05) with a **manually partitioned, fully encrypted LVM-on-LUKS** disk (encrypted root + a 92 GiB encrypted swap sized for hibernation), then build the system from a flake that imports `nixos-hardware` (framework-13-7040-amd), `niri-flake`, and the `DankMaterialShell` flake. The bootstrap stack — 1Password, Chromium, Obsidian, lazygit, mise-managed runtimes, AI CLIs, LazyVim, shell config — is expressed declaratively in `configuration.nix`/`home.nix`. Only three items can't be declared and need a one-shot script: CyberChef, Playdate Simulator, and the TODO.md scaffold. Secure Boot is added as a clean post-install step via lanzaboote (see `secure-boot.md`).

Three sequencing facts drive the whole install:
- **Encryption is install-time and irreversible.** It changes partitioning; you cannot bolt it on later without reinstalling. So it happens in Phase 1, by hand.
- **Hibernation needs persistent-key encrypted swap ≥ the size of the RAM image.** Random-key swap can't survive a power cycle, so swap lives inside the same LUKS container. 92 GiB is set as requested; note it should be ≥ your installed RAM for guaranteed full-image hibernation (covers ~64 GB RAM comfortably; relies on compression above that).
- **Secure Boot is post-install only.** lanzaboote layers signing onto a booting system. Enabling it before the system boots, or flipping Secure Boot on in BIOS before enrolling keys, leaves you unbootable.

Plus the usual: BIOS 3.05+ (else multi-watt standby drain), Secure Boot **off** during install, and `power-profiles-daemon` rather than TLP on Ryzen 7040.

---

## Stack Decision

| Layer | Choice | Why |
|---|---|---|
| Distro | NixOS unstable (26.05) | Required for `programs.dank-material-shell` and `services.displayManager.dms-greeter`; rolling kernel |
| Channel mgmt | Flakes + home-manager | Reproducible; lets you pin DMS/niri flakes independently |
| Hardware module | `nixos-hardware.nixosModules.framework-13-7040-amd` | Maintained quirks (lid wake, sensors, GPU) |
| Power | `power-profiles-daemon` | Framework's official recommendation for Ryzen 7040; do NOT use TLP |
| Compositor | niri via `niri-flake` (sodiboo) | Latest niri; DMS-compatible; declarative config |
| Shell/UI | DankMaterialShell flake + home-manager module | Faster updates than nixpkgs; `niri.enableKeybinds` shortcut |
| Greeter | `dms-greeter` (unstable nixpkgs) | Theme-synced with DMS |
| Disk encryption | LUKS2 + LVM (LVM-on-LUKS) | One passphrase unlocks root + swap; required for encrypted hibernation |
| Swap | 92 GiB LV inside LUKS | Persistent-key encrypted swap; holds the suspend-to-disk image |
| Bootloader | systemd-boot → lanzaboote (post-install) | lanzaboote layers signing onto a booting system; see `secure-boot.md` |
| App provisioning | Nix-declarative (`environment.systemPackages` + `home.packages`) | Replaces the imperative bootstrap script; idempotent by definition |
| Imperative gaps | CyberChef, Playdate Simulator | Not packaged in nixpkgs; one-shot installer script |

---

## Prerequisites & Pre-Install

### Verify hardware identity
Framework 13 with Ryzen 7040. If it's Ryzen AI 300 instead, swap the hardware module to `framework-amd-ai-300-series` and require a 6.12+ kernel.

### BIOS
1. Update BIOS to **3.05 or later** before installing. Older firmware causes multi-watt standby drain on the 7040.
2. Boot into BIOS (F2), set a UEFI password, **disable Secure Boot** in "Administer Secure Boot."

### USB media
Download the **NixOS unstable minimal or GNOME ISO** from nixos.org. The minimal ISO is fine — we partition by hand from a terminal, so no graphical installer is needed. Flash with `dd` or Rufus. Don't use Etcher from a NixOS host — it's no longer packaged.

---

## Phase 1: Manual Encrypted Install

This replaces the Calamares auto-install. Manual partitioning is what reliably produces a fully encrypted disk with a correctly sized hibernation swap, and `nixos-generate-config` captures all of it into `hardware-configuration.nix` automatically.

> **Disk target below is `/dev/nvme0n1`.** Confirm with `lsblk` first. This erases the disk.

1. Boot the ISO (tap **F12**), connect Wi-Fi (`nmtui` on minimal, or the applet on GNOME).

2. **Partition** — GPT, a 1 GiB ESP, and a LUKS container for the rest:
   ```bash
   sudo -i
   sgdisk --zap-all /dev/nvme0n1
   sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:ESP         /dev/nvme0n1
   sgdisk -n 2:0:0     -t 2:8309 -c 2:cryptsystem /dev/nvme0n1
   mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
   ```

3. **Create the LUKS2 container** (this passphrase unlocks the machine at every boot — make it strong):
   ```bash
   cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
   cryptsetup open /dev/nvme0n1p2 cryptsystem
   ```

4. **LVM inside LUKS** — 92 GiB swap + root on the remainder:
   ```bash
   pvcreate /dev/mapper/cryptsystem
   vgcreate vg /dev/mapper/cryptsystem
   lvcreate -L 92G        -n swap vg
   lvcreate -l 100%FREE   -n root vg
   ```

5. **Filesystems + mount** (swap on for hibernation; it must be active when config is generated):
   ```bash
   mkfs.ext4 -L nixos /dev/vg/root
   mkswap   -L swap   /dev/vg/swap
   mount /dev/vg/root /mnt
   mkdir -p /mnt/boot
   mount /dev/nvme0n1p1 /mnt/boot
   swapon /dev/vg/swap
   ```

6. **Generate the hardware config** — this writes the LUKS unlock entry, filesystems, and swap into `hardware-configuration.nix`:
   ```bash
   nixos-generate-config --root /mnt
   ```

You now have `/mnt/etc/nixos/hardware-configuration.nix` describing the encrypted layout. Proceed to Phase 2 to drop in the flake and install. Don't reboot yet.

> **Why this and not Calamares' "encrypt" checkbox:** the checkbox encrypts root but does not give you a deliberately sized encrypted swap wired for resume. Manual LVM-on-LUKS gives encrypted root + 92 GiB swap under a single passphrase, with hibernation working out of the box.

---

## Phase 2: Install from the Flake

### Get the flake files next to the generated hardware config
Bring `flake.nix`, `configuration.nix`, and `home.nix` into `/mnt/etc/nixos/` alongside the `hardware-configuration.nix` you just generated. Clone your private repo (see `INSTALL-from-repo.md`) or copy from USB. **Delete the placeholder `configuration.nix` that `nixos-generate-config` created** — you're using your own:
```bash
rm /mnt/etc/nixos/configuration.nix   # the auto-generated stub; replace with yours
# copy/clone your flake.nix, configuration.nix, home.nix into /mnt/etc/nixos/
```

### Install
```bash
nixos-install --flake /mnt/etc/nixos#framework13 \
  --option experimental-features 'nix-command flakes'
```
Set the root password when prompted, then:
```bash
reboot
```

At boot you'll get the LUKS passphrase prompt, then the dms-greeter. Hibernation (`systemctl hibernate`) works immediately — `boot.resumeDevice = "/dev/vg/swap"` in `configuration.nix` points the resume at the encrypted swap, and the swap entry from `hardware-configuration.nix` keeps it active.

### (Reference) the flake that does all this

```nix
{
  description = "Scott's Framework 13 AMD NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Optional: hourly-updated Claude Code instead of nixpkgs version
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-hardware, niri, dms, claude-code-nix, ... }@inputs: {
    nixosConfigurations.framework13 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        nixos-hardware.nixosModules.framework-13-7040-amd
        niri.nixosModules.niri
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.scott = import ./home.nix;
        }
      ];
    };
  };
}
```

```bash
# First install was done with `nixos-install` in Phase 2. From here on, after
# any config change:
sudo nixos-rebuild switch --flake /etc/nixos#framework13
```

> The reference block above is abbreviated. The shipped `flake.nix` also imports `./hardware-configuration.nix` and carries a commented-out lanzaboote input for Secure Boot — see the standalone files.

---

## Phase 3: Framework Hardware Tuning

Add to `configuration.nix`:

```nix
{ config, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Hibernation: resume from the encrypted swap LV (stable LVM path).
  # The swap entry itself comes from the auto-generated hardware-configuration.nix.
  boot.resumeDevice = "/dev/vg/swap";

  services.fwupd.enable = true;

  # AMD Ryzen 7040: power-profiles-daemon, not tlp
  services.power-profiles-daemon.enable = true;
  services.tlp.enable = false;

  services.fstrim.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.fprintd.enable = true;  # Goodix fingerprint reader
}
```

Run `sudo fwupdmgr update` after first boot. Test hibernation with `systemctl hibernate` — the machine should write its image to encrypted swap, power off fully, and restore on next unlock.

---

## Phase 4: niri + DankMaterialShell + Greeter

### System-level (in `configuration.nix`)

```nix
{
  programs.niri.enable = true;

  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/scott";
    configFiles = [ "/home/scott/.config/DankMaterialShell/settings.json" ];
    logs = { save = true; path = "/tmp/dms-greeter.log"; };
  };

  systemd.user.services.niri-flake-polkit.enable = false;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk xdg-desktop-portal-gnome ];
  };

  services.gnome.gnome-keyring.enable = true;
  services.accounts-daemon.enable = true;  # required for DMS profile pictures
  programs.dconf.enable = true;

  # Tear out GNOME from the Calamares install
  services.xserver.enable = false;
  services.displayManager.gdm.enable = false;
  services.desktopManager.gnome.enable = false;
}
```

### User-level (in `home.nix`) — base DMS setup

```nix
{ inputs, pkgs, ... }:
{
  home.username = "scott";
  home.homeDirectory = "/home/scott";
  home.stateVersion = "26.05";

  imports = [
    inputs.dms.homeModules.dank-material-shell
    inputs.dms.homeModules.niri
  ];

  programs.dank-material-shell = {
    enable = true;
    enableSystemMonitoring = true;
    niri = {
      enableKeybinds = true;
      enableSpawn = true;
    };
  };

  programs.home-manager.enable = true;
}
```

---

## Phase 5: GUI Application Stack

Everything the bootstrap script installs as a GUI, translated to Nix. Add to `configuration.nix` under `environment.systemPackages`:

```nix
{
  # System-wide GUI apps (available to all users)
  environment.systemPackages = with pkgs; [
    _1password-gui
    chromium
    discord
    localsend
    obsidian
    lmstudio              # unfree; works on x86_64-linux
    rpi-imager
    slack
    signal-desktop
    typora                # unfree
    zoom-us
  ];

  # 1Password CLI + browser integration
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "scott" ];
  };
}
```

### Items the script handles that don't fit `environment.systemPackages`

| Script item | Nix equivalent | Notes |
|---|---|---|
| Docker Desktop | `virtualisation.docker.enable = true` + add user to `docker` group | See Phase 8. Native daemon; no Docker Desktop GUI on Linux is needed |
| Ollama (GUI) | `services.ollama.enable = true` | See Phase 8 — runs as a system service, not a GUI |
| Playdate Simulator | Not in nixpkgs | One-shot install (Phase 11) |
| CyberChef | Not in nixpkgs | One-shot install (Phase 11) |
| VoxType | macOS-only | Skip |

---

## Phase 6: CLI & TUI Tools

Add to `home.nix` under `home.packages`. All CLIs from the script:

```nix
{
  home.packages = with pkgs; [
    # Core CLI from the bootstrap script
    neovim
    mise
    typst
    yara-x                # binary is `yr`
    gum
    crush                 # charmbracelet/crush
    glow
    lazygit
    lazydocker
    btop
    fastfetch
    jq
    git
    curl
    unzip

    # The script installs these via `programs.zoxide` etc., but listing for clarity
    zoxide
    fzf
    eza
    fd

    # qq (JFryy) — JSON/YAML pretty-printer; nixpkgs has it as `qq-cli`
    qq-cli

    # Wayland/Niri ergonomics
    wl-clipboard
    brightnessctl
    playerctl
    alacritty
    foot
    fuzzel
    matugen
    cava
    xwayland-satellite
  ];
}
```

### CLIs not in nixpkgs

| Script item | Workaround |
|---|---|
| `q-text-as-data` | `pipx install q-text-as-data` after `home.packages` includes `pipx` |
| `jsongrep` | `pipx install jsongrep` |

Add to `home.nix`:

```nix
{
  home.packages = with pkgs; [ pipx ];
  home.activation.installPipxTools = {
    after = [ "writeBoundary" ];
    before = [];
    data = ''
      export PATH="$HOME/.local/bin:$PATH"
      ${pkgs.pipx}/bin/pipx install --force q-text-as-data >/dev/null 2>&1 || true
      ${pkgs.pipx}/bin/pipx install --force jsongrep >/dev/null 2>&1 || true
    '';
  };
}
```

The activation hook keeps these idempotent across rebuilds — matches the script's behavior.

---

## Phase 7: Runtimes & AI CLIs

The script uses `mise` to manage Python/Node/Go, then `npm install -g` for Claude Code and Gemini CLI. On NixOS, two clean paths:

### Option A — Nix-managed AI CLIs (recommended)

```nix
# in home.nix
{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    # Nix-packaged versions, updated on nixpkgs cadence
    claude-code
    gemini-cli
  ];
}
```

### Option B — Hourly-updated Claude Code via flake

```nix
{ inputs, pkgs, system, ... }:
{
  home.packages = [
    inputs.claude-code-nix.packages.${pkgs.system}.claude-code
    pkgs.gemini-cli
  ];
}
```

### Mise for project-local runtimes

Mise is still the right tool for per-project Python/Node/Go pins; just install it via Nix and let mise manage versions:

```nix
{
  programs.mise = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    globalConfig = {
      tools = {
        python = "latest";
        node = "lts";
        go = "latest";
      };
    };
  };
}
```

On first rebuild, mise auto-installs the global tools.

---

## Phase 8: Services (Docker + Ollama)

In `configuration.nix`:

```nix
{
  # Docker — native daemon; no Docker Desktop needed
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };
  users.users.scott.extraGroups = [ "docker" "wheel" "networkmanager" "video" ];

  # Ollama as a system service with AMD GPU acceleration
  services.ollama = {
    enable = true;
    acceleration = "rocm";   # Framework 13 AMD has Radeon 780M iGPU
    # Use "cpu" if rocm causes issues
  };
}
```

Pull models the same way the script's TODO suggests:
```bash
ollama pull llama3.2
ollama pull qwen2.5-coder
```

---

## Phase 9: NeoVim + LazyVim

The script clones the LazyVim starter to `~/.config/nvim`. On NixOS, install neovim via Nix and clone the starter once via a home-manager activation:

```nix
# already in home.packages: neovim

{
  home.activation.lazyvimStarter = {
    after = [ "writeBoundary" ];
    before = [];
    data = ''
      if [ ! -e "$HOME/.config/nvim" ]; then
        ${pkgs.git}/bin/git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
        rm -rf "$HOME/.config/nvim/.git"
      fi
    '';
  };
}
```

This matches the script: clones if not present, leaves existing config alone.

---

## Phase 10: Shell, Aliases, Integrations

The script writes to `~/.zshrc` or `~/.bashrc`. On NixOS, home-manager owns these via `programs.*` modules:

```nix
# in home.nix
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      tree = "eza --tree";
      cat = "bat";
    };

    initContent = ''
      # Match the script's intent: eza, zoxide, fzf, mise
      bindkey -e
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    options = [ "--cmd cd" ];  # cd → zoxide, matching the script
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.bat.enable = true;
  programs.starship.enable = true;
}
```

Set zsh as default shell at the system level:

```nix
# configuration.nix
{
  programs.zsh.enable = true;
  users.users.scott.shell = pkgs.zsh;
  environment.shells = [ pkgs.zsh ];
}
```

### Natural scroll for niri

Add to your niri config (via the niri-flake home-manager module, which validates the schema at build time):

```nix
# in home.nix, after the dms imports
{
  programs.niri.settings = {
    input.touchpad = {
      tap = true;
      natural-scroll = true;   # matches the script's macOS / Linux intent
      dwt = true;              # disable while typing
    };
  };
}
```

---

## Phase 11: Imperative Add-ons (CyberChef, Playdate Simulator)

These aren't in nixpkgs. Match the script's behavior with a small home-manager activation:

```nix
{
  home.activation.cyberchef = {
    after = [ "writeBoundary" ];
    before = [];
    data = ''
      DEST="$HOME/.local/share/cyberchef"
      LAUNCHER="$HOME/.local/bin/cyberchef"
      if [ ! -x "$LAUNCHER" ] || [ ! -d "$DEST" ]; then
        TMP=$(${pkgs.coreutils}/bin/mktemp -d)
        URL=$(${pkgs.curl}/bin/curl -fsSL https://api.github.com/repos/gchq/CyberChef/releases/latest \
              | ${pkgs.gnugrep}/bin/grep -oE '"browser_download_url": *"[^"]+\.zip"' \
              | ${pkgs.coreutils}/bin/head -1 \
              | ${pkgs.gnused}/bin/sed -E 's/.*"(https[^"]+)".*/\1/')
        [ -z "$URL" ] && exit 0
        ${pkgs.curl}/bin/curl -fsSL -o "$TMP/cc.zip" "$URL" || exit 0
        ${pkgs.coreutils}/bin/mkdir -p "$DEST" "$HOME/.local/bin"
        ${pkgs.unzip}/bin/unzip -q -o "$TMP/cc.zip" -d "$DEST"
        IDX=$(${pkgs.findutils}/bin/find "$DEST" -maxdepth 3 -name 'CyberChef_v*.html' -print -quit)
        [ -z "$IDX" ] && IDX=$(${pkgs.findutils}/bin/find "$DEST" -maxdepth 3 -name 'index.html' -print -quit)
        if [ -n "$IDX" ]; then
          ${pkgs.coreutils}/bin/cat > "$LAUNCHER" <<LAUNCH
#!/usr/bin/env bash
xdg-open "$IDX"
LAUNCH
          ${pkgs.coreutils}/bin/chmod +x "$LAUNCHER"
        fi
        ${pkgs.coreutils}/bin/rm -rf "$TMP"
      fi
    '';
  };
}
```

**Playdate Simulator**: Panic does not ship a Linux build separate from the full SDK, and the SDK isn't packaged. Download from [play.date/dev](https://play.date/dev/) manually after install; the SDK will run from `~/playdate-sdk` without further integration. Track this as a one-time manual step in TODO.md.

---

## Phase 12: TODO.md

Match the script's TODO.md exactly so muscle memory carries over. Activation hook drops it once:

```nix
{
  home.activation.todoMd = {
    after = [ "writeBoundary" ];
    before = [];
    data = ''
      if [ ! -f "$HOME/TODO.md" ]; then
        ${pkgs.coreutils}/bin/cat > "$HOME/TODO.md" <<'TODO'
# Post-bootstrap TODO

Things the flake can't do for you.

- [ ] Connect to Wifi (or verify NetworkManager picked it up)
- [ ] Sign into 1Password (desktop + Chromium extension)
- [ ] Sign into Gmail
- [ ] Sign into GitHub
  - [ ] `gh auth login`
- [ ] Set wallpaper (DMS picks Material You theme from it)
- [ ] Set up Obsidian Sync (and enable Iconize community plugin)
- [ ] Register Typora license
- [ ] Install browser extensions in Chromium:
  - [ ] 1Password
  - [ ] Obsidian Web Clipper
  - [ ] Instapaper
- [ ] Sign in to Slack, Discord, Signal, Zoom
- [ ] Download Playdate Simulator from https://play.date/dev/
- [ ] Pull Ollama models: `ollama pull llama3.2` etc.
- [ ] Authenticate Claude Code: `claude` and follow prompts
- [ ] Authenticate Gemini CLI: `gemini auth`
- [ ] Verify `dms doctor -v` reports green
- [ ] Run `sudo fwupdmgr update` for any BIOS/EC updates
TODO
      fi
    '';
  };
}
```

---

## Verification

```bash
# Encryption: confirm root + swap are LUKS-backed under one container
lsblk                          # vg-root and vg-swap sit under cryptsystem (LUKS)
sudo cryptsetup status cryptsystem

# Hibernation: resume target set, swap active and large enough
cat /sys/power/resume          # non-zero device
swapon --show                  # 92G swap present
systemctl hibernate            # should power off fully, then restore on unlock

# Hardware module loaded
systemd-analyze cat-config etc/nixos | grep framework

# Power profiles working, TLP not loaded
powerprofilesctl get
systemctl status tlp 2>&1 | head -2

# Kernel 6.12+ floor
uname -r

# Firmware
fwupdmgr get-devices && fwupdmgr update

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

---

## Known Gotchas

1. **niri-flake niri-stable is on 25.08 but DMS needs 25.11.** Use `niri-unstable` from the flake or the version in nixpkgs unstable. Don't mix.
2. **Native module vs flake module for DMS:** the nixpkgs unstable `programs.dank-material-shell` works; the flake gives DMS git head and `niri.enableKeybinds`. Plan uses the flake.
3. **Empty `binds.kdl` on flake install** (AvengeMedia/DankMaterialShell #1586): let `niri.enableKeybinds = true` handle it; if binds still empty, copy DMS's default binds.kdl manually.
4. **Keep a recovery USB.** With an encrypted root, a broken boot chain (especially after enabling Secure Boot) means recovering from the live ISO: `cryptsetup open` → `vgchange -ay` → mount → roll back. The `secure-boot.md` recovery section has the exact commands.
5. **lmstudio is unfree** — `nixpkgs.config.allowUnfree = true;` is mandatory.
6. **Ollama ROCm on Radeon 780M** is hit-or-miss. If you see crashes, swap `acceleration = "cpu"` and confirm Vulkan instead.
7. **Claude Code via Nix bundles its own Node** — your project's npm/node from mise stays untouched. This is intentional and prevents the "wrong shell" error that affected earlier Nix packaging.
8. **Activation hooks run as the user, not root** — use absolute Nix store paths for any binary (the example hooks above do this).
9. **Secure Boot is a post-install project** (full steps in `secure-boot.md`). Get the encrypted system booting first, then uncomment the lanzaboote input in `flake.nix`, the lanzaboote block in `configuration.nix` (and add `lib` to its function args), run `sbctl create-keys` → rebuild → `sbctl enroll-keys --microsoft` → enable Secure Boot in BIOS. Never enable Secure Boot in BIOS before keys are enrolled.
10. **GNOME leftovers** only apply if you ever ran the Calamares route. The manual install in Phase 1 never installs GNOME, so there's nothing to garbage-collect on that front.
11. **Hibernation needs swap ≥ RAM image.** 92 GiB is set as requested. If you have 96 GB RAM and hibernate from a near-full state, the image can exceed swap and hibernation aborts (you stay running, no data loss). Bump the swap LV if you routinely run RAM that hot.
12. **Don't use random-key swap** (`randomEncryption`). It can't survive the power cycle hibernation requires. The swap must live inside the persistent LUKS container, which the Phase 1 layout ensures.

---

## Migration from your previous Arch+DankLinux Setup

Two things carry over cleanly:

- **DMS settings.** Copy `~/.config/DankMaterialShell/settings.json` and `dms-colors.json` from the Arch install. Drop them in the same path on NixOS; `configFiles` in the greeter config will sync them.
- **niri config.** Copy `~/.config/niri/config.kdl`. With `enableKeybinds = true`, DMS overwrites the bind section — back up first if you had custom binds.

What doesn't carry: any `dankinstall`-managed system packages. On NixOS those live in the flake, not on disk.

---

## References

- [NixOS on the Framework Laptop 13 (Framework Guides)](https://guides.frame.work/Guide/NixOS+on+the+Framework+Laptop+13/400)
- [NixOS Wiki — Hardware/Framework/Laptop 13](https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_13)
- [nixos-hardware framework-13-7040-amd module](https://github.com/NixOS/nixos-hardware/tree/master/framework/13-inch/7040-amd)
- [DankMaterialShell — NixOS Flake install](https://danklinux.com/docs/dankmaterialshell/nixos-flake)
- [DankGreeter — NixOS install](https://danklinux.com/docs/dankgreeter/nixos)
- [niri-flake (sodiboo)](https://github.com/sodiboo/niri-flake)
- [niri Getting Started](https://niri-wm.github.io/niri/Getting-Started.html)
- [claude-code-nix (sadjow) — hourly-updated flake](https://github.com/sadjow/claude-code-nix)
- [home-manager manual — activation hooks](https://nix-community.github.io/home-manager/)
