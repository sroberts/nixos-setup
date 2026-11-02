# macOS VM Guest Integration Tools & Services for Try NixOS
#
# Provides:
# 1. Out-of-tree kernel module `try-omarchy-battery` (mirrors host battery to BAT0/ADP0)
# 2. Battery bridge service (`mac-battery-bridge.service`)
# 3. Wayland clipboard bridge service (`mac-clipboard-bridge.service`)
# 4. Audio and Timezone bridges (`mac-audio-bridge.service`, `mac-timezone-bridge.service`)
# 5. Camera bridge service (`mac-camera-bridge.service`) with `v4l2loopback`
# 6. Touch ID PAM integration for sudo (`native-authentication-broker` + `mac-touch-id`)
# 7. Guest status reporter service (`mac-guest-status.service`)
# 8. Apple Silicon VirGL Kitty software GL wrapper & Mesa overrides
# 9. Udev rules for virtio-ports and pinch device
# 10. PipeWire quantum configuration for VM guests
# 11. Shared folder (/mnt/mac 9p mount) and root auto-expansion
{
  config,
  lib,
  pkgs,
  ...
}:
let
  tryOmarchyBattery = pkgs.callPackage ../../packages/mac-guest-tools/battery {
    inherit (config.boot.kernelPackages) kernel;
  };

  macGuestTools = pkgs.callPackage ../../packages/mac-guest-tools { };

  kittyWrapped = macGuestTools.kittyWrapped;
in
{
  # ── Filesystems & Partitions ──
  boot.growPartition = true;
  fileSystems."/".autoResize = true;

  fileSystems."/mnt/mac" = {
    device = "mac";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "msize=1048576"
      "cache=readahead"
      "nofail"
      "rw"
    ];
  };

  # ── Kernel Modules ──
  boot.extraModulePackages = [
    tryOmarchyBattery
    config.boot.kernelPackages.v4l2loopback
  ];
  boot.kernelModules = [
    "try-omarchy-battery"
    "v4l2loopback"
  ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=42 card_label="Mac Camera" exclusive_caps=1
  '';

  # ── Udev Rules & Quirks ──
  services.udev.extraRules = ''
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.clipboard", GROUP="users", MODE="0660", TAG+="uaccess"
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.audio", GROUP="audio", MODE="0660", TAG+="uaccess"
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.camera", GROUP="video", MODE="0660", TAG+="uaccess"
    KERNEL=="video42", SUBSYSTEM=="video4linux", GROUP="video", MODE="0660", TAG+="uaccess"
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.battery", MODE="0600"
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.timezone", OWNER="root", GROUP="root", MODE="0600"
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.authentication", OWNER="root", GROUP="root", MODE="0600"
    SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.tryomarchy.guest", MODE="0666"
    ATTRS{name}=="QEMU Virtio Pinch*", ENV{ID_INPUT_TOUCHPAD}="1"
  '';

  environment.etc."libinput/local-overrides.quirks".text = ''
    [Try Omarchy Virtio Pinch Touchpad]
    MatchName=QEMU Virtio Pinch*
    ModelLenovoX1Gen6Touchpad=1
  '';

  # ── PipeWire Quantum Config ──
  services.pipewire.extraConfig.pipewire."90-try-omarchy-quantum" = {
    "context.properties" = {
      "default.clock.quantum" = 4096;
      "default.clock.min-quantum" = 4096;
      "default.clock.max-quantum" = 4096;
    };
    "context.properties.rules" = [
      {
        matches = [ { "cpu.vm.name" = "!null"; } ];
        actions.update-props."default.clock.min-quantum" = 4096;
      }
    ];
  };

  # ── Power & Session Management ──
  # When user selects Shut Down in macOS launcher, QEMU sends power key event
  services.logind.settings.Login.HandlePowerKey = "poweroff";
  # Let macOS host handle low-battery policy without guest forcing shutdown
  services.upower = {
    enable = true;
    allowRiskyCriticalPowerAction = true;
    criticalPowerAction = "Ignore";
  };

  # Disable guest sleep/suspend/hibernate targets
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # ── System Directories ──
  systemd.tmpfiles.rules = [
    "d /var/lib/try-omarchy 0700 root root -"
    "d /run/try-omarchy 0755 root root -"
  ];

  # ── Touch ID for sudo (PAM integration) ──
  security.pam.services.sudo.rules.auth.touchid = {
    order = config.security.pam.services.sudo.rules.auth.unix.order - 10;
    control = "sufficient";
    modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
    args = [
      "quiet"
      "seteuid"
      "stdout"
      "${macGuestTools}/bin/native-authentication-broker"
      "pam"
    ];
  };

  # ── System Services ──

  # 1. Mac Battery Bridge (System Service)
  systemd.services.mac-battery-bridge = {
    description = "Mirror macOS battery into guest";
    unitConfig = {
      ConditionPathExists = [
        "/dev/virtio-ports/dev.tryomarchy.battery"
        "/sys/devices/platform/try-omarchy-battery/state"
      ];
    };
    serviceConfig = {
      ExecStart = "${macGuestTools}/bin/omarchy-native-battery-bridge";
      Restart = "always";
      RestartSec = 1;
    };
    wantedBy = [ "multi-user.target" ];
  };

  # 2. Mac Timezone Bridge (System Service)
  systemd.services.mac-timezone-bridge = {
    description = "Follow macOS host time zone and handle wake events";
    unitConfig = {
      ConditionPathExists = "/dev/virtio-ports/dev.tryomarchy.timezone";
    };
    path = [
      pkgs.systemd
      pkgs.coreutils
    ];
    serviceConfig = {
      ExecStart = "${macGuestTools}/bin/omarchy-native-timezone-bridge";
      Restart = "always";
      RestartSec = 2;
    };
    wantedBy = [ "multi-user.target" ];
  };

  # 3. Mac Guest Status (System Service)
  systemd.services.mac-guest-status = {
    description = "Report Try NixOS guest state to macOS launcher app";
    unitConfig = {
      ConditionPathExists = "/dev/virtio-ports/dev.tryomarchy.guest";
    };
    serviceConfig = {
      ExecStart = "${macGuestTools}/bin/mac-guest-status";
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
    wantedBy = [ "multi-user.target" ];
  };

  # ── User Services ──

  # 4. Wayland Clipboard Bridge (User Service)
  systemd.user.services.mac-clipboard-bridge = {
    description = "Share macOS pasteboard with Wayland clipboard";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig = {
      ConditionPathExists = "/dev/virtio-ports/dev.tryomarchy.clipboard";
    };
    path = [
      pkgs.wl-clipboard
      pkgs.coreutils
    ];
    serviceConfig = {
      ExecStart = "${macGuestTools}/bin/omarchy-native-clipboard-bridge";
      Restart = "on-failure";
      RestartSec = 2;
    };
    wantedBy = [ "graphical-session.target" ];
  };

  # 5. Mac Audio Bridge (User Service)
  systemd.user.services.mac-audio-bridge = {
    description = "Mirror macOS audio devices to PipeWire";
    partOf = [ "graphical-session.target" ];
    after = [
      "graphical-session.target"
      "pipewire.service"
      "pipewire-pulse.service"
      "wireplumber.service"
    ];
    wants = [
      "pipewire.service"
      "pipewire-pulse.service"
      "wireplumber.service"
    ];
    unitConfig = {
      ConditionPathExists = "/dev/virtio-ports/dev.tryomarchy.audio";
    };
    path = [
      pkgs.pulseaudio
      pkgs.coreutils
    ];
    serviceConfig = {
      ExecStart = "${macGuestTools}/bin/omarchy-native-audio-bridge";
      Restart = "on-failure";
      RestartSec = 1;
    };
    wantedBy = [ "graphical-session.target" ];
  };

  # 6. Mac Camera Bridge (User Service)
  systemd.user.services.mac-camera-bridge = {
    description = "Expose macOS camera to guest over virtio";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig = {
      ConditionPathExists = "/dev/virtio-ports/dev.tryomarchy.camera";
    };
    serviceConfig = {
      ExecStart = "${macGuestTools}/bin/omarchy-native-camera-bridge";
      Restart = "always";
      RestartSec = 2;
    };
    wantedBy = [ "graphical-session.target" ];
  };

  # ── Packages & Environment ──
  environment.systemPackages = [
    macGuestTools
  ];

  environment.sessionVariables = {
    MESA_GL_VERSION_OVERRIDE = "3.3";
    MESA_GLSL_VERSION_OVERRIDE = "330";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };

  # Override home-manager's kitty package with wrapped VirGL-safe kitty
  home-manager.users.${config.systemSettings.username} = {
    programs.kitty.package = lib.mkDefault macGuestTools.kittyWrapped;
  };
}
