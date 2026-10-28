# System-level configuration for the Framework 13 AMD.
# User-level packages and dotfiles live in home.nix.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # Mintplex-Labs/anything-llm — Desktop app packaged from the upstream
  # AppImage release. Not in nixpkgs (checked: no `anythingllm` / `anythingllm-desktop`
  # attrs). appimageTools.wrapType2 mounts the AppImage into an FHS-like
  # runtime so the bundled Chromium + Node stack starts on NixOS.
  # `--no-sandbox` is what upstream's .desktop ships — Chromium's SUID
  # sandbox depends on chrome-sandbox owning setuid-root, which AppImage
  # extraction on NixOS can't guarantee. Trade-off is documented; the
  # workspace itself still lives under $HOME.
  # Version bump: change `version`, run
  #   nix-prefetch-url --type sha256 <url>
  # and re-encode with `nix hash to-sri --type sha256 <hash>`.
  anythingllm-desktop =
    let
      pname = "anythingllm-desktop";
      version = "1.16.2";
      src = pkgs.fetchurl {
        url = "https://github.com/Mintplex-Labs/anything-llm/releases/download/v${version}/AnythingLLMDesktop.AppImage";
        hash = "sha256-QKEW6MW5TI+gA7zSz8ves5n7zGUMfC4qvb8fL5hUB70=";
      };
      contents = pkgs.appimageTools.extractType2 { inherit pname version src; };
    in
    pkgs.appimageTools.wrapType2 {
      inherit pname version src;
      extraInstallCommands = ''
        install -Dm644 ${contents}/${pname}.desktop \
          $out/share/applications/${pname}.desktop
        substituteInPlace $out/share/applications/${pname}.desktop \
          --replace-fail 'Exec=AppRun' 'Exec=${pname}'
        install -Dm644 ${contents}/usr/share/icons/hicolor/0x0/apps/${pname}.png \
          $out/share/icons/hicolor/512x512/apps/${pname}.png
      '';
      meta = {
        description = "AnythingLLM — all-in-one local RAG / agent chat desktop app";
        homepage = "https://anythingllm.com/";
        license = lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
        mainProgram = "anythingllm-desktop";
      };
    };
in
{
  ############################################################
  # Nix / nixpkgs
  ############################################################
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # Default download buffer is 1 MiB, which fills constantly on big builds
  # (first install, niri/noctalia/claude-code together). 256 MiB silences the
  # "download buffer is full" warnings without meaningful memory cost.
  nix.settings.download-buffer-size = 256 * 1024 * 1024;
  # Weekly GC keeps /nix/store bounded; the 30-day window preserves enough
  # rollback headroom for a bad kernel or flake bump.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = true; # lmstudio, typora, 1password, spotify
  system.stateVersion = "26.05";

  ############################################################
  # Boot — systemd-boot now; lanzaboote later (see SECURE BOOT)
  ############################################################
  boot.loader.systemd-boot.enable = true;
  # Cap /boot entries. The ESP is 1G; each generation writes a kernel + initrd
  # + entry. 10 entries ≈ 30 days of weekly rebuilds and keeps /boot well under
  # the fail line where nixos-rebuild switch dies mid-activation.
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # PINNED to the 7.2 series — deliberately NOT linuxPackages_latest.
  #
  # linuxPackages_latest hands you whatever major kernel nixpkgs ships at the
  # moment you update, unreviewed. On 2026-10-27 that silently moved this
  # machine 7.2.10 -> 7.3.0 as part of a routine input bump, and the first
  # suspend-then-hibernate escalation on 7.3.0 froze the machine hard at
  # `PM: hibernation: hibernation entry` — it had to be power-cycled, and the
  # next boot was cold, not a resume.
  #
  # Evidence it is the kernel and not userspace: hibernation succeeded on
  # 7.2.10 that same morning ("Allocated 38910536 kbytes in 9.55 seconds",
  # then `hibernation exit`), and the freeze happens after userspace is
  # frozen, so no compositor or shell code is running at that point.
  # amdgpu + hibernate on this hardware has a long tail of trouble — see
  # nixpkgs#413932, "black screen/freeze after wake up from hibernate on
  # amdgpu/framework laptop 13", open since 2025.
  #
  # This box hibernates on a 15-minute idle escalation, so a broken hibernate
  # path does not announce itself until you walk away — which is exactly how
  # it bit us. Treat a kernel move as a change to TEST (suspend, wait out
  # HibernateDelaySec, confirm resume), not a free ride on `nix flake update`.
  #
  # Note nixpkgs' 7.2 series is 7.2.11 here; 7.2.10 exactly would require
  # pinning nixpkgs itself. Same series, one patch release on.
  #
  # Revisit when a later kernel is known-good on Framework 13 AMD: bump to
  # linuxPackages_7_3 (or newer) deliberately and hibernate-test it before
  # trusting it.
  #
  # 6.12+ floor for Ryzen 7040.
  #
  # framework-laptop-kmod is patched here to emit a module-signing
  # certificate. nixpkgs now builds kernel modules with `cmd_sign` pointing at
  # `kmodigest` (pkgs/os-specific/linux/kernel/common-flags.nix), and
  # aggregateModules concatenates one `<module>.ko.cer` per OUT-OF-TREE module
  # into modules.cer (pkgs/os-specific/linux/kmod/aggregator.nix). Modules
  # whose package hand-rolls an installPhase — rather than running
  # `make modules_install`, which is what triggers Kbuild's signing step —
  # never produce that .cer, so the whole linux-<ver>-modules build dies with:
  #
  #   cat: extra/framework_laptop.ko.cer: No such file or directory
  #
  # Upstream bug, not ours: nixpkgs#575192, with the real fix (a
  # kernelModuleInstallHook) in flight as nixpkgs#578004 — open, unmerged as
  # of 2026-10-27. tuxedo-drivers is broken the same way (nixpkgs#576266).
  # Running kmodigest by hand produces the .cer the aggregator wants; drop
  # this whole block once #578004 lands.
  boot.kernelPackages = pkgs.linuxPackages_7_2.extend (
    _kfinal: kprev: {
      framework-laptop-kmod = kprev.framework-laptop-kmod.overrideAttrs (_old: {
        installPhase = ''
          runHook preInstall
          ${lib.getExe pkgs.kmodigest} framework_laptop.ko
          install -D -t $out/lib/modules/${kprev.kernel.modDirVersion}/extra \
            framework_laptop.ko framework_laptop.ko.cer
          runHook postInstall
        '';
      });
    }
  );

  # FAT32 doesn't support Unix perms, so the ESP defaults to world-readable.
  # bootctl writes a kernel random-seed file in /boot/loader and (correctly)
  # complains: any local user could read the seed and learn things about the
  # kernel's entropy pool. Mount /boot with restrictive masks so files and
  # directories under the ESP are owner-only (root). Merges with the
  # /boot entry that nixos-generate-config wrote to hardware-configuration.nix.
  fileSystems."/boot".options = [
    "fmask=0077"
    "dmask=0077"
  ];

  ############################################################
  # Disk encryption + hibernation (suspend-to-disk)
  #
  # Default (Calamares install): ESP + LUKS-encrypted ext4 root. If you
  # selected the "Swap with Hibernate" option in Calamares, a swap
  # partition sized for the hibernation image is also created and
  # nixos-generate-config writes it into hardware-configuration.nix's
  # `swapDevices`. The kernel resumes from the first listed swap device
  # by default — no boot.resumeDevice needed. Verify after first boot
  # with `systemctl hibernate`.
  #
  # If Calamares' swap detection or hibernation doesn't pick up
  # automatically, uncomment one of these lines pointing at YOUR machine's
  # swap device (run `swapon --show` to find it):
  #
  #   boot.resumeDevice = "/dev/disk/by-uuid/<your-swap-uuid>";
  #
  # If you used INSTALL.md's manual LVM-on-LUKS appendix instead, the
  # stable LVM path is:
  #
  #   boot.resumeDevice = "/dev/vg/swap";

  # The per-host hibernation swap unlock and boot.resumeDevice are
  # machine-specific (LUKS UUIDs differ per disk), so they live in the host's
  # own module: hosts/<hostname>/default.nix. See hosts/README.md for how a
  # new machine sets them up.

  # Idle escalation timing (Noctalia in home.nix triggers the actions, via
  # programs.noctalia.settings.idle.behavior): lock @ 10 min, then
  # `systemctl suspend-then-hibernate` @ 15 min. That
  # suspends to RAM and, HibernateDelaySec later, wakes and hibernates to
  # disk — so hibernate lands at 3h 15m total idle. The long delay favors
  # quick lid-open resume for the common short-break case; hibernate still
  # catches the laptop before the battery drains overnight.
  systemd.sleep.settings.Sleep.HibernateDelaySec = 10800; # 3h

  # Closing the lid suspends to RAM, then hibernates HibernateDelaySec later —
  # the same suspend-then-hibernate escalation the idle timeout uses. Applies
  # on battery and AC (HandleLidSwitchExternalPower defaults to this value);
  # HandleLidSwitchDocked defaults to "ignore", so an external display keeps
  # the session alive with the lid shut.
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";

  ############################################################
  # SECURE BOOT (lanzaboote) — uncomment after install, see secure-boot.md
  ############################################################
  # environment.systemPackages = with pkgs; [ sbctl ]; # merge into the list below
  # boot.loader.systemd-boot.enable = lib.mkForce false;
  # boot.lanzaboote = {
  #   enable = true;
  #   pkiBundle = "/var/lib/sbctl";
  # };

  ############################################################
  # Framework 13 AMD power & firmware
  ############################################################
  services.fwupd.enable = true;
  services.power-profiles-daemon.enable = true; # NOT tlp on Ryzen 7040
  services.tlp.enable = false;
  services.fstrim.enable = true;
  # Noctalia's battery widget (and any UPower consumer) needs the daemon
  # registered on the system bus; without it the shell logs
  # `org.freedesktop.DBus.Error.ServiceUnknown` and silently drops battery
  # state. power-profiles-daemon doesn't pull it in on its own.
  services.upower.enable = true;

  ############################################################
  # Backups — Time Machine-style, to an attached USB drive
  #
  # Shape: plug the drive in and it backs itself up; unplug and nothing
  # complains. restic gives versioned, deduplicated, encrypted snapshots, and
  # `restic mount` exposes every snapshot as a browsable directory tree — the
  # "go back in time" part of the Time Machine experience.
  #
  # The drive is found by FILESYSTEM LABEL, not device path, so any port or
  # enclosure works. Prepare a drive once with (destroys everything on it):
  #   sudo mkfs.ext4 -L timemachine /dev/sdX1
  #
  # The repo itself is encrypted by restic, so a lost or stolen drive leaks
  # nothing without the password — which is why the drive's own filesystem
  # doesn't need LUKS on top.
  ############################################################

  # noauto: don't try at boot, since the drive usually isn't there. nofail:
  # never block boot on it. The udev rule below is what actually mounts it,
  # on plug-in.
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-label/timemachine";
    fsType = "ext4";
    options = [
      "nofail"
      "noauto"
    ];
  };

  # Plugging the drive in starts the mount unit. systemd translates
  # /mnt/backup into the unit name mnt-backup.mount.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="timemachine", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mnt-backup.mount"
  '';

  services.restic.backups.home = {
    repository = "/mnt/backup/restic/${config.networking.hostName}";
    passwordFile = "/etc/restic/home-password";
    # Create the repo on first run so there's no manual `restic init` step.
    initialize = true;
    paths = [ "/home/sroberts" ];

    # Excludes. Measured 2026-09-05: $HOME was 31G, of which ~26G is
    # re-fetchable. What's left (~5G) is the genuinely irreplaceable part —
    # Documents, source, keys, ~/.claude, this flake.
    exclude = [
      # Model weights — large and re-downloadable.
      "/home/sroberts/.lmstudio"
      "/home/sroberts/.ollama"
      # Caches.
      "/home/sroberts/.cache"
      "/home/sroberts/.npm"
      "/home/sroberts/.local/share/Trash"
      "/home/sroberts/.zoom"
      # Chat/browser app state: big, and all of it re-syncs on next sign-in.
      # Signal in particular is re-linked from the phone, not restored.
      "/home/sroberts/.config/Signal"
      "/home/sroberts/.config/chromium"
      "/home/sroberts/.config/Slack"
      "/home/sroberts/.config/discord"
      "/home/sroberts/Downloads"
      # Build artefacts / dependency trees — rebuildable from the source
      # that IS backed up, and by far the worst churn-to-value ratio.
      "**/node_modules"
      "**/.venv"
      "**/__pycache__"
      "**/target"
      "**/.direnv"
      "*.pyc"
    ];

    # Hourly while the drive is attached. Persistent=true means a missed
    # window (laptop asleep, drive unplugged) runs once on the next mount
    # rather than being skipped silently.
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };

    # Time Machine-ish thinning: dense recent history, sparse older.
    pruneOpts = [
      "--keep-hourly 24"
      "--keep-daily 14"
      "--keep-weekly 8"
      "--keep-monthly 12"
    ];
  };

  systemd.services.restic-backups-home = {
    # Skip silently when the drive isn't attached. A Condition makes the unit
    # report "condition failed" and exit 0 — unlike RequiresMountsFor, which
    # would mark it failed and generate an alert every hour the drive is out.
    unitConfig.ConditionPathIsMountPoint = "/mnt/backup";
    # Back up as soon as the drive appears, not just on the hourly tick.
    wantedBy = [ "mnt-backup.mount" ];
  };

  ############################################################
  # Audio (PipeWire)
  ############################################################
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  ############################################################
  # Locale + timezone
  # America/New_York follows EST/EDT (DST-aware). en_US.UTF-8 gives
  # imperial measurement units, US paper sizes, etc.
  ############################################################
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  ############################################################
  # Networking, Bluetooth, fingerprint
  ############################################################
  # networking.hostName is set per-host in hosts/<hostname>/default.nix.
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;
  # tally's soft-pad listener (systemd.user.services.tally in home.nix runs
  # `tally serve --remote`): TLS WebSocket on 47824 for paired vibepad phones,
  # plus mDNS on 5353 so the phone can find the laptop via Bonjour
  # (_tally._tcp) when its address changes. Auth is the pinned cert + token
  # from `tally pair`, so the open port alone grants nothing.
  networking.firewall.allowedTCPPorts = [ 47824 ];
  networking.firewall.allowedUDPPorts = [ 5353 ];
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # Goodix fingerprint reader. fprintd runs the daemon; the PAM hooks
  # below let it stand in for a password. Enroll once with `fprintd-enroll`
  # before the integrations are useful.
  services.fprintd.enable = true;
  security.pam.services = {
    sudo.fprintAuth = true; # sudo prompt
    login.fprintAuth = true; # TTY login
    su.fprintAuth = true; # su to another user
    polkit-1.fprintAuth = true; # GUI privilege prompts (e.g. password change)
    greetd.fprintAuth = true; # noctalia-greeter at the login screen
    # Noctalia's lock screen uses /etc/pam.d/login, so login.fprintAuth above
    # is what lights up the lock screen's fingerprint path. In v5 the lock
    # screen's auth is native (C++): it arms pam_fprintd at lock time and
    # manages the fingerprint-vs-password handoff itself. The v4 QML flags that
    # used to gate this (`allowPasswordWithFprintd` / `autoStartAuth`, once
    # asserted by home.activation.noctaliaConfigSeed) no longer exist and are
    # not needed. Re-verify the touch-to-unlock path after any Noctalia bump —
    # this system-side fprintd wiring assumes Noctalia arms the reader for us.
  };

  ############################################################
  # niri + greetd (noctalia-greeter) login
  ############################################################
  programs.niri.enable = true;
  # niri-flake's `programs.niri.package` defaults to niri-stable (v25.08).
  # Pin to niri-unstable because Quickshell-based shells (Noctalia and the
  # ecosystem that shares its Wayland-protocol footprint) track niri's
  # latest, and the stable tag lags. Also disable the in-build cargo test
  # suite — those tests sometimes SIGABRT inside the Nix build sandbox
  # (filesystem assumptions that don't hold), even when the binary itself
  # works at runtime. We don't gain confidence by running niri's own tests
  # during our system build.
  #
  # Built with OUR nixpkgs, not niri-flake's: nixpkgs' `niri` recipe fed
  # niri-flake's niri-unstable source + vendored crates. niri-flake doesn't
  # follow our nixpkgs (see flake.nix), so its prebuilt niri carries its own
  # older glibc — and niri dlopens the system mesa from /run/opengl-driver.
  # Once our nixpkgs' mesa needed a newer glibc than niri's (the 2026-10-15
  # bump: mesa wants GLIBC_2.43, niri-flake's pin is 2.42), mesa failed to
  # load, niri came up with no render device, and login was a black screen.
  # Building niri here keeps niri, mesa and glibc on one nixpkgs. nixpkgs'
  # recipe already links libdisplay-info 0.3, sidestepping the _0_2 removal
  # that blocks the follows. Cost: niri builds from source (no cache hit).
  programs.niri.package =
    let
      unstable = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;
    in
    pkgs.niri.overrideAttrs (old: {
      inherit (unstable) src version cargoDeps;
      doCheck = false;
      # nixpkgs' versionCheckHook expects `niri --version` to print our
      # `version` (unstable-…), but niri reports its Cargo version (26.04).
      doInstallCheck = false;
    });

  # noctalia-greeter on tty1 — a Quickshell-based login screen that mirrors
  # Noctalia Shell's palette/wallpaper (imperative sync via Settings → Shell →
  # Security → Noctalia Greeter → Sync Now — see TODO.md). The greeter's
  # NixOS module sets services.greetd.enable + default_session.command with
  # mkDefault, so no explicit greetd block is needed here.
  #   - allow_empty_password: fprintd's PAM module answers the password
  #     prompt with an empty reply after a fingerprint match; without this
  #     the greeter rejects that reply as invalid credentials.
  #   - keyboard.layout: greeter runs before the session's input config, so
  #     the layout has to be told explicitly.
  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      auth.allow_empty_password = true;
      keyboard.layout = "us";
    };
  };

  # Polkit auth agent: defer to Noctalia's native polkit agent (enabled via
  # programs.noctalia.settings.shell.polkit_agent in home.nix) rather than
  # niri-flake's bundled polkit-kde-agent service. Two agents would race on the
  # org.freedesktop.PolicyKit1.AuthenticationAgent bus name; the upstream
  # plugin docs explicitly require the other agent to be disabled. Force
  # the unit off — niri-flake hard-codes `wantedBy = [ "niri.service" ]`
  # with no opt-out option, so this is the only knob.
  systemd.user.services.niri-flake-polkit.enable = lib.mkForce false;

  # Tear out GNOME left behind by the Calamares base install. Harmless
  # to keep on if you used the manual install path (nothing to disable).
  services.xserver.enable = false;
  services.displayManager.gdm.enable = false;
  services.desktopManager.gnome.enable = false;

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };

  services.gnome.gnome-keyring.enable = true;
  services.accounts-daemon.enable = true;
  programs.dconf.enable = true;

  # gvfs — the GNOME virtual filesystem daemon. Nautilus (in
  # environment.systemPackages) degrades quietly without it: no Trash, no
  # network mounts (SMB/SFTP), no MTP for phones. Nothing errors, the
  # features are simply absent from the UI, so this is easy to miss.
  services.gvfs.enable = true;

  ############################################################
  # Shell
  ############################################################
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  ############################################################
  # Non-Nix dynamic binaries (mise / pre-built toolchains)
  #
  # mise downloads upstream pre-built binaries — node from nodejs.org,
  # go from go.dev, python from python-build-standalone — that are all
  # linked against /lib64/ld-linux-x86-64.so.2 and a handful of common
  # shared libraries. NixOS doesn't have an FHS, so without a shim those
  # binaries fail to launch with "No such file or directory" pointing at
  # the linker. `programs.nix-ld` installs a stub at the canonical linker
  # path and uses the `libraries` list as the search path for the .so
  # files those binaries dlopen at runtime.
  #
  # Scope is intentional: this is only for mise-managed toolchains.
  # Everything Nix-native (everything in pkgs / home.packages) ignores
  # nix-ld and resolves through the usual store paths.
  ############################################################
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++ / libgcc_s — node's V8, many node native modules
      zlib # python zlib, node zlib bindings, gzipped tarballs unpacked at runtime
      openssl # python _ssl, node tls
      libffi # python ctypes
      ncurses # python _curses, readline backend
      readline # python readline
      bzip2 # python _bz2
      xz # python _lzma
      sqlite # python sqlite3
    ];
  };

  ############################################################
  # 1Password (GUI + CLI + browser integration)
  ############################################################
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "sroberts" ];
  };

  ############################################################
  # Chromium + auto-installed extensions
  ############################################################
  # `programs.chromium` only writes a managed-policy file under
  # /etc/chromium/policies — it does NOT install chromium. The package
  # itself still has to be added to environment.systemPackages below.
  # The policy pre-installs each extension ID at first launch and locks
  # installation, so the user can disable but not remove without
  # editing this file. One-time sign-in for each extension is still
  # required and lives in TODO.md.
  programs.chromium = {
    enable = true;
    extensions = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1Password
      "cnjifjpddelmedmihgijeibhnjfabmlf" # Obsidian Web Clipper
      "ldjkgaaoikpmhmkelcgkgacicjfbofhh" # Instapaper
    ];
  };

  ############################################################
  # Containers + local LLM serving
  ############################################################
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm; # Radeon 780M iGPU; switch to pkgs.ollama (cpu) or pkgs.ollama-vulkan if rocm crashes
    # Pulled on first start by ollama-model-loader.service.
    loadModels = [
      "llama3.2"
      "gemma4:latest"
      "gpt-oss:20b"
      "lfm2.5-thinking"
      # 27B, ~16.5 GB, 256K context, vision + tool use. Bound to crush's
      # large/coder role in home.nix. Comfortable here: 93 GB RAM, and the
      # 780M iGPU shares system memory rather than being capped at a fixed
      # VRAM size. `qwen3.8:27b` is the same manifest as `:latest`.
      "qwen3.8"
    ];
  };

  ############################################################
  # User
  ############################################################
  users.users.sroberts = {
    isNormalUser = true;
    description = "Scott";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "video"
      "input"
    ];
  };

  ############################################################
  # System-wide GUI applications
  ############################################################
  environment.systemPackages = with pkgs; [
    _1password-gui
    anythingllm-desktop
    chromium
    discord
    firefox
    localsend
    nautilus
    obsidian
    lmstudio
    rpi-imager
    slack
    signal-desktop
    spotify
    typora
    zed-editor
    zoom-us

    git
    curl
    wget
    unzip
    cryptsetup # handy for inspecting/managing the LUKS volume post-install
    # Framework EC monitor/control TUI: fan curves, battery charge limit,
    # thermals, keyboard backlight. Talks to the embedded controller directly,
    # so it needs root — run `sudo framework-tool-tui`. System-wide rather than
    # in home.packages for that reason.
    framework-tool-tui
    # The backup service brings its own restic; this is for driving the repo
    # by hand — `restic snapshots`, and `restic mount` to browse snapshots as
    # directories. Both need `--repo /mnt/backup/restic/<host>` and the
    # password file (see the Backups section above).
    restic
  ];

  ############################################################
  # Firmware blobs, fonts
  ############################################################
  hardware.enableRedistributableFirmware = true;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];
}
