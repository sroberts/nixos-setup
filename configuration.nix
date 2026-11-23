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
  # nh — friendlier front end for nixos-rebuild (`nh os switch` builds with
  # nix-output-monitor, shows a package diff, then elevates). `flake` sets
  # NH_FLAKE, so `nh os switch` needs no `.#<host>` and `os-update` (home.nix)
  # reads the same variable to find the repo — one place says where the
  # checkout lives.
  #
  # nh.clean stays OFF on purpose: nix.gc above already collects weekly, and
  # running two GC timers is exactly what the nh module warns about. nix.gc's
  # age-based `--delete-older-than 30d` is the policy this repo wants (it
  # pairs with systemd-boot.configurationLimit below), so there is nothing to
  # gain by swapping it for `nh clean all --keep-since`.
  programs.nh = {
    enable = true;
    flake = "${config.users.users.sroberts.home}/nixos-setup";
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

  # PINNED to the 6.18 LTS series — deliberately NOT linuxPackages_latest,
  # and spelled linuxPackages_6_18 rather than linuxPackages so a change of
  # nixpkgs' default kernel can't move it either.
  #
  # History: linuxPackages_latest hands you whatever major kernel nixpkgs
  # ships at the moment you update, unreviewed. On 2026-10-27 that silently
  # moved this machine 7.2.10 -> 7.3.0 as part of a routine input bump, and
  # the first suspend-then-hibernate escalation on 7.3.0 froze the machine
  # hard after `PM: hibernation: hibernation entry` — power-cycled, next boot
  # cold. 7.2.10 had hibernated that morning, so it was pinned to 7.2 (PR
  # #112) until nixpkgs removed 7.2 at end of life (2026-11).
  #
  # Why 6.18 LTS and not 7.3.x (researched 2026-11-20):
  #   - None of the 7.3.1-7.3.5 stable changelogs touches the hibernation
  #     core or amdgpu's S4 paths, so 7.3.5 should be assumed to hang like
  #     7.3.0 did. regzbot tracks no matching 7.3 regression.
  #   - 6.18's kernel/power/hibernate.c has been unchanged since Nov 2025; it
  #     predates the 7.2/7.3 image-preallocation reorder and the deadlock fix
  #     layered on top of it.
  #   - It carries the TTM swapout fix behind post-hibernate hard lockups on
  #     AMD APUs (drm/amd#5387): broken only in 6.18.57-58, fixed in 6.18.59.
  #   - Reports of hibernate working on 6.18 with Framework 13 7840U, and in
  #     nixpkgs#413932 ("fixed on 6.18.8").
  #   - LTS: no end-of-life removal breaking a flake update for years.
  #
  # If 6.18 hangs at hibernation entry too, suspect the amdgpu-with-a-
  # compositor intermittent S4 hang (pop-os/pop#4085, Phoenix 780M on
  # 7.0/7.1: fails only with a KMS client running) or the Wi-Fi/Bluetooth
  # drivers (unloading them pre-hibernate fixed it for several people in
  # nixpkgs#413932), not the kernel version. Test by hibernating from a TTY.
  #
  # This box hibernates on a 15-minute idle escalation, so a broken hibernate
  # path does not announce itself until you walk away — which is exactly how
  # it bit us. Treat a kernel move as a change to TEST (`systemctl
  # hibernate`, then a suspend-then-hibernate), not a free ride on
  # `nix flake update`.
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
  boot.kernelPackages = pkgs.linuxPackages_6_18.extend (
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
  # programs.noctalia.settings.idle.behavior): lock @ 10 min, screens off
  # @ 11 min, then `systemctl suspend-then-hibernate` @ 15 min — the last
  # step on battery only (suspendUnlessOnAc). That
  # suspends to RAM and, HibernateDelaySec later, wakes and hibernates to
  # disk — so hibernate lands at 3h 15m total idle. The long delay favors
  # quick lid-open resume for the common short-break case; hibernate still
  # catches the laptop before the battery drains overnight.
  systemd.sleep.settings.Sleep.HibernateDelaySec = 10800; # 3h

  # Lid close. On BATTERY this suspends to RAM, then hibernates
  # HibernateDelaySec later — the same escalation the idle timeout uses.
  #
  # On AC it is "ignore": plugged in, closing the lid leaves the machine
  # running. HandleLidSwitchExternalPower would otherwise inherit
  # HandleLidSwitch's value, which is how a plugged-in lid close used to
  # suspend. This matches the idle path, where suspendUnlessOnAc (home.nix)
  # skips the sleep step on AC — between the two, nothing puts this machine
  # to sleep while it has wall power. It still LOCKS on lid close (niri's
  # switch-events.lid-close in home.nix) and still turns its screens off on
  # idle, so "awake for long jobs" never means "open and lit".
  #
  # Consequence worth knowing: on AC with the lid shut and no external
  # display, the session stays live on a blanked internal panel. It still
  # locks (Noctalia's 10-min idle lock is not gated), so this is a power
  # choice, not a security hole.
  #
  # HandleLidSwitchDocked stays at its "ignore" default, so an external
  # display keeps the session alive with the lid shut regardless of power.
  #
  # To keep a long job alive on BATTERY with the lid shut, run it under
  # `keepawake <cmd…>` or toggle Mod+Alt+I (home.nix): a logind
  # handle-lid-switch block inhibitor makes logind skip this setting, while
  # niri still locks on lid close.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "ignore";
  };

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
  # tally's browser pad (`tally serve --web`) fetches its HTTPS certificate
  # with `tailscale cert` as the user, which on Linux needs the user to be
  # Tailscale's operator.
  services.tailscale.extraSetFlags = [ "--operator=sroberts" ];
  # The browser pad itself: HTTPS on 47825, reached by this machine's
  # MagicDNS name, so it opens on the tailnet only. Sign-in is a password
  # (`tally web`), so the open port alone grants nothing. Its port is opened
  # on tailscale0 with sshd's, below.
  # SSH, for remote login over the tailnet only. openFirewall is off so port
  # 22 stays closed on Wi-Fi/LAN; the per-interface rule opens it on
  # tailscale0 alone, so only this tailnet's devices can reach sshd. Keys
  # only (no passwords, no root); the allowed public keys are
  # users.users.sroberts.openssh.authorizedKeys below.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "sroberts" ];
    };
  };
  # Tailnet-only ports: sshd (22) and tally's browser pad (47825, above).
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    22
    47825
  ];
  # tally's soft-pad listener (systemd.user.services.tally in home.nix runs
  # `tally serve --remote --web`): TLS WebSocket on 47824 for paired vibepad
  # phones, plus mDNS on 5353 so the phone can find the laptop via Bonjour
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
    sudo.fprintAuth = true; # sudo prompt (Ctrl+C at the finger prompt → password)
    su.fprintAuth = true; # su to another user
    polkit-1.fprintAuth = true; # GUI privilege prompts (Noctalia's polkit agent)
    # `login` is deliberately password-only. Noctalia v5's lock screen drives
    # the reader itself over fprintd's D-Bus API (FingerprintAuthenticator),
    # and only sends the *typed password* through PAM, hardcoded to the
    # `login` service (src/shell/lockscreen/lock_screen.cpp). With
    # pam_fprintd at the top of `login`, a typed password stalled behind a
    # second "place your finger" wait (up to fprintd's 30s timeout x 3
    # tries) before pam_unix ever saw it — the "needs the finger even though
    # I typed the password" flakiness. Upstream's own comment there says to
    # strip pam_fprintd from `login` for exactly this reason.
    #
    # greetd's stack is just `substack login` (the greeter module renders
    # it that way, so a greetd.fprintAuth here is a no-op), which makes the
    # noctalia-greeter password-only too. That is intended: the greeter is
    # where pam_gnome_keyring unlocks the keyring, and it can only do that
    # with a password — a fingerprint login leaves the keyring locked.
    # Re-verify touch-to-unlock on the lock screen after any Noctalia bump.
    login.fprintAuth = false;
  };

  ############################################################
  # niri + greetd (noctalia-greeter) login
  ############################################################
  programs.niri.enable = true;
  # Pin to niri-unstable: Quickshell-based shells (Noctalia and the ecosystem
  # sharing its Wayland-protocol footprint) track niri's latest, and the
  # stable tag lags.
  #
  # This comes straight from niri-nix now. The previous arrangement — taking
  # niri-flake's source and rebuilding it with nixpkgs' recipe — existed only
  # to work around niri-flake: it pins `libdisplay-info_0_2` (removed from
  # nixpkgs), so it could not follow our nixpkgs, and the resulting glibc skew
  # against the system mesa niri dlopens black-screened login. niri-nix builds
  # against `libdisplay-info_0_3` and follows our nixpkgs, so niri, mesa and
  # glibc share one nixpkgs by construction and the override is unnecessary.
  #
  # Cost is unchanged: following nixpkgs means no niri-nix.cachix.org hit, so
  # niri builds from source — the same price the old workaround paid.
  #
  # No doCheck override: niri-nix's recipe already skips the sandbox-hostile
  # EGL tests (`checkFlags = [ "--skip=::egl" ]`), and the rest of niri's
  # cargo suite passes in the sandbox. (The home-manager side reuses this
  # exact package via osConfig for `niri validate`, so it stays in sync.)
  programs.niri.package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;

  # noctalia-greeter on tty1 — a Quickshell-based login screen that mirrors
  # Noctalia Shell's palette/wallpaper (imperative sync via Settings → Shell →
  # Security → Noctalia Greeter → Sync Now — see TODO.md). The greeter's
  # NixOS module sets services.greetd.enable + default_session.command with
  # mkDefault, so no explicit greetd block is needed here.
  #   - keyboard.layout: greeter runs before the session's input config, so
  #     the layout has to be told explicitly.
  services.displayManager.noctalia-greeter = {
    enable = true;
    # No auth.allow_empty_password: it existed for pam_fprintd's empty reply
    # after a finger match, and the greeter is password-only now (see the
    # login.fprintAuth comment above).
    settings.keyboard.layout = "us";
  };

  # Polkit auth agent: Noctalia's native one (programs.noctalia.settings.shell
  # .polkit_agent in home.nix). niri-nix, unlike niri-flake, ships no polkit
  # agent of its own, so there is nothing to disable here — don't add a
  # second agent, or the two race on the PolicyKit1 AuthenticationAgent name.

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

  # Screen recording backend for Noctalia's official `noctalia/screen_recorder`
  # plugin (enabled in home.nix, driven by Super+Alt+R / Super+Alt+Shift+R).
  # The plugin shells out to gpu-screen-recorder, which encodes on the GPU
  # (VAAPI on the Radeon 780M), so a recording costs almost no CPU.
  #
  # The binds record with the plugin's `focused` / `region` sources, which
  # make gpu-screen-recorder capture the output straight from KMS
  # (`-w eDP-1`): compositor-agnostic, no portal picker dialog on every
  # start, and no dependency on niri's PipeWire screencast path. KMS capture
  # needs CAP_SYS_ADMIN, which gpu-screen-recorder confines to a tiny helper
  # (`gsr-kms-server`). This module is what creates the setcap wrapper for
  # that helper in /run/wrappers/bin. Installing the bare package would make
  # every KMS recording fail, or fall back to a pkexec prompt.
  #
  # Why not wf-recorder: it needs wlr-screencopy, which niri supports, but it
  # has no bar indicator, no shell integration and no replay buffer. It would
  # also have needed a hand-rolled pidfile toggle script that the plugin
  # already provides.
  #
  # Privacy caveat: KMS reads the scanout buffer, so niri's
  # `block-out-from "screencast"` window rules do NOT apply to these
  # recordings. Whatever is on screen is recorded.
  programs.gpu-screen-recorder.enable = true;

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

  # NixOS's built-in command-not-found looks commands up in the
  # programs.sqlite that ships with a nixos *channel*; a flake system has no
  # channel, so it can only ever answer "not found". The zsh handler comes
  # from nix-index instead (prebuilt database via nix-index-database, set up
  # in home.nix). Disabled explicitly — not left to whatever nixpkgs defaults
  # to — so /etc/zshrc can never define a second, broken
  # command_not_found_handler competing with home-manager's.
  programs.command-not-found.enable = false;

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
      # d1 — 3.7 GB, multimodal (its manifest carries a `projector` layer
      # alongside the model). Pulled and available, but deliberately bound to
      # NO crush role: see home.nix, where the ollama provider leaves its
      # model list empty, so auto-discovery lists every pulled model in the
      # picker without any of them being wired to an agent role.
      "d1"

      # lfm3 and lfm3-audio are NOT here, and cannot be yet. Both are gated on
      # a newer runtime than nixpkgs ships:
      #
      #   Error: model requires ollama version v0.40.13 or newer
      #          (current version is v0.40.4)
      #
      # and this is not a pin we can escape by updating: nixos-unstable is at
      # ollama 0.40.11 as of 2026-11-02, still short of 0.40.13. Listing them
      # anyway is actively harmful rather than merely useless — the pull is a
      # hard error, so ollama-model-loader.service exits non-zero and systemd
      # restart-loops it indefinitely, which is exactly what happened when
      # they were first added here.
      #
      # Worth knowing for next time: `ollama pull` fails at the MANIFEST stage,
      # so this is not catchable by checking that the model exists in the
      # registry (all three returned HTTP 200 from
      # registry.ollama.ai/v2/library/<name>/manifests/latest). Only the pull,
      # or reading the required version out of the manifest, tells you.
      #
      # Revisit once nixpkgs carries ollama >= 0.40.13: re-add both names and
      # rebuild. `nix eval nixpkgs#ollama.version` is the one-line check.
      #
      # inkling-2-mini (~20 GB safetensors, vision + tools + thinking) is
      # waiting on the same thing: its config blob says `requires: 0.40.17`.
      # On 2026-11-22 nixos-unstable had 0.40.16 and only master had 0.40.17.
      # Add it with the flake update that brings 0.40.17 in.
    ];
  };

  ############################################################
  # User
  ############################################################
  users.users.sroberts = {
    # Public keys allowed to SSH in (services.openssh above). Public keys
    # are safe to commit; one line per client machine.
    openssh.authorizedKeys.keys = [
      # From github.com/sroberts.keys (2026-11-07).
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDD2UtEE/wZVLcQUgDqj60t+WUoPdLoURNlbXR6qtLe95ruHS6iy4pOa91yRx9fizPAixlj1FzPwt8JTrqpmHsGQfgTEAnmTvUBlDybefh6OFJV2F9VOV08teKtAw92360bH4dB3kln1Ku7t6cp5Zgj18SmUsUF6clHZ4fRYTfA32arITG++NXmrWWWGVz0EzdSK2Bc1M7BG+VWHmLxRA+yn2Ias5jsPnAPJQ+yyGEQvA1spcF+Wrx94PiPMJ7hkPmqGrrKnS5tiQhMwZnY2GQQv6Dr4yaSVNTQu3lexqw42GqaJ588KUiSMGtown85dWoqZj9ekNXKOcpsIfxvzG3p"
    ];
    isNormalUser = true;
    description = "Scott";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "video"
      # evdev access for voxtype's Right Ctrl push-to-talk listener
      # (services.voxtype in home.nix). Note what it grants: any process
      # running as this user can read raw keyboard events.
      "input"
    ];

    # herdr-core (home.nix) keeps coding agents running in the background,
    # and on first start it runs `loginctl enable-linger` for its own user so
    # the core outlives a logout. Declared here so the repo OWNS that fact
    # rather than discovering it: without this the binary writes
    # /var/lib/systemd/linger/sroberts behind Nix's back, and the running
    # system stops matching these files.
    #
    # The effect is not herdr-specific: user units in general survive logout
    # and start at boot. That is the point for an agent runner, but it is a
    # real change in scope — set this to false to opt out, and herdr-core's
    # agents then die with the session (it will try to re-enable it).
    linger = true;
  };

  # LocalSend (AirDrop-style file sharing on the local network). The module
  # installs the app (so it is not in systemPackages below) and, with
  # openFirewall (its default, spelled out here), opens port 53317 on TCP and
  # UDP on every interface: UDP multicast for discovery and TCP for the
  # transfer. That covers Wi-Fi/LAN as well as the tailnet. Nothing is
  # listening on that port unless the LocalSend window is open.
  programs.localsend = {
    enable = true;
    openFirewall = true;
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
