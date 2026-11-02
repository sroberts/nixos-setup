# Per-host module for dev (Gnome Boxes / QEMU on x86_64).
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    ../common.nix
    ../../modules/disko/btrfs-uefi.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  networking.hostName = "dev";
  nixpkgs.hostPlatform = "x86_64-linux";

  # Disko device override for QEMU virtio disk
  disko.devices.disk.main.device = "/dev/vda";

  # Hardware kernel modules for QEMU VM
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];

  # Ensure Mesa exposes OpenGL 3.3 in the virgl VM (the virtual GPU reports
  # a lower core profile than niri/Quickshell request).
  environment.sessionVariables = {
    MESA_GL_VERSION_OVERRIDE = "3.3";
    MESA_GLSL_VERSION_OVERRIDE = "330";
  };

  # Gnome Boxes / QEMU guest integrations (clipboard sharing, dynamic resolution, time sync)
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  # Passwordless sudo for dev VM to allow seamless automated rebuilds
  security.sudo.wheelNeedsPassword = false;

  # Install Limine to standard removable UEFI path so VM always boots without NVRAM state
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.limine.efiInstallAsRemovable = true;

  # Compressed RAM swap (25% total RAM)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  # Disable nested hypervisor inside guest VM
  my.virtualization.enable = false;

  # Enable OpenSSH daemon for SSH access from host
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.gosha20777.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHz1i0hWB0f6oP3+EkA0EodjJrp5R3P9F8rC5sivM1py gosha20777@pc"
  ];

  # Per-host home overrides
  home-manager.users.${config.systemSettings.username}.imports = [ ./home.nix ];
}
