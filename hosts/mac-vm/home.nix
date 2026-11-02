# Per-host home overrides for macOS VM guest
{ ... }:
{
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
