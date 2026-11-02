# Live installer ISO — boots into the full shared desktop and runs the
# Python installer. NOT a target machine: this module lives outside hosts/
# (nixosConfigurations.live-*, built by mkLive in flake.nix) so that
# host auto-discovery only ever offers target machines.
#
# Hardware support is inherited from the installation-cd-minimal profile
# (scan/detected + not-detected: all kernel drivers, NetworkManager);
# graphics come from Mesa in the shared closure (Intel/AMD iGPU — the
# NVIDIA dGPU is host-specific and is fetched at install time instead).
{
  config,
  pkgs,
  lib,
  repoRoot, # flake root path (specialArgs from mkLive)
  ...
}:
let
  kittyWrapped = (pkgs.callPackage ../packages/mac-guest-tools { }).kittyWrapped;
in
{
  imports = [
    # Live desktop = the shared system + home module trees, exactly like a
    # real host — this IS the final OS experience.
    ../../hosts/common.nix
  ];

  networking.hostName = "live";
  # Passwordless sudo for the live user: the TUI installer mutates disks and
  # runs nixos-install, so it must run as root — the launcher elevates via
  # `sudo -n`. Live-ISO-only: target hosts never import this module.
  security.sudo.wheelNeedsPassword = false;
  # Fix font rendering in Live ISO: installation-cd-minimal sets mkOverride 500 false,
  # which disables fontconfig entirely. Force it on so JetBrainsMono Nerd Font resolves.
  fonts.fontconfig.enable = lib.mkForce true;

  # Disable sops in live session (no Age key present on boot). This allows Home Manager
  # activation to complete cleanly without aborting, ensuring wallpapers and starship seed.
  systemSettings.sops.enable = false;
  # Silence upstream nixpkgs warning from installation-cd-minimal profile:
  # NixOS 26.11 recommends setting boot.zfs.forceImportRoot explicitly.
  boot.zfs.forceImportRoot = false;
  boot.loader.limine.enable = lib.mkForce false;

  # Disable virtualization stack in live installer ISO
  my.virtualization.enable = false;

  # VirtIO kernel modules for seamless VM display and device support (x86_64 and aarch64)
  boot.initrd.availableKernelModules = [
    "virtio_gpu"
    "virtio_pci"
    "virtio_blk"
    "virtio_input"
    "virtio_net"
    "virtio_console"
  ];
  # Trackpad recognition for QEMU pinch device
  services.udev.extraRules = ''
    ATTRS{name}=="QEMU Virtio Pinch*", ENV{ID_INPUT_TOUCHPAD}="1"
    SUBSYSTEM=="block", KERNEL=="vd[a-z]", ATTR{ro}=="0", ENV{ID_MODEL}=="", ENV{ID_MODEL}="QEMU_VirtIO_Disk", ENV{ID_MODEL_ENC}="QEMU\x20VirtIO\x20Disk"
  '';

  # Home Manager live tweaks: auto-start installer, set scale, and fish hint
  home-manager.users.${config.systemSettings.username} = {
    programs.kitty.package = lib.mkDefault kittyWrapped;

    programs.niri.settings = {
      outputs."eDP-1".scale = 1.25;
      outputs."Virtual-1".scale = 1.25;
    };
    # Launch the TUI installer in --execute mode only AFTER graphical-session.target
    # and noctalia.service are active (preventing early startup race with Noctalia's
    # kitty theme generation).
    systemd.user.services.nixos-installer-autostart = {
      Unit = {
        Description = "Auto-start NixOS Everforest Live Installer in Kitty";
        After = [
          "graphical-session.target"
          "noctalia.service"
        ];
        Wants = [ "noctalia.service" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 1";
        ExecStart = "${kittyWrapped}/bin/kitty --title \"NixOS Everforest Installer\" -e /run/current-system/sw/bin/nixos-installer --execute";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    programs.fish.interactiveShellInit = ''
      set -g fish_greeting "🌲 NixOS Everforest Live — для запуска установщика выполните: nixos-installer --execute"
    '';
  };

  # Passwordless live user for desktop autologin (installation-device style)
  users.users.${config.systemSettings.username}.initialHashedPassword = "";

  # Autologin straight into niri (no greeter prompt in live mode)
  services.greetd.settings.initial_session = {
    command = "niri-session";
    user = config.systemSettings.username;
  };

  # Ensure Home Manager activation completes before greetd starts the session,
  # preventing races where niri/Noctalia launch before themes, icons, and wallpapers exist.
  systemd.services.greetd = {
    after = [
      "home-manager-${config.systemSettings.username}.service"
      "systemd-user-sessions.service"
      "network.target"
    ];
    wants = [ "home-manager-${config.systemSettings.username}.service" ];
  };
  environment.systemPackages =
    let
      installerPython = pkgs.python3.withPackages (ps: [ ps.rich ]);
    in
    with pkgs;
    [
      disko
      git
      age
      sops
      installerPython

      # TUI installer launcher — runs the baked flake repo's installer app
      (writeShellScriptBin "nixos-installer" ''
        for arg in "$@"; do
          if [ "$arg" = "--dry-run" ]; then
            exec sudo -n ${installerPython}/bin/python3 /etc/iso/repo/installer/main.py --repo /etc/iso/repo
          fi
        done
        exec sudo -n ${installerPython}/bin/python3 /etc/iso/repo/installer/main.py --repo /etc/iso/repo --execute "$@"
      '')
    ];

  # Bake the flake repository (including installer/) into the ISO
  environment.etc."iso/repo".source = repoRoot;

  # zstd instead of the default xz: much faster ISO builds, slightly larger image
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
}
