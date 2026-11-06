# Per-host home overrides for macOS VM guest
{
  config,
  lib,
  pkgs,
  ...
}:
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

  # GPU-accelerated kitty. The macOS host runs a patched virglrenderer
  # (virgl-core-instance-id + virgl-shader-failure-skip-draws), so kitty renders
  # on virgl and the llvmpipe wrapper from mac-guest-tools.nix is no longer
  # needed. Keep background_opacity below 1.0 (kitty.nix sets 0.92): it forces
  # kitty's layers path, whose blit shader does the linear→sRGB encode in
  # software. vrend does not forward the guest's glEnable(GL_FRAMEBUFFER_SRGB)
  # (it derives sRGB from the surface format, and the Wayland window surface is
  # B8G8R8A8_UNORM), so the direct path — used when opacity is 1.0, or when no
  # image/cursor-trail/progress-bar forces layers — writes linear values and the
  # window goes dark.
  programs.kitty.package = pkgs.kitty;

  programs.niri.settings = {
    # Pin the virtual display to 16:10 MacBook resolution on 15.3" panel (199.3 PPI).
    # Scale 2.10 gives ~15.6' - 17.5' x-height (4.7x - 5.3x MAR at 40-45 cm),
    # matching ThinkPad 15.6" 1080p @ 1.40 feel and making UI ~6% larger.
    outputs."Virtual-1" = {
      mode = {
        width = 2560;
        height = 1656;
      };
      scale = 2.10;
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

  # Split Noctalia bar around the MacBook display notch:
  # Keep center empty so widgets are not obscured by the physical notch.
  programs.noctalia.settings.bar.default = {
    start = lib.mkForce [
      "launcher"
      "workspaces"
      "cpu_temp"
      "ram_usage"
      "net_speed"
      "cat"
      "audio_visualizer"
    ];
    center = lib.mkForce [ ];
    end = lib.mkForce [
      "clock"
      "caffeine"
      "weather"
      "dictation"
      "tray"
      "keyboard_layout"
      "network"
      "battery"
      "control-center"
    ];
  };
}
