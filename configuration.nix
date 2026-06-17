# System-level configuration for the Framework 13 AMD.
# User-level packages and dotfiles live in home.nix.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

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
  nixpkgs.config.allowUnfree = true; # lmstudio, typora, 1password
  system.stateVersion = "26.05";

  ############################################################
  # Boot — systemd-boot now; lanzaboote later (see SECURE BOOT)
  ############################################################
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest; # 6.12+ floor for Ryzen 7040

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

  # Idle escalation timing (Noctalia in home.nix triggers the actions):
  # lock @ 5 min, then `systemctl suspend-then-hibernate` @ 15 min. That
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
    greetd.fprintAuth = true; # tuigreet at the login screen
    # Noctalia's lock screen auto-detects PAM service: it falls through to
    # /etc/pam.d/login (LockContext.qml:22), so login.fprintAuth above is
    # what lights up the lock screen's fingerprint path. The "competing
    # readers" problem this would otherwise cause (pam_fprintd vs Noctalia's
    # text input) is avoided by Noctalia's `allowPasswordWithFprintd=true`
    # setting, asserted by home.activation.noctaliaConfigSeed.
  };

  # pam_fprintd's default `timeout=30` returns PAM_AUTH_ERR after 30s of no
  # touch, at which point Noctalia's lock screen sees PAM completed and drops
  # the fingerprint affordance from its UI — there's no re-arm hook. (The only
  # re-arm path Noctalia has is the keypress one driven by
  # `allowPasswordWithFprintd`, which is for switching to the password input,
  # not for restarting fingerprint listening.) `timeout=-1` per man pam_fprintd
  # disables the deadline entirely, so Verify stays open until either a finger
  # matches or Noctalia cancels PAM itself (which it does on keypress / Enter).
  # max-tries=-1 removes the analogous cap on wrong-touch retries; default 3
  # would otherwise put a hard cap of 3 bad reads.
  #
  # Scoped to `login` only: that's the PAM service Noctalia uses. sudo / su /
  # polkit dialogs keep the 30s default — short authentication prompts are
  # supposed to time out.
  security.pam.services.login.rules.auth.fprintd.args = [
    "timeout=-1"
    "max-tries=-1"
  ];

  # Goodix MOC fingerprint sensor (USB 27c6:609c) — keep USB runtime-PM off.
  # The kernel default is `power/control=auto` with a 2s autosuspend delay, so
  # the sensor goes to `runtime_status=suspended` ~2s after the last touch.
  # On this Goodix MOC variant the USB resume path is unreliable: a touch on
  # a suspended sensor is dropped silently, the lock screen falls back to
  # password, and from the user's perspective "fingerprint works for a few
  # minutes then dies." Pinning `power/control=on` keeps the device awake; the
  # idle power cost is sub-milliwatt and never showed up on the laptop's
  # battery telemetry. Match is by VID+PID so the rule is a no-op on hosts
  # without this exact reader (i.e. it can live in shared config).
  #
  # `add|change` (not just `add`) so the activation script below can re-fire
  # the rule on already-attached devices via `udevadm trigger --action=change`.
  # Without that, nixos-rebuild reloads the ruleset but never applies the new
  # power setting to the running sensor — which is exactly what bit us first.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="27c6", ATTR{idProduct}=="609c", ATTR{power/control}="on"
  '';

  # Force the rule onto the already-attached Goodix device on every rebuild.
  # `services.udev.extraRules` writes the rule and nixos-rebuild reloads the
  # ruleset, but neither re-runs the rule against existing devices — so a
  # fresh `power/control=on` setting would otherwise wait for the next
  # unplug/replug (i.e. a reboot) to actually land on the sensor.
  system.activationScripts.goodixFingerprintPM = {
    text = ''
      ${pkgs.systemd}/bin/udevadm trigger --action=change \
        --attr-match=idVendor=27c6 --attr-match=idProduct=609c 2>/dev/null || true
    '';
    deps = [ ];
  };

  # Bounce fprintd on every resume. When the lid closes, swayidle's
  # before-sleep raises Noctalia's lock screen, pam_fprintd starts a
  # long-lived Verify call, and fprintd grabs a handle to the Goodix sensor.
  # Userspace freezes mid-Verify; on wake the USB tree re-enumerates and
  # fprintd's old sensor handle is dead. The wedged Verify never returns, so
  # pam_fprintd's max-tries=-1 retry loop never gets a chance to fire — the
  # lock screen comes back password-only.
  #
  # Restarting fprintd here kills the dead Verify, fprintd comes back up
  # clean and re-claims the freshly enumerated sensor, and pam_fprintd's
  # next retry hits a working daemon. powerManagement.resumeCommands is
  # NixOS's wrapper around the systemd-sleep post-resume hook directory.
  powerManagement.resumeCommands = ''
    ${pkgs.systemd}/bin/systemctl restart fprintd.service || true
  '';

  # Keep fprintd hot. Upstream packages it as a dbus-activated service with a
  # 30s idle-exit, so the unit is `inactive (dead)` most of the time. When the
  # lock screen calls pam.start() under Noctalia's autoStartAuth=true, pam_fprintd
  # has to wake fprintd via dbus *and* claim the sensor before Noctalia decides
  # whether to render the "touch finger or type password" UI or fall back to
  # password-only. That activation latency is the second half of the Goodix
  # problem (the udev rule above handles USB autosuspend; this handles the
  # daemon side). wantedBy starts fprintd at boot; Restart=always brings it back
  # within RestartSec of the idle-exit, so it's effectively continuously running.
  systemd.services.fprintd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = 1;
    };
  };

  ############################################################
  # niri + greetd (tuigreet) login
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
  programs.niri.package =
    (inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable).overrideAttrs
      (old: {
        doCheck = false;
      });

  # tuigreet on tty1, launching niri (which auto-spawns Noctalia via
  # spawn-at-startup in home.nix). `--remember` keeps the last username
  # pre-filled; `--time` shows a clock. The session command is the same
  # one DankInstaller-style configs use to start niri.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
    };
  };

  # Polkit auth agent: defer to Noctalia's `polkit-agent` plugin (seeded in
  # home.nix as part of plugins.json) rather than niri-flake's bundled
  # polkit-kde-agent service. Two agents would race on the
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
  # NIXOS_OZONE_WL=1 is the nixpkgs convention for opting Electron /
  # Chromium-based apps into native Wayland (Ozone) instead of XWayland.
  # Without it, apps like Discord and Obsidian render at the panel's
  # native pixel density and ignore the compositor's per-output scale —
  # on the Framework 13's 2880×1920 panel that means UI a third of the
  # size of the rest of the desktop. The discord/obsidian/1password
  # wrappers in nixpkgs check this var and pass the appropriate
  # `--ozone-platform=wayland` flags only when it's set.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.systemPackages = with pkgs; [
    _1password-gui
    chromium
    discord
    localsend
    obsidian
    lmstudio
    rpi-imager
    slack
    signal-desktop
    typora
    zed-editor
    zoom-us

    git
    curl
    wget
    unzip
    cryptsetup # handy for inspecting/managing the LUKS volume post-install
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
