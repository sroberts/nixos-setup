{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../common.nix
    ./disko.nix
    ../../modules/nixos/roles/workstation.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel
  ];

  networking.hostName = "lab";
  nixpkgs.hostPlatform = "x86_64-linux";

  # ── CPU, Sensors & Hardware (Intel Core i9-12900K + Gigabyte Z790) ──
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [
    "coretemp"
    "gigabyte_wmi"
  ];

  # Enable transparent QEMU user emulation for building ARM64 (aarch64-linux) targets
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  environment.systemPackages = with pkgs; [
    lm_sensors
    nvtopPackages.full
  ];

  # ── Graphics: NVIDIA GeForce RTX 4090 (Ada Lovelace) + Intel UHD 770 ──
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    # Stationary workstation running 24/7 calculations — no sleep / power off
    powerManagement.enable = false;
    # Ada Lovelace RTX 4090 is officially supported by the open kernel modules
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  # ── Greeter Display Configuration ──
  # Pin login screen to primary (right) monitor at calculated 1.60 scale
  services.displayManager.noctalia-greeter.settings.output = {
    name = "DP-2";
    scale = 1.6;
  };

  # ── Swap & Storage ──
  # Compressed RAM swap (25% total RAM ≈ 8 GB virtual swap)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  # Phase 1: Mount existing ext4 HDD-1 with _BACKUP in read-only mode for safe migration
  fileSystems."/mnt/backup-source" = {
    device = "/dev/disk/by-id/ata-ST8000DM004-2U9188_ZR14R708";
    fsType = "ext4";
    options = [
      "ro"
      "nofail"
      "noatime"
    ];
  };

  # ── Remote Access (OpenSSH + Tailscale) ──
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.${config.systemSettings.username}.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDZcLJfiJMqmAPjaS3klqZ3bfKyHZV2hkDuFkFOyZvHzXu6ya79LrIHG3e33HB5ZrCqkWUbETNTZz3q3SNm41pnQjBYaDtM4ldPgs9Mckk0N6TVoS+E/aHLGLaWmn9Mg6ehJZL47nMs5kecUp1HRWerRoEq2FOebGcmhSsDvbznMeFLsnoa2ZEbx1C7ka3PMcIFoC6iuw0tnC6ZDwKJ6mrlhxJ11MCIw8YiQAi423p4rVnlaHSbpyvEPSq3LtB6LWwX/Q4fGMQHNPujMOWc73xBSd0ZPTNm+upROnMgDi7F+f6CoseBi/ztEnbsAGwDcxY+0nZnKknDJuQ2ayUmlq+eiyQbiFs5ycyZe0u0CfzMZQD5Kjyj8wsPqQMKOgkM2TcG5dUDOqhMnnhh8xVRpHDYcbW3qLzFLBWh4CLzFiELYtjVkVydsHZCIRwMjDnossUhbjNcVGsX8d7ceGY7qdlTe4SL+aRLtXc2Lm06ox2553BouUNda9pZ+2x6twM48Gk= gosha20777@thinkpad"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCzlNXrgy/YYzu3x0bpJB6MljpVYAPgBKERPcs3CWiou8vMrsKHmObJLHJbejpQ+CdF0oEBZo4e0Zv+0KnHgKTYB5aikV2+6jd+CEZglURh96rNJhR/ygpZTixcYE5MkbdXmpZZ0EFAph3KJfXDUfJvGD1Vu8wndxuuNg2oor5W+9hCsU3nq8/p7rpLM7z1xjbeol573rCXZ7bnbgEmjN6wRQ3uxzYxmgHYE7UHG3EwsxqCAC8mz6GQaOv+tZOB2PUvoartd4d9RKzGY9VeP3c1Jl1bijnwfXcgQC8wA0F9YdlX12VvQArIJa72p8hP24rS7PxTG3jqzTzQShtSyJKE3ScZnDO60RiXTlWEDWvTAerxR98I5Jsae66r4m38xG79RHFiIh1T9acoP0Ih8HgeY/IeSZ6MH2O52n+lHYasO2jsD7jC+iUquh3TEEKi9xNDfhWToAuyFQJsshJ7In2i1tmqjO/lwhUsNzh9x+0z1zpVVeGA0RMXA6qHKdXNC2U= gosha20777@ThinkPad"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAYQavuQjYZQAxRspxYRObVbvZNY8+vX145cN+O3tFGd gosha20777@Georgys-Air"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHz1i0hWB0f6oP3+EkA0EodjJrp5R3P9F8rC5sivM1py gosha20777@pc"
  ];

  # ── Services ──
  my.services.ollama.enable = true;

  # ── Backups & SOPS ──
  my.services.restic.enable = true;
  sops.age.keyFile = "/home/${config.systemSettings.username}/.config/sops/age/keys.txt";
  sops.secrets."restic/password".sopsFile = ../../secrets/lab.yaml;

  home-manager.users.${config.systemSettings.username}.imports = [ ./home.nix ];
}
