# Role: macOS VM guest integration with Try Omarchy launcher
# Hardware: Apple Silicon QEMU VirtIO guest (aarch64-linux, UEFI)
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    ../common.nix
    ../../modules/disko/btrfs-uefi.nix
    ../../modules/nixos/roles/mac-guest-tools.nix
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  networking.hostName = "mac-vm";
  nixpkgs.hostPlatform = "aarch64-linux";

  # Disko target virtio block device
  disko.devices.disk.main.device = "/dev/vda";

  # Install Limine to standard removable UEFI path (\EFI\BOOT\BOOTAA64.EFI)
  # so fresh/ephemeral/cloned efi-vars.fd in try-omarchy always boots without NVRAM state
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.limine.efiInstallAsRemovable = true;

  # Compressed RAM swap (25% total RAM)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  # Hardware kernel modules for QEMU VirtIO ARM64 guest
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_gpu"
    "virtio_balloon"
    "virtio_input"
    "virtio_net"
    "virtio_console"
    "9p"
    "9pnet_virtio"
  ];

  # Graphics & Display via VirGL / Mesa
  services.xserver.videoDrivers = [ "modesetting" ];
  hardware.graphics.enable = true;

  # Disable nested hypervisor and gaming stack inside guest VM
  my.virtualization.enable = false;
  my.apps.steam.enable = false;

  # Per-host home overrides
  home-manager.users.${config.systemSettings.username}.imports = [ ./home.nix ];
}
