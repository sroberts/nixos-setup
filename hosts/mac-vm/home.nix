# Per-host home overrides for macOS VM guest
{ config, ... }:
{
  # Machine-specific SSH key from secrets/mac-vm.yaml
  sops.secrets."id_ed25519" = {
    sopsFile = ../../secrets/mac-vm.yaml;
    path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    mode = "0600";
  };

  # Public key matching id_ed25519
  home.file.".ssh/id_ed25519.pub".text =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAYQavuQjYZQAxRspxYRObVbvZNY8+vX145cN+O3tFGd gosha20777@Georgys-Air\n";

  programs.niri.settings = {
    # Pin the virtual display to standard Retina 16:10 MacBook resolution with 1.6 scale
    outputs."Virtual-1" = {
      mode = {
        width = 2560;
        height = 1600;
      };
      scale = 1.6;
    };

    # QEMU Virtio Pinch Touchpad delivers reconstructed macOS gesture contacts
    # with host scroll direction already applied; keep tap, dwt, and guest
    # scroll inversion disabled to avoid double-reversed scroll and false taps.
    input.touchpad = {
      tap = false;
      dwt = false;
      natural-scroll = false;
    };
  };
}
