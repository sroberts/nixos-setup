# niri — input, keybinds, and the config.kdl composition with noctalia.kdl.
# The bind set is identical on every host; only outputs differ (per-host,
# via hosts/<name>/home.nix).
{
  config,
  lib,
  pkgs,
  systemSettings,
  ...
}:
let
  # Умное переключение раскладок. Индексы жёстко связаны с
  # input.keyboard.xkb.layout "us,ru,de" ниже (0/1/2) — меняются вместе.
  # Одиночный Win+Space: тумблер EN<->RU (из DE — в EN); быстрое двойное
  # нажатие (<=400 мс) — немецкий. Текущая раскладка всегда читается живьём
  # из `niri msg`, поэтому рассинхрона состояния нет; state-файл хранит
  # только время последнего нажатия для окна двойного тапа.
  layoutSwitch = pkgs.writeShellScriptBin "layout-switch" ''
    now=$(date +%s%3N)
    state="''${XDG_RUNTIME_DIR:-/tmp}/layout-switch.last"
    prev=$(cat "$state" 2>/dev/null || echo 0)
    cur=$(niri msg -j keyboard-layouts | sed -n 's/.*"current_idx":\([0-9]\+\).*/\1/p')
    if (( now - prev < 400 )); then
      rm -f "$state"
      niri msg action switch-layout 2
    else
      printf '%s' "$now" >"$state"
      case "$cur" in
        0) niri msg action switch-layout 1 ;;
        *) niri msg action switch-layout 0 ;;
      esac
    fi
  '';
in
{
  # niri input — natural scrolling, tap-to-click, disable-while-typing.
  # Schema is validated at build time by niri-flake.
  programs.niri.settings = {
    prefer-no-csd = true;
    cursor = {
      theme = "graphite-dark";
      size = 24;
    };
    input.touchpad = {
      tap = lib.mkDefault true;
      natural-scroll = lib.mkDefault true;
      dwt = lib.mkDefault true;
    };
    input.keyboard.xkb.layout = "us,ru,de";

    workspaces = {
      "01-web".name = "󰖟 Web";
      "02-dev".name = "󰅩 Dev";
      "03-game".name = "󰊴 Game";
    };

    layout = {
      gaps = 6;
    };

    animations = {
      workspace-switch.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 800;
        epsilon = 0.001;
      };
      horizontal-view-movement.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 800;
        epsilon = 0.001;
      };
      window-movement.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 800;
        epsilon = 0.001;
      };
      window-resize.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 800;
        epsilon = 0.001;
      };
      window-open.kind.easing = {
        duration-ms = 180;
        curve = "ease-out-expo";
      };
      window-close.kind.easing = {
        duration-ms = 150;
        curve = "ease-out-quad";
      };
      config-notification-open-close.kind.spring = {
        damping-ratio = 0.65;
        stiffness = 900;
        epsilon = 0.001;
      };
      exit-confirmation-open-close.kind.spring = {
        damping-ratio = 0.6;
        stiffness = 500;
        epsilon = 0.01;
      };
      overview-open-close.kind.spring = {
        damping-ratio = 0.85;
        stiffness = 800;
        epsilon = 0.001;
      };
    };

    window-rules = [
      {
        matches = [
          { app-id = "^firefox$"; }
          { app-id = "^google-chrome$"; }
        ];
        open-on-workspace = "󰖟 Web";
      }
      {
        matches = [
          { app-id = "^kitty$"; }
          { app-id = "^code$"; }
          { app-id = "^obsidian$"; }
        ];
        open-on-workspace = "󰅩 Dev";
      }
      {
        matches = [
          { app-id = "^steam$"; }
        ];
        open-on-workspace = "󰊴 Game";
      }
    ];
    # Monitor layout: outputs are matched by "make model serial" (more
    # stable than connector names — surviving dock swaps / different DP
    # ports). Discover identifier strings with `niri msg outputs`. Layouts
    # and per-output modes/scales are per-host — hosts/<name>/home.nix.

    # niri upstream default keybinds, verbatim, with the terminal binary
    # taken from systemSettings (terminal). The
    # session/media/lock/brightness binds at the bottom of this block were
    # previously owned by DMS's `enableKeybinds`; with Noctalia in charge of
    # the shell UI we wire them directly to the underlying utilities (wpctl,
    # playerctl, brightnessctl, loginctl). Noctalia's own panels are driven
    # over its IPC surface (`noctalia msg <command…>`); Mod+Space toggles the
    # launcher below. Add settings/clipboard/etc. the same way —
    # `noctalia msg --help` lists every command.
    #
    # NOTE: v5 replaced the `noctalia ipc call <target> <fn>` surface with
    # `noctalia msg <command…>`.
    binds = {
      # Help: нативная панель-читшит Noctalia вместо встроенного оверлея
      # niri (то не surface — не стилизуется; см. packages/noctalia-keybind-cheatsheet).
      "Mod+Shift+Slash".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "local/keybind-cheatsheet:cheatsheet"
      ];
      # Quick application launch
      "Mod+Return".action.spawn = "${systemSettings.terminal}";
      "Mod+Shift+Return".action.spawn = [
        "${systemSettings.terminal}"
        "-e"
        "btop"
      ];
      "Mod+T".action.spawn = [ "telegram-desktop" ];
      "Mod+B".action.spawn = [ "google-chrome-stable" ];
      "Mod+E".action.spawn = [ "nemo" ];
      "Mod+Shift+E".action.spawn = [
        "${systemSettings.terminal}"
        "-e"
        "yazi"
      ];

      # Noctalia panels & system overlays
      "Mod+D".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "launcher"
      ];
      "Mod+A".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "control-center"
      ];
      "Mod+Escape".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "session"
      ];
      "Mod+O".action.toggle-overview = [ ];

      # Keyboard layout switcher (Win+Space)
      "Mod+Space".action.spawn = [ (lib.getExe layoutSwitch) ];

      # Window
      "Mod+Q".action.close-window = [ ];

      # Global Spatial Navigation (Arrows)
      # Horizontal ribbon = columns
      "Mod+Left".action.focus-column-left = [ ];
      "Mod+Right".action.focus-column-right = [ ];
      # Vertical stack = workspaces
      "Mod+Up".action.focus-workspace-up = [ ];
      "Mod+Down".action.focus-workspace-down = [ ];
      # Local vertical = windows inside column
      "Mod+Alt+Up".action.focus-window-up = [ ];
      "Mod+Alt+Down".action.focus-window-down = [ ];

      # Moving windows and columns (Shift = Move)
      "Mod+Shift+Left".action.move-column-left = [ ];
      "Mod+Shift+Right".action.move-column-right = [ ];
      "Mod+Shift+Up".action.move-column-to-workspace-up = [ ];
      "Mod+Shift+Down".action.move-column-to-workspace-down = [ ];
      "Mod+Alt+Shift+Up".action.move-window-up = [ ];
      "Mod+Alt+Shift+Down".action.move-window-down = [ ];

      # Workspace reordering
      "Mod+Ctrl+Alt+Up".action.move-workspace-up = [ ];
      "Mod+Ctrl+Alt+Down".action.move-workspace-down = [ ];

      # First / last column
      "Mod+Home".action.focus-column-first = [ ];
      "Mod+End".action.focus-column-last = [ ];
      "Mod+Ctrl+Home".action.move-column-to-first = [ ];
      "Mod+Ctrl+End".action.move-column-to-last = [ ];

      # Multi-monitor control (Ctrl = Monitor)
      "Mod+Ctrl+Left".action.focus-monitor-left = [ ];
      "Mod+Ctrl+Right".action.focus-monitor-right = [ ];
      "Mod+Ctrl+Down".action.focus-monitor-down = [ ];
      "Mod+Ctrl+Up".action.focus-monitor-up = [ ];

      # Move column to monitor (Shift+Ctrl)
      "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [ ];
      "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [ ];
      "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [ ];
      "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [ ];
      # Scroll wheel = workspaces / columns
      "Mod+WheelScrollDown" = {
        cooldown-ms = 150;
        action.focus-workspace-down = [ ];
      };
      "Mod+WheelScrollUp" = {
        cooldown-ms = 150;
        action.focus-workspace-up = [ ];
      };
      "Mod+Ctrl+WheelScrollDown" = {
        cooldown-ms = 150;
        action.move-column-to-workspace-down = [ ];
      };
      "Mod+Ctrl+WheelScrollUp" = {
        cooldown-ms = 150;
        action.move-column-to-workspace-up = [ ];
      };
      "Mod+WheelScrollRight".action.focus-column-right = [ ];
      "Mod+WheelScrollLeft".action.focus-column-left = [ ];
      "Mod+Ctrl+WheelScrollRight".action.move-column-right = [ ];
      "Mod+Ctrl+WheelScrollLeft".action.move-column-left = [ ];
      "Mod+Shift+WheelScrollDown".action.focus-column-right = [ ];
      "Mod+Shift+WheelScrollUp".action.focus-column-left = [ ];
      "Mod+Ctrl+Shift+WheelScrollDown".action.move-column-right = [ ];
      "Mod+Ctrl+Shift+WheelScrollUp".action.move-column-left = [ ];

      # Numeric workspace switch + move
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+6".action.focus-workspace = 6;
      "Mod+7".action.focus-workspace = 7;
      "Mod+8".action.focus-workspace = 8;
      "Mod+9".action.focus-workspace = 9;
      "Mod+Shift+1".action.move-column-to-workspace = 1;
      "Mod+Shift+2".action.move-column-to-workspace = 2;
      "Mod+Shift+3".action.move-column-to-workspace = 3;
      "Mod+Shift+4".action.move-column-to-workspace = 4;
      "Mod+Shift+5".action.move-column-to-workspace = 5;
      "Mod+Shift+6".action.move-column-to-workspace = 6;
      "Mod+Shift+7".action.move-column-to-workspace = 7;
      "Mod+Shift+8".action.move-column-to-workspace = 8;
      "Mod+Shift+9".action.move-column-to-workspace = 9;

      # Previous workspace toggle
      "Mod+Tab".action.focus-workspace-previous = [ ];

      # Consume / expel
      "Mod+BracketLeft".action.consume-or-expel-window-left = [ ];
      "Mod+BracketRight".action.consume-or-expel-window-right = [ ];
      "Mod+Period".action.expel-window-from-column = [ ];

      # Sizing
      "Mod+R".action.switch-preset-column-width = [ ];
      "Mod+Shift+R".action.switch-preset-window-height = [ ];
      "Mod+Ctrl+R".action.reset-window-height = [ ];
      "Mod+F".action.maximize-column = [ ];
      "Mod+Shift+F".action.fullscreen-window = [ ];
      "Mod+Ctrl+F".action.expand-column-to-available-width = [ ];
      "Mod+C".action.center-column = [ ];
      "Mod+Ctrl+C".action.center-visible-columns = [ ];
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+Shift+Minus".action.set-window-height = "-10%";
      "Mod+Shift+Equal".action.set-window-height = "+10%";

      # Floating + tabbed display
      "Mod+V".action.toggle-window-floating = [ ];
      "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = [ ];
      "Mod+W".action.toggle-column-tabbed-display = [ ];

      # Voice dictation toggle & capture correction (noctalia-dictation IPC)
      "Mod+M".action.spawn = [
        "noctalia-dictation"
        "toggle"
      ];
      "Mod+Shift+M".action.spawn = [
        "noctalia-dictation"
        "capture-correction"
      ];
      # Screenshots
      "Mod+Shift+S".action.screenshot = [ ];
      "Print".action.screenshot = [ ];
      "Ctrl+Print".action.screenshot-screen = [ ];
      "Alt+Print".action.screenshot-window = [ ];

      # Session & power
      "Mod+Shift+P".action.power-off-monitors = [ ];
      "Mod+Ctrl+Shift+T".action.toggle-debug-tint = [ ];

      # Lock screen (Noctalia WlSessionLock)
      "Mod+L".action.spawn = [
        "noctalia"
        "msg"
        "session"
        "lock"
      ];

      # Media keys — PipeWire sinks via wpctl, transport via playerctl.
      "XF86AudioRaiseVolume".action.spawn = [
        "wpctl"
        "set-volume"
        "@DEFAULT_AUDIO_SINK@"
        "5%+"
      ];
      "XF86AudioLowerVolume".action.spawn = [
        "wpctl"
        "set-volume"
        "@DEFAULT_AUDIO_SINK@"
        "5%-"
      ];
      "XF86AudioMute".action.spawn = [
        "wpctl"
        "set-mute"
        "@DEFAULT_AUDIO_SINK@"
        "toggle"
      ];
      "XF86AudioMicMute".action.spawn = [
        "wpctl"
        "set-mute"
        "@DEFAULT_AUDIO_SOURCE@"
        "toggle"
      ];
      "XF86AudioPlay".action.spawn = [
        "playerctl"
        "play-pause"
      ];
      "XF86AudioNext".action.spawn = [
        "playerctl"
        "next"
      ];
      "XF86AudioPrev".action.spawn = [
        "playerctl"
        "previous"
      ];

      # Brightness — keyboard top row.
      "XF86MonBrightnessUp".action.spawn = [
        "brightnessctl"
        "s"
        "5%+"
      ];
      "XF86MonBrightnessDown".action.spawn = [
        "brightnessctl"
        "s"
        "5%-"
      ];
    };
  };

  # Extend niri's generated config.kdl with an `include "noctalia.kdl"` line
  # so noctalia's builtin `niri` template's separately-written noctalia.kdl
  # actually applies. programs.niri.config's `default` is not merge-able (any
  # override replaces the settings-derived default entirely), so we compose
  # our own file by reusing programs.niri.finalConfig — the already-rendered
  # string of settings — and appending the include line.
  #
  # `niri validate` (which validated-config-for would run) rejects a config
  # whose included file doesn't exist. That file is written at runtime by
  # noctalia, not at build time, so we bypass validated-config-for and use
  # pkgs.writeText directly — settings themselves are still type-checked at
  # Nix eval time by niri-flake, so the only unchecked thing is our one-line
  # include, which is worth the trade.
  #
  # apply.sh's grep pattern `^[[:space:]]*include([[:space:]].*)?"([^"]*/)?
  # noctalia\.kdl"([[:space:]]|$)` matches the line we inject, so noctalia's
  # apply-time short-circuit fires and it never tries to write into
  # config.kdl (which is still an HM store-path symlink).
  xdg.configFile.niri-config.source = lib.mkForce (
    pkgs.writeText "config.kdl" ''
      ${config.programs.niri.finalConfig}
      include "noctalia.kdl"

      ${builtins.readFile ../../themes/${systemSettings.theme}/niri-effects.kdl}
    ''
  );
}
