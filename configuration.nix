# System-level configuration for the Framework 13 AMD.
# User-level packages and dotfiles live in home.nix.
#
# NOTE: when enabling Secure Boot (see the SECURE BOOT block below), add `lib`
# to the function arguments: { config, pkgs, lib, inputs, ... }
{ config, pkgs, inputs, ... }:

{
  ############################################################
  # Nix / nixpkgs
  ############################################################
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Default download buffer is 1 MiB, which fills constantly on big builds
  # (first install, niri/dms/claude-code together). 256 MiB silences the
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
  fileSystems."/boot".options = [ "fmask=0077" "dmask=0077" ];

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

  # Optional: let the lid / power key hibernate instead of sleep.
  # services.logind.lidSwitch = "hibernate";

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
  networking.hostName = "sjr-fw13";
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # Goodix fingerprint reader. fprintd runs the daemon; the PAM hooks
  # below let it stand in for a password. Enroll once with `fprintd-enroll`
  # before the integrations are useful.
  services.fprintd.enable = true;
  security.pam.services = {
    sudo.fprintAuth = true;        # sudo prompt
    login.fprintAuth = true;       # TTY login
    su.fprintAuth = true;          # su to another user
    polkit-1.fprintAuth = true;    # GUI privilege prompts (e.g. password change)
    greetd.fprintAuth = true;      # tuigreet at the login screen
    # Noctalia's lock screen runs its own PAM context; we don't add fprintAuth
    # there. Wayland lock-screen PAM stacks tend to omit the `unix-early`
    # password reader that login/greetd have, so layering pam_fprintd on top
    # breaks the password fallback (fprintd blocks the conversation while the
    # user is typing). Lock-screen fingerprint, if wanted, should be wired
    # through Noctalia's own settings, not this PAM map.
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
    (inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable).overrideAttrs (old: {
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
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
    };
  };

  # niri-flake's polkit user service is left at its default (enabled).
  # DMS used to provide its own polkit agent, so we disabled the niri one
  # to avoid double-registration; Noctalia does not provide a polkit
  # agent, so we want niri's back.

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
  # 1Password (GUI + CLI + browser integration)
  ############################################################
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "sroberts" ];
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
  };

  ############################################################
  # User
  ############################################################
  users.users.sroberts = {
    isNormalUser = true;
    description = "Scott";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "docker" "video" "input" ];
  };

  ############################################################
  # System-wide GUI applications
  ############################################################
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
