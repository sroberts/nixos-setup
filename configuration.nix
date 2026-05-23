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
  nixpkgs.config.allowUnfree = true; # lmstudio, typora, 1password
  system.stateVersion = "26.05";

  ############################################################
  # Boot — systemd-boot now; lanzaboote later (see SECURE BOOT)
  ############################################################
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest; # 6.12+ floor for Ryzen 7040

  ############################################################
  # Disk encryption + hibernation (suspend-to-disk)
  #
  # Layout (created manually at install — see Phase 1 of the plan):
  #   nvme0n1p1  ESP (unencrypted, FAT32)
  #   nvme0n1p2  LUKS2 container -> LVM vg "vg"
  #                vg/swap  92 GiB   (encrypted swap, holds hibernation image)
  #                vg/root  rest     (encrypted root, ext4)
  #
  # The LUKS unlock entry + filesystems + swapDevices are auto-written into
  # hardware-configuration.nix by `nixos-generate-config`. We only declare the
  # resume target here, using the STABLE LVM path so it's machine-independent.
  ############################################################
  boot.resumeDevice = "/dev/vg/swap";

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
  # Networking, Bluetooth, fingerprint
  ############################################################
  networking.hostName = "framework13";
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.fprintd.enable = true; # Goodix reader

  ############################################################
  # niri + DankMaterialShell greeter
  ############################################################
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
    polkitPolicyOwners = [ "scott" ];
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
    acceleration = "rocm"; # Radeon 780M iGPU; switch to "cpu" if rocm crashes
  };

  ############################################################
  # User
  ############################################################
  users.users.scott = {
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
    noto-fonts-emoji
  ];
}
