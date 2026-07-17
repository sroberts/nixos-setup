# User-level configuration: packages, shell, dotfiles, Noctalia.
{
  inputs,
  pkgs,
  config,
  ...
}:

let
  # JFryy/qq — jq-like CLI with interchangeable format transcodings. Not in
  # nixpkgs; packaged inline so it survives reinstalls instead of needing a
  # post-boot `go install`.
  qq = pkgs.buildGoModule rec {
    pname = "qq";
    version = "0.3.4";
    src = pkgs.fetchFromGitHub {
      owner = "JFryy";
      repo = "qq";
      rev = "v${version}";
      hash = "sha256-GLZKDKJEtZIsOMj9V7q2Po7DDelhl1tg1DOyihOw2bk=";
    };
    vendorHash = "sha256-x4tEGE/ewE4SjUm9m+NTbKZVLNJsvbNg03Wdw7s4qhI=";
  };

  # basecamp/fizzy-cli — packaged from the prebuilt linux-amd64 release
  # binary because `go install` can't reach v3.x.x for this repo: their
  # go.mod still declares `module github.com/basecamp/fizzy-cli` with no
  # `/v3` suffix, and Go's semantic import versioning won't resolve v2+
  # tags without the major-version path. So `@latest` falls back to a
  # pseudo-version of master, which fizzy itself flags as out-of-date.
  # autoPatchelfHook fixes the ELF interpreter path; stdenv.cc.cc.lib
  # covers libstdc++/libgcc_s that the cgo binary links against.
  fizzy-cli = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "fizzy-cli";
    version = "3.0.3";
    src = pkgs.fetchurl {
      url = "https://github.com/basecamp/fizzy-cli/releases/download/v${version}/fizzy-linux-amd64";
      hash = "sha256-r1vNVFkRaRkxo81nhpE0X8MiHsiE2M7px0ZMxfKPgVQ=";
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    installPhase = ''
      install -Dm755 $src $out/bin/fizzy
    '';
    meta = {
      description = "Fizzy CLI and Agent Skills";
      homepage = "https://github.com/basecamp/fizzy-cli";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  home.username = "sroberts";
  home.homeDirectory = "/home/sroberts";
  home.stateVersion = "26.05";

  ############################################################
  # Noctalia shell
  ############################################################
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia = {
    enable = true;
    # Run Noctalia as a systemd user unit (PartOf/WantedBy=wayland.systemd.target,
    # Restart=on-failure) instead of letting the compositor spawn it. Two reasons:
    #   1. `nixos-rebuild switch` doesn't kill the running noctalia; without
    #      systemd owning the process, activation leaves the old store-path bar
    #      alive and next startup adds a second one (dup bars — see PR #51).
    #   2. In v5, `noctalia msg …` transparently spawns a full bar when it
    #      can't reach a server (a client/server version mismatch during a
    #      partial rebuild used to give us a stray extra bar). systemd ensures
    #      the running server always matches the current generation.
    # The module wires X-Restart-Triggers to the config.toml source path, so a
    # settings change alone triggers a clean unit restart — no manual bounce.
    systemd.enable = true;

    # Declarative base config → ~/.config/noctalia/config.toml (v5's TOML
    # format; the module runs `noctalia config validate` at build time).
    #
    # v5 splits config into two files and this is why we can own config.toml
    # declaratively where v4 forced a home.activation seed: config.toml is the
    # read-only BASE the shell never writes, and every runtime change from the
    # settings UI (including the chosen wallpaper, which drives the Material You
    # palette) is written to a SEPARATE ~/.config/noctalia/settings.toml
    # overrides file that Noctalia merges on top. So a store-path symlink here
    # can't clobber the user's live tweaks — they live in settings.toml, which
    # home-manager doesn't touch.
    settings = {
      # Weather + where-am-I. v5 moved the unit under [weather]; [location]
      # geocodes `address`.
      location.address = "Greenville, SC";
      weather = {
        enabled = true;
        unit = "fahrenheit";
      };

      # Theme derives from the wallpaper (Material You), same as v4's matugen
      # behavior — this is what feeds the gtk3/gtk4 templates below and, in
      # turn, our @import'd gtk.css and the zellij/typora palettes.
      theme = {
        mode = "dark";
        source = "wallpaper";
        # Force a grayscale Material You palette regardless of the wallpaper's
        # hues. This decouples the derived palette from the image: any wallpaper
        # now yields a neutral scheme, keeping the GTK/Material You side aligned
        # with the hardcoded `noctalia-mono` terminal themes (zellij/nvim/
        # starship/bat) below. Valid schemes: m3-tonal-spot | m3-content |
        # m3-fruit-salad | m3-rainbow | m3-monochrome | vibrant | faithful |
        # dysfunctional | muted (only applies while source = "wallpaper").
        wallpaper_scheme = "m3-monochrome";
        # v5 replaces v4's single `gtk` template with two builtin templates
        # writing ~/.config/gtk-{3,4}.0/noctalia.css (the paths our managed
        # gtk.css @imports). Opt into them explicitly. Discover ids with
        # `noctalia theme --list-templates` (builtin) or api.noctalia.dev
        # /templates (community).
        templates = {
          enable_builtin_templates = true;
          builtin_ids = [
            "gtk3"
            "gtk4"
            # NOTE: each of these writes a `noctalia` theme file AND appends an
            # include/palette line to the app's MAIN config.
            #   btop     — plain/writable config, applies cleanly.
            #   ghostty  — migrated: `theme = noctalia` set declaratively above
            #              so apply.sh no-ops on the config; only the theme file
            #              is written. (issue #62)
            #   starship — migrated: config seeded writable so apply.sh can
            #              inject the palette (see programs.starship + the
            #              starshipConfigSeed activation). (issue #62)
            # NOTE: `niri` is deliberately NOT enabled here. Its apply.sh appends
            # an `include` line to config.kdl, which home-manager owns as a
            # read-only store symlink — the append fails and the generated
            # noctalia.kdl is left unreferenced (dead config). Re-add it once
            # #62 gives us a writable-include path for niri.
            "btop"
            "ghostty"
            "starship"
          ];
          # Community templates are fetched from api.noctalia.dev/templates at
          # runtime and cached under ~/.cache/noctalia (a network fetch, not a
          # Nix-pinned input — offline first-boot won't have them until the
          # shell can reach the API).
          enable_community_templates = true;
          community_ids = [
            "neovim"
            "obsidian"
            "zed"
            "fuzzel"
            "discord"
            "steam"
          ];
        };
      };

      wallpaper = {
        enabled = true;
        directory = "~/Pictures/Wallpapers";
        # Initial wallpaper on a fresh $HOME (the asset copied in by
        # home.activation.defaultWallpaper). Once the user picks another in
        # the UI, that choice lands in settings.toml and wins.
        default.path = "~/Pictures/Wallpapers/default-wallpaper.jpg";
      };

      # v5 folds the polkit agent into native config; this replaces v4's
      # plugins.json `polkit-agent`. niri-flake's polkit-kde-agent stays
      # force-disabled in configuration.nix so the two don't race.
      shell.polkit_agent = true;

      # Idle escalation, native to Noctalia's idle manager. Named behaviors
      # under [idle.behavior.*]: a 5-min lock, then suspend-then-hibernate at
      # 15 min. `noctalia:session lock` is the internal action; the bare
      # systemctl command is run as a user command. See services.swayidle
      # below for the one job (lock-on-lid-close) this can't cover.
      idle.behavior = {
        lock = {
          timeout = 300;
          command = "noctalia:session lock";
          enabled = true;
        };
        hibernate = {
          timeout = 900;
          command = "systemctl suspend-then-hibernate";
          enabled = true;
        };
      };
    };
  };

  # niri input — natural scrolling, tap-to-click, disable-while-typing.
  # Schema is validated at build time by niri-flake.
  programs.niri.settings = {
    input.touchpad = {
      tap = true;
      natural-scroll = true;
      dwt = true;
    };
    # Monitor layout. Outputs are matched by "make model serial" (more
    # stable than connector names — surviving dock swaps / different DP
    # ports). The Dell sits at the origin; the laptop panel is placed to
    # its right at x=2560 (Dell's logical width at scale 1) and bottom-
    # aligned at y=480 (Dell 1440 − laptop 960) so crossing the boundary
    # matches the physical arrangement — laptop on the desk, Dell rising
    # above it. Discover identifier strings with `niri msg outputs`.
    outputs = {
      "Dell Inc. DELL P3221D C57ZQ83".position = {
        x = 0;
        y = 0;
      };
      "BOE NE135A1M-NY1 Unknown".position = {
        x = 2560;
        y = 480;
      };
    };
    # Noctalia now runs as a systemd user unit tied to wayland.systemd.target
    # (see programs.noctalia.systemd.enable above), not a compositor spawn.
    # NOTE: v5 replaced the `noctalia ipc call <target> <fn>` surface with
    # `noctalia msg <command…>`. Discover commands with `noctalia msg --help`.
    # niri upstream default keybinds, verbatim, with the terminal binary
    # swapped from alacritty to ghostty. The session/media/lock/brightness
    # binds at the bottom of this block were previously owned by DMS's
    # `enableKeybinds`; with Noctalia in charge of the shell UI we wire
    # them directly to the underlying utilities (wpctl, playerctl,
    # brightnessctl, loginctl). Noctalia's own panels are driven over its
    # IPC surface (`noctalia msg <command…>`); Mod+Space toggles the
    # launcher below. Add settings/clipboard/etc. the same way —
    # `noctalia msg --help` lists every command.
    binds = {
      # Help + spawn
      "Mod+Shift+Slash".action.show-hotkey-overlay = [ ];
      "Mod+T".action.spawn = "ghostty";
      "Mod+Return".action.spawn = "ghostty";
      # App launcher — Noctalia's, toggled over IPC. v5: `panel-toggle <id>`.
      "Mod+Space".action.spawn = [
        "noctalia"
        "msg"
        "panel-toggle"
        "launcher"
      ];
      "Mod+D".action.spawn = "fuzzel";

      # Window
      "Mod+Q".action.close-window = [ ];

      # Column focus (arrows + vim keys)
      "Mod+Left".action.focus-column-left = [ ];
      "Mod+Right".action.focus-column-right = [ ];
      "Mod+H".action.focus-column-left = [ ];
      "Mod+L".action.focus-column-right = [ ];

      # Window focus within column (arrows). Vim J/K is reassigned below
      # to workspace switching — niri's workspaces only run vertically,
      # so J/K is the natural fit for them.
      "Mod+Down".action.focus-window-down = [ ];
      "Mod+Up".action.focus-window-up = [ ];

      # Vim-style workspace focus. Mod+U/I below still works as a
      # secondary binding (niri upstream default).
      "Mod+J".action.focus-workspace-down = [ ];
      "Mod+K".action.focus-workspace-up = [ ];

      # Column / window move (Ctrl = move). Vim Ctrl+J/K mirrors the
      # focus binding above and moves the current column to the
      # workspace below/above. Arrow Ctrl+Down/Up keeps within-column
      # window movement so that primitive isn't lost.
      "Mod+Ctrl+Left".action.move-column-left = [ ];
      "Mod+Ctrl+Right".action.move-column-right = [ ];
      "Mod+Ctrl+H".action.move-column-left = [ ];
      "Mod+Ctrl+L".action.move-column-right = [ ];
      "Mod+Ctrl+Down".action.move-window-down = [ ];
      "Mod+Ctrl+Up".action.move-window-up = [ ];
      "Mod+Ctrl+J".action.move-column-to-workspace-down = [ ];
      "Mod+Ctrl+K".action.move-column-to-workspace-up = [ ];

      # First / last column
      "Mod+Home".action.focus-column-first = [ ];
      "Mod+End".action.focus-column-last = [ ];
      "Mod+Ctrl+Home".action.move-column-to-first = [ ];
      "Mod+Ctrl+End".action.move-column-to-last = [ ];

      # Monitor focus (Shift = monitor)
      "Mod+Shift+Left".action.focus-monitor-left = [ ];
      "Mod+Shift+Right".action.focus-monitor-right = [ ];
      "Mod+Shift+Down".action.focus-monitor-down = [ ];
      "Mod+Shift+Up".action.focus-monitor-up = [ ];
      "Mod+Shift+H".action.focus-monitor-left = [ ];
      "Mod+Shift+L".action.focus-monitor-right = [ ];
      "Mod+Shift+J".action.focus-monitor-down = [ ];
      "Mod+Shift+K".action.focus-monitor-up = [ ];

      # Move column to monitor (Shift+Ctrl)
      "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [ ];
      "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [ ];
      "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [ ];
      "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [ ];
      "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = [ ];
      "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = [ ];
      "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = [ ];
      "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = [ ];

      # Workspace focus / move (Page keys + u/i)
      "Mod+Page_Down".action.focus-workspace-down = [ ];
      "Mod+Page_Up".action.focus-workspace-up = [ ];
      "Mod+U".action.focus-workspace-down = [ ];
      "Mod+I".action.focus-workspace-up = [ ];
      "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = [ ];
      "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = [ ];
      "Mod+Ctrl+U".action.move-column-to-workspace-down = [ ];
      "Mod+Ctrl+I".action.move-column-to-workspace-up = [ ];
      "Mod+Shift+Page_Down".action.move-workspace-down = [ ];
      "Mod+Shift+Page_Up".action.move-workspace-up = [ ];
      "Mod+Shift+U".action.move-workspace-down = [ ];
      "Mod+Shift+I".action.move-workspace-up = [ ];

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

      # Screenshots
      "Print".action.screenshot = [ ];
      "Ctrl+Print".action.screenshot-screen = [ ];
      "Alt+Print".action.screenshot-window = [ ];

      # Session
      "Mod+Shift+E".action.quit = [ ];
      "Mod+Shift+P".action.power-off-monitors = [ ];
      "Mod+Ctrl+Shift+T".action.toggle-debug-tint = [ ];

      # Lock. Noctalia does NOT subscribe to logind's Lock signal, so
      # `loginctl lock-session` is a no-op here — lock through Noctalia's IPC,
      # which raises its WlSessionLock directly.
      "Super+Alt+L".action.spawn = [
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

      # Brightness — Framework keyboard top row.
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

  # The idle escalation is driven entirely by Noctalia's own idle manager,
  # configured declaratively via programs.noctalia.settings.idle.behavior above:
  #
  #   - LOCK (5 min):  [idle.behavior.lock] timeout=300, `noctalia:session lock`.
  #     Locks via WlSessionLock — the ONLY path that works, since Noctalia
  #     ignores logind's Lock signal, so `loginctl lock-session` is a no-op.
  #   - SUSPEND-THEN-HIBERNATE (15 min): [idle.behavior.hibernate] timeout=900
  #     running `systemctl suspend-then-hibernate` as a user command. Suspends
  #     to RAM, then hibernates after HibernateDelaySec (3h, configuration.nix)
  #     — hibernate at 3h 15m total.
  #
  # swayidle is kept for the ONE thing a Noctalia idle command can't do: lock
  # before a sleep Noctalia didn't initiate — namely a lid close (logind's
  # HandleLidSwitch). Its before-sleep hook holds a logind sleep inhibitor and
  # raises Noctalia's lock via IPC ahead of ANY suspend/hibernate, so the
  # screen is never left unlocked on resume. No timeouts here — they live in
  # Noctalia.
  #
  # The before-sleep command resolves noctalia by absolute store path:
  # swayidle.service runs under user@.service's app.slice with a minimal PATH
  # that does NOT inherit the niri/login-shell PATH where `programs.noctalia`
  # puts the binary. Bare `noctalia` would fail with `command not
  # found`, which is exactly what lid close did before this fix.
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = "${config.programs.noctalia.package}/bin/noctalia msg session lock";
    };
  };

  # Default terminal for tools that consult $TERMINAL (lazygit edit, fzf,
  # xdg-terminal-exec helpers, etc.).
  home.sessionVariables.TERMINAL = "ghostty";

  ############################################################
  # CLI / TUI tools
  ############################################################
  home.packages = with pkgs; [
    # From the bootstrap script
    neovim
    typst
    yara-x # binary is `yr`
    gum
    crush # charmbracelet/crush
    glow
    gh
    railway
    lazydocker
    btop
    fastfetch
    jq
    fd
    mosh

    # Compiler. `pkgs.gcc` resolves to the current nixpkgs default
    # (gcc-wrapper around gcc 14.x at time of writing); pin to e.g.
    # `gcc13`/`gcc14` if a project needs a specific ABI.
    gcc

    # q-text-as-data is packaged in nixpkgs, so we pull it in here instead of
    # via pipx. JFryy/qq is built from source in the `let` above;
    # basecamp/fizzy-cli is the prebuilt v3.0.3 binary, also from `let`.
    q-text-as-data
    qq
    fizzy-cli
    # pipx itself is still NOT installed via Nix: build-time deps in current
    # nixos-unstable (black, black[extras], nox) cycle through transient
    # failures. Install pipx + jsongrep (not in nixpkgs) manually post-boot
    # (mise provides python):
    #   pip install --user pipx
    #   pipx ensurepath
    #   pipx install jsongrep

    # Wayland / niri ergonomics
    wl-clipboard
    # macOS-style aliases for wl-copy / wl-paste so muscle memory works:
    # `echo foo | pbcopy`, `pbpaste`. pbcopy is a bare wl-copy symlink;
    # pbpaste is a wrapper that adds `--no-newline` to match macOS pbpaste
    # — wl-paste's default appends a \n, which doubles up when the copied
    # content already ends with one (e.g. anything piped from `echo`).
    (writeShellScriptBin "pbcopy" ''exec ${wl-clipboard}/bin/wl-copy "$@"'')
    (writeShellScriptBin "pbpaste" ''exec ${wl-clipboard}/bin/wl-paste --no-newline "$@"'')
    brightnessctl
    playerctl
    matugen
    cava
    xwayland-satellite

    # Needed for Noctalia's GTK theming pipeline:
    # - python3 runs Scripts/python/src/theming/gtk-refresh.py (postProcess hook)
    # - glib provides gsettings, which the script calls to push color-scheme
    #   and gtk-theme into org.gnome.desktop.interface so GTK3/4 apps reload.
    python3
    glib

    # AI CLIs — Option B (hourly-updated flake). For Option A, delete the next
    # binding and add `claude-code` to this list instead.
    #
    # Wrapped so a bare `claude` (no args) starts with Remote Control enabled —
    # this is a PATH-level wrapper, not a shell alias, so it also covers
    # non-interactive starts (niri/fuzzel spawns, scripts), which an alias
    # misses. The flag is added ONLY when there are no args: `--remote-control`
    # takes an optional [name], so prepending it unconditionally would make
    # `claude update` / `claude -p …` / `claude --resume` misparse their first
    # arg as the session name. Any invocation with args passes straight through.
    (
      let
        claudePkg = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
        claudeWrapper = writeShellScript "claude-remote-control" ''
          if [ "$#" -eq 0 ]; then
            exec ${claudePkg}/bin/claude --remote-control
          fi
          exec ${claudePkg}/bin/claude "$@"
        '';
      in
      symlinkJoin {
        name = "claude-code-remote-control";
        paths = [ claudePkg ];
        postBuild = ''
          rm "$out/bin/claude"
          ln -s ${claudeWrapper} "$out/bin/claude"
        '';
      }
    )
    gemini-cli

    # ogulcancelik/herdr — terminal workspace manager for AI coding agents
    # (panes, sessions that survive detach). Tag-pinned in flake.nix to
    # match the herdr server version; bump by editing the tag there.
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  ############################################################
  # Shell + integrations (replaces the script's ~/.zshrc edits)
  ############################################################
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      tree = "eza --tree";
      cat = "bat";
    };
    # Append ~/.local/bin to PATH for imperatively-installed user binaries:
    # pipx drops console scripts here (see pipx note in home.packages above),
    # and `claude update` maintains its own native install at
    # ~/.local/bin/claude. Appended (not prepended via home.sessionPath) so
    # the Nix-managed claude-code from the flake input still wins on PATH;
    # ~/.local/bin/claude exists but is shadowed, which silences `claude
    # update`'s PATH warning without changing which binary actually runs.
    # In initExtra (interactive-shell .zshrc) because Ghostty (and most
    # terminal emulators) launch zsh as a non-login interactive shell, so
    # .zprofile never sources; .zshrc does. `typeset -U path` dedupes if a
    # parent shell already appended it.
    initContent = ''
      typeset -U path
      path+=("$HOME/.local/bin")
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd cd" ]; # cd -> zoxide, matching the script
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
  };

  # bat — syntax-highlighted `cat` (see shellAliases above). Ships a
  # Noctalia-mono tmTheme inline; scopes lean on the same brightness/bold
  # gradations the nvim colorscheme uses so highlighted code reads
  # consistently across both renderers.
  programs.bat = {
    enable = true;
    config.theme = "Noctalia-Mono";
    themes."Noctalia-Mono" = {
      src = pkgs.writeTextDir "Noctalia-Mono.tmTheme" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>name</key><string>Noctalia Mono</string>
          <key>settings</key>
          <array>
            <dict><key>settings</key><dict>
              <key>background</key><string>#111111</string>
              <key>foreground</key><string>#aaaaaa</string>
              <key>caret</key><string>#cccccc</string>
              <key>lineHighlight</key><string>#191919</string>
              <key>selection</key><string>#3c3c3c</string>
            </dict></dict>
            <dict><key>scope</key><string>comment</string><key>settings</key><dict>
              <key>foreground</key><string>#5d5d5d</string>
              <key>fontStyle</key><string>italic</string>
            </dict></dict>
            <dict><key>scope</key><string>string</string><key>settings</key><dict>
              <key>foreground</key><string>#828282</string>
            </dict></dict>
            <dict><key>scope</key><string>constant.numeric, constant.language</string><key>settings</key><dict>
              <key>foreground</key><string>#cccccc</string>
            </dict></dict>
            <dict><key>scope</key><string>keyword, storage, storage.type</string><key>settings</key><dict>
              <key>foreground</key><string>#aaaaaa</string>
              <key>fontStyle</key><string>bold</string>
            </dict></dict>
            <dict><key>scope</key><string>entity.name.function, support.function</string><key>settings</key><dict>
              <key>foreground</key><string>#dddddd</string>
              <key>fontStyle</key><string>bold</string>
            </dict></dict>
            <dict><key>scope</key><string>entity.name.type, entity.name.class, support.type</string><key>settings</key><dict>
              <key>foreground</key><string>#cccccc</string>
            </dict></dict>
            <dict><key>scope</key><string>variable</string><key>settings</key><dict>
              <key>foreground</key><string>#aaaaaa</string>
            </dict></dict>
            <dict><key>scope</key><string>keyword.operator, punctuation</string><key>settings</key><dict>
              <key>foreground</key><string>#828282</string>
            </dict></dict>
          </array>
          <key>uuid</key><string>00000000-noctalia-mono-bat</string>
        </dict>
        </plist>
      '';
      file = "Noctalia-Mono.tmTheme";
    };
  };

  # starship — prompt. Noctalia owns the palette now (issue #62). The
  # `starship` builtin template writes ~/.cache/noctalia/starship-palette.toml
  # and its apply.sh injects a `[palettes.noctalia]` block into
  # ~/.config/starship.toml between markers. That in-place edit REQUIRES a
  # writable config, so — unlike ghostty — we can't let home-manager own
  # starship.toml as a read-only store symlink (settings must be empty or HM
  # writes the file and Noctalia clobbers it). Instead we keep programs.starship
  # enabled only for the shell init and seed a writable base config in
  # home.activation.starshipConfigSeed below.
  #
  # Module styles reference Noctalia's palette color NAMES, which are
  # Catppuccin-compatible (text/subtext/overlay/…) — NOT the old
  # accent/dim/faint/bright/fg. Remap under m3-monochrome (all grayscale):
  #   accent/git_status → subtext1   bright/root → text
  #   fg/directory      → text       dim  → overlay1   faint → overlay0
  # The [palettes.noctalia] table itself is deliberately NOT defined here —
  # Noctalia injects it; defining it too would make a duplicate TOML table.
  programs.starship.enable = true;

  # ghostty — primary terminal (see niri binds + home.sessionVariables.TERMINAL).
  # Noctalia owns the theme now (issue #62): the `ghostty` builtin template
  # renders the colors to ~/.config/ghostty/themes/noctalia, and its apply.sh
  # no-ops on THIS config the moment it sees `theme = noctalia` already set —
  # so our read-only home-manager symlink is never materialized/clobbered
  # (that clobber is exactly what broke the first v5 rebuild). Under
  # theme.wallpaper_scheme = "m3-monochrome" the generated palette stays
  # grayscale, matching the zellij/nvim mono aesthetic. font stays declarative.
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "noctalia";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
    };
  };

  # lazygit — git TUI. Colors take YAML list form: [hex, "bold"] etc.
  # nerdFontsVersion = "3" to match the JetBrainsMono Nerd Font shipped
  # in configuration.nix.
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        theme = {
          activeBorderColor = [
            "#cccccc"
            "bold"
          ];
          inactiveBorderColor = [ "#3c3c3c" ];
          searchingActiveBorderColor = [
            "#dddddd"
            "bold"
          ];
          selectedLineBgColor = [ "#191919" ];
          optionsTextColor = [ "#aaaaaa" ];
          cherryPickedCommitBgColor = [ "#3c3c3c" ];
          cherryPickedCommitFgColor = [ "#cccccc" ];
          markedBaseCommitBgColor = [ "#3c3c3c" ];
          markedBaseCommitFgColor = [ "#cccccc" ];
          unstagedChangesColor = [ "#dddddd" ];
          defaultFgColor = [ "#aaaaaa" ];
        };
      };
    };
  };

  # fuzzel — Mod+D launcher. Colors take aRRGGBB hex (alpha-first). Border
  # gets a thin Noctalia outline; main.terminal points at ghostty so any
  # exec entries respect the system terminal.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=12";
        terminal = "ghostty";
        icon-theme = "Papirus-Dark";
        width = 50;
      };
      border = {
        width = 1;
        radius = 4;
      };
      colors = {
        background = "111111ff";
        text = "aaaaaaff";
        match = "ddddddff";
        selection = "3c3c3cff";
        selection-text = "ccccccff";
        selection-match = "ddddddff";
        border = "3c3c3cff";
      };
    };
  };

  # zellij — terminal multiplexer. Shipped with a "noctalia-mono" theme
  # that mirrors the stock Noctalia palette from ~/.config/noctalia/colors.json
  # (mSurface / mPrimary / mTertiary). It's statically pinned: if the
  # Noctalia wallpaper changes and the palette shifts off mono, zellij
  # won't follow until you regenerate this block. enableZshIntegration is
  # intentionally OFF — upstream's hook auto-attaches on every new shell,
  # which is too invasive. Invoke `zellij` manually.
  programs.zellij = {
    enable = true;
    settings = {
      theme = "noctalia-mono";
      default_layout = "compact";
    };
    themes.noctalia-mono = ''
      themes {
          noctalia-mono {
              fg "#aaaaaa"
              bg "#111111"
              black "#111111"
              red "#dddddd"
              green "#aaaaaa"
              yellow "#cccccc"
              blue "#a7a7a7"
              magenta "#828282"
              cyan "#cccccc"
              white "#cccccc"
              orange "#cccccc"
          }
      }
    '';
  };

  # mise for per-project runtime pins (python/node/go)
  #
  # nix-ld (in configuration.nix) is what makes mise's pre-built binaries
  # runnable on NixOS at all — without it the linker path under /lib64
  # 404s and nothing launches. The settings below tune *which* pre-built
  # binaries mise reaches for.
  #
  # python.compile / node.compile = false force mise to use the precompiled
  # binaries (python-build-standalone for python; nodejs.org tarballs for
  # node) rather than building from source via python-build / node-build.
  # Compiling needs a full build toolchain on PATH (gcc, make, openssl-dev,
  # bzip2-dev, readline-dev, sqlite-dev, …) — exactly the FHS-shaped pile of
  # dev libs NixOS doesn't make convenient. Both also default to "try
  # precompiled, fall back to compile" and the fallback path is silent;
  # pinning to `false` turns it into a loud failure instead of a 5-minute
  # source build that ends in `make: command not found`. go is precompiled
  # only — no equivalent knob — and nix-ld alone covers it at runtime.
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    globalConfig = {
      tools = {
        python = "latest";
        node = "lts";
        pnpm = "latest";
        go = "latest";
      };
      settings = {
        python.compile = false;
        node.compile = false;
      };
    };
  };

  # GTK theming. adw-gtk3-dark is a libadwaita-style GTK3 port — it's
  # exactly what Noctalia's gtk-refresh.py expects to switch to (script
  # hardcodes "adw-gtk3" / "adw-gtk3-dark" as the target via gsettings).
  # Noctalia's gtk3/gtk4 templates write ~/.config/gtk-{3,4}.0/noctalia.css on
  # each wallpaper change; the @import in our managed gtk.css pulls those
  # @define-color overrides into every GTK app without us touching gtk.css
  # ourselves. enableUserTheming stays off — we use only the built-in gtk3/gtk4
  # templates, enabled via programs.noctalia.settings.theme.templates.
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
    gtk3 = {
      extraConfig.gtk-application-prefer-dark-theme = 1;
      extraCss = ''
        @import url("noctalia.css");
      '';
    };
    gtk4 = {
      extraConfig.gtk-application-prefer-dark-theme = 1;
      extraCss = ''
        @import url("noctalia.css");
      '';
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Scott J Roberts";
        # GitHub's "no-reply" form for this account (numeric user ID +
        # username). Lets the repo go public without putting the real
        # email in future commits' diffs / Author lines, while still
        # being correctly attributed on GitHub.
        email = "44774+sroberts@users.noreply.github.com";
      };
      # Delegate GitHub HTTPS auth to gh so git push uses the token gh stores
      # in the system keyring. Declared here because home-manager renders
      # ~/.config/git/config as a read-only store symlink — `gh auth setup-git`
      # can't write into it at runtime.
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";
    };
  };

  programs.home-manager.enable = true;

  ############################################################
  # Activation hooks — the imperative bits Nix can't declare
  ############################################################

  # LazyVim starter — clone once, leave existing config alone
  home.activation.lazyvimStarter = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      if [ ! -e "$HOME/.config/nvim" ]; then
        ${pkgs.git}/bin/git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
        rm -rf "$HOME/.config/nvim/.git"
      fi
    '';
  };

  # Materialize mise-managed tools at rebuild time, not lazily on first
  # shell. `programs.mise.globalConfig.tools` (above) only writes the TOML;
  # the actual download happens on `mise install` or when a shell with the
  # activate hook touches a directory whose config references the tool.
  # That's why `which go` could 404 right after a rebuild even though the
  # eval line is in ~/.zshrc — go hadn't been installed yet. Running
  # `mise install` here makes the rebuild authoritative for what's on disk.
  # `|| true` so a transient network failure during activation doesn't
  # block the whole rebuild — mise will retry on next switch or shell.
  home.activation.miseInstall = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      ${pkgs.mise}/bin/mise install --yes 2>&1 || true
    '';
  };

  # CyberChef — no nixpkgs package; pull the latest release zip
  home.activation.cyberchef = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      DEST="$HOME/.local/share/cyberchef"
      LAUNCHER="$HOME/.local/bin/cyberchef"
      if [ ! -x "$LAUNCHER" ] || [ ! -d "$DEST" ]; then
        TMP=$(${pkgs.coreutils}/bin/mktemp -d)
        URL=$(${pkgs.curl}/bin/curl -fsSL https://api.github.com/repos/gchq/CyberChef/releases/latest \
              | ${pkgs.gnugrep}/bin/grep -oE '"browser_download_url": *"[^"]+\.zip"' \
              | ${pkgs.coreutils}/bin/head -1 \
              | ${pkgs.gnused}/bin/sed -E 's/.*"(https[^"]+)".*/\1/')
        if [ -n "$URL" ]; then
          ${pkgs.curl}/bin/curl -fsSL -o "$TMP/cc.zip" "$URL" && {
            ${pkgs.coreutils}/bin/mkdir -p "$DEST" "$HOME/.local/bin"
            ${pkgs.unzip}/bin/unzip -q -o "$TMP/cc.zip" -d "$DEST"
            IDX=$(${pkgs.findutils}/bin/find "$DEST" -maxdepth 3 -name 'CyberChef_v*.html' -print -quit)
            [ -z "$IDX" ] && IDX=$(${pkgs.findutils}/bin/find "$DEST" -maxdepth 3 -name 'index.html' -print -quit)
            if [ -n "$IDX" ]; then
              ${pkgs.coreutils}/bin/printf '#!/usr/bin/env bash\nxdg-open "%s"\n' "$IDX" > "$LAUNCHER"
              ${pkgs.coreutils}/bin/chmod +x "$LAUNCHER"
            fi
          }
        fi
        ${pkgs.coreutils}/bin/rm -rf "$TMP"
      fi
    '';
  };

  # Impeccable — AI design skill for Claude Code (https://impeccable.style).
  # Not in nixpkgs; installed via `npx impeccable install`, which auto-detects
  # the coding tool and writes the skill under .claude/skills/. Run from $HOME
  # so its "project" install lands in the *global* skills dir (~/.claude/skills/,
  # available in every project — same place ~/.claude/skills/fizzy lives).
  #
  # Two things this hook has to paper over, both because home-manager runs
  # activation with a bare PATH (coreutils/findutils/grep/sed only — no node,
  # no shell) and no TTY:
  #   1. The installer prompts for target + location. Redirecting stdin from
  #      /dev/null makes those reads hit EOF and take the defaults
  #      (detected-harnesses / project), so it never blocks on a missing TTY.
  #   2. npx spawns child processes that need `node` AND a shell on PATH. With
  #      the bare activation PATH those fail with `spawn sh ENOENT` / `node:
  #      not found` and nothing installs. So prepend nodejs to PATH and point
  #      npm's script-shell at bash (nixpkgs bash has bin/bash but no bin/sh,
  #      which is exactly the `sh` npm can't find otherwise).
  # `.claude` is pre-created so auto-detection resolves to Claude Code on a
  # fresh box; guard on the installed skill dir so reruns are a no-op; --yes so
  # npx never stops to confirm the one-off package download; `|| true` so a
  # network hiccup doesn't fail the rebuild (next switch retries, like cyberchef).
  home.activation.impeccable = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      if [ ! -d "$HOME/.claude/skills/impeccable" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$HOME/.claude"
        ( cd "$HOME" \
          && PATH="${pkgs.nodejs}/bin:$PATH" \
             npm_config_script_shell="${pkgs.bash}/bin/bash" \
             ${pkgs.nodejs}/bin/npx --yes impeccable install </dev/null ) 2>&1 || true
      fi
    '';
  };

  # Default wallpaper. Copies the tracked asset (assets/default-wallpaper.jpg)
  # into the Noctalia-configured wallpaper directory so the file exists on a
  # fresh $HOME. The actual "use this on first boot" wiring is declarative in
  # v5 — programs.noctalia.settings.wallpaper.default.path points here, and
  # Noctalia derives the Material You palette (→ gtk3/gtk4 templates → GTK)
  # from it. Idempotent: skips the copy if the file already exists. Once the
  # user picks another wallpaper in the UI, that choice lands in settings.toml
  # and takes over. The asset lives in the repo so a fresh install never
  # depends on a third-party URL.
  home.activation.defaultWallpaper = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      DIR="$HOME/Pictures/Wallpapers"
      DEST="$DIR/default-wallpaper.jpg"
      SRC="${./assets/default-wallpaper.jpg}"
      ${pkgs.coreutils}/bin/mkdir -p "$DIR"
      if [ ! -f "$DEST" ]; then
        ${pkgs.coreutils}/bin/install -m 0644 "$SRC" "$DEST"
      fi
    '';
  };

  # Writable base config for starship (see programs.starship above). Noctalia's
  # starship template edits ~/.config/starship.toml in place to inject its
  # palette, so this file cannot be a read-only home-manager symlink. We seed
  # the declarative base (module styles, palette name — but NOT the palette
  # table, which Noctalia appends) into a plain writable file. Change-detected
  # against the store path of the base: on a fresh $HOME or whenever the base
  # content below changes we (re)write it, otherwise we leave the file alone so
  # Noctalia's injected [palettes.noctalia] block survives rebuilds. After a
  # (re)seed the block is briefly absent until Noctalia next applies the theme
  # (shell start / wallpaper change) — starship just falls back to defaults in
  # the meantime.
  home.activation.starshipConfigSeed = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      DEST="$HOME/.config/starship.toml"
      STAMP="$HOME/.cache/noctalia/.starship-base-src"
      SRC="${pkgs.writeText "starship-base.toml" ''
        add_newline = false
        palette = "noctalia"

        [character]
        success_symbol = "[➜](bold subtext1)"
        error_symbol = "[➜](bold text)"

        [directory]
        style = "text bold"

        [git_branch]
        style = "overlay1"

        [git_status]
        style = "subtext1"

        [cmd_duration]
        style = "overlay0"

        [hostname]
        style = "overlay1"

        [username]
        style_user = "overlay1"
        style_root = "text bold"
      ''}"
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$DEST")" \
                                     "$(${pkgs.coreutils}/bin/dirname "$STAMP")"
      if [ ! -f "$DEST" ] || \
         [ "$(${pkgs.coreutils}/bin/cat "$STAMP" 2>/dev/null)" != "$SRC" ]; then
        ${pkgs.coreutils}/bin/rm -f "$DEST"
        ${pkgs.coreutils}/bin/install -m 0644 "$SRC" "$DEST"
        printf '%s' "$SRC" > "$STAMP"
      fi
    '';
  };

  # User avatar at ~/.face (the conventional path login managers, greeters,
  # and AccountsService read). Pulled from GitHub; download to a temp file
  # and move into place so a failed fetch never leaves a truncated ~/.face.
  home.activation.faceIcon = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      if [ ! -e "$HOME/.face" ]; then
        TMP=$(${pkgs.coreutils}/bin/mktemp)
        if ${pkgs.curl}/bin/curl -fsSL -o "$TMP" "https://avatars.githubusercontent.com/u/44774?v=4"; then
          ${pkgs.coreutils}/bin/mv "$TMP" "$HOME/.face"
        else
          ${pkgs.coreutils}/bin/rm -f "$TMP"
        fi
      fi
    '';
  };

  # Noctalia config is fully declarative in v5 — see programs.noctalia.settings
  # above (→ ~/.config/noctalia/config.toml, build-time validated). v4's
  # home.activation.noctaliaConfigSeed (which hand-wrote settings.json +
  # plugins.json and jq-asserted the fprintd flags) is gone: v5 renamed and
  # restructured every one of those keys, moved the polkit agent into
  # [shell].polkit_agent, and dropped the QML LockContext fingerprint flags
  # entirely (auth is now native C++). Runtime settings-UI changes are written
  # to a separate ~/.config/noctalia/settings.toml overrides file, so nothing
  # here needs to hand a mutable file to Noctalia the way v4 did.

  # Default browser. Signal's Electron shell rewrites ~/.config/mimeapps.list
  # on first launch when no default is set, hijacking http/https/text/html
  # for itself — so `xdg-open https://...` (e.g. `gh auth refresh`) opens
  # Signal instead of a browser. home-manager replaces mimeapps.list with a
  # store-path symlink, which Signal can't clobber.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium-browser.desktop";
      "x-scheme-handler/http" = "chromium-browser.desktop";
      "x-scheme-handler/https" = "chromium-browser.desktop";
      "x-scheme-handler/about" = "chromium-browser.desktop";
      "x-scheme-handler/unknown" = "chromium-browser.desktop";
      # Claude Code's URL handler (claude-cli://...) — preserved from the
      # runtime mimeapps.list so `claude` URL launches still work.
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

  # Typora theme matching Noctalia's monochrome dark palette.
  # Lives at ~/.config/Typora/themes/noctalia-mono.css; Typora reads themes
  # but never writes them, so a store-path symlink is fine here (unlike the
  # Noctalia configs above). Pick it via Themes → Noctalia Mono after first
  # rebuild — Typora persists the selection in its profile.data.
  xdg.configFile."Typora/themes/noctalia-mono.css".text = ''
    @charset "UTF-8";

    /* Noctalia-mono palette
       mSurface         #111111   mSurfaceVariant  #191919
       mOutline         #3c3c3c   mOnSurfaceVariant #5d5d5d
       mOnSurface       #828282   mPrimary         #aaaaaa
       mTertiary        #cccccc */

    :root {
      --bg-color:                 #111111;
      --side-bar-bg-color:        #191919;
      --control-text-color:       #aaaaaa;
      --text-color:               #cccccc;
      --meta-content-color:       #5d5d5d;
      --primary-color:            #aaaaaa;
      --active-file-bg-color:     #2a2a2a;
      --active-file-text-color:   #cccccc;
      --active-file-border-color: #aaaaaa;
      --item-hover-bg-color:      #1f1f1f;
      --item-hover-text-color:    #cccccc;
      --rawblock-edit-panel-bd:   #3c3c3c;
      --window-border:            #3c3c3c;
      --select-text-bg-color:     #3c3c3c;
      --select-text-font-color:   #ffffff;
      --md-char-color:            #5d5d5d;
      --heading-char-color:       #828282;
      --code-block-bg-color:      #0a0a0a;
    }

    html, body, content, #write {
      background: #111111;
      color:      #cccccc;
    }

    /* Chrome: title bar, tabs, status bar, footer */
    header, footer, .typora-quick-open, .megamenu-menu, #top-titlebar,
    .ty-window-control, .typora-sourceview-buttons, #footer-word-count,
    #footer-word-count-info, .footer-item, .footer-item-right {
      background: #191919;
      color:      #aaaaaa;
      border-color: #3c3c3c;
    }

    /* Tab bar */
    .tab-bar, #file-tabs, .file-tab, .file-tab-name {
      background: #191919;
      color:      #aaaaaa;
      border-color: #3c3c3c;
    }
    .file-tab.active {
      background: #111111;
      color:      #cccccc;
    }

    /* Sidebar */
    #typora-sidebar, .sidebar-content, .sidebar-tabs, .outline-content,
    .file-tree, .file-list-item, .file-node-content, .info-panel-tab,
    .sidebar-footer {
      background: #191919;
      color:      #aaaaaa;
      border-color: #3c3c3c;
    }
    .file-node-content:hover, .file-list-item:hover, .outline-item:hover {
      background: #1f1f1f;
      color:      #cccccc;
    }
    .file-node-content.active, .file-list-item.active, .outline-active {
      background: #2a2a2a;
      color:      #cccccc;
    }

    /* Menus (hamburger megamenu + right-click context) */
    .megamenu-content, .megamenu-menu-panel, .megamenu-menu-list,
    .megamenu-menu-header, #context-menu, .context-menu, .dropdown-menu,
    .modal-content {
      background: #191919;
      color:      #cccccc;
      border-color: #3c3c3c;
    }
    .megamenu-menu-list li:hover, .context-menu li:hover,
    .dropdown-menu li:hover, .dropdown-menu a:hover {
      background: #2a2a2a;
      color:      #ffffff;
    }
    .megamenu-menu-header-title { color: #cccccc; }

    /* Search / find-replace bar */
    .searchpanel, #typora-search-panel, .search-input, .ty-search-result,
    .ty-find-target, .typora-search-input {
      background: #191919;
      color:      #cccccc;
      border-color: #3c3c3c;
    }

    /* Source mode */
    #typora-source, .CodeMirror, .CodeMirror-gutters {
      background: #0a0a0a;
      color:      #cccccc;
      border-color: #3c3c3c;
    }
    .CodeMirror-cursor { border-left-color: #cccccc; }

    /* Headings + inline code */
    h1, h2, h3, h4, h5, h6 { color: #ffffff; }
    code, tt {
      background: #0a0a0a;
      color:      #cccccc;
    }
    pre.md-fences, .md-fences {
      background:   #0a0a0a;
      color:        #cccccc;
      border-color: #3c3c3c;
    }

    /* Links + blockquotes */
    a { color: #cccccc; }
    a:hover { color: #ffffff; }
    blockquote {
      border-left-color: #3c3c3c;
      color: #aaaaaa;
    }

    /* Tables + hr */
    table, thead, tbody, tr, th, td {
      background: #111111;
      color:      #cccccc;
      border-color: #3c3c3c;
    }
    hr { border-color: #3c3c3c; }
  '';

  # Neovim / LazyVim — Noctalia-mono colorscheme. Two files:
  #   colors/noctalia-mono.lua      — highlight definitions; nvim picks it up
  #                                   automatically via the runtime path so
  #                                   `:colorscheme noctalia-mono` works.
  #   lua/plugins/colorscheme.lua   — LazyVim spec that sets it as the default.
  # The LazyVim starter clone (home.activation.lazyvimStarter) creates the
  # parent dirs but never these specific files, so the home-manager symlinks
  # land without conflict. Palette mirrors ~/.config/noctalia/colors.json
  # (mSurface / mPrimary / mTertiary / mOutline); statically pinned in the
  # same way as the zellij and Typora themes.
  xdg.configFile."nvim/colors/noctalia-mono.lua".text = ''
    -- Noctalia-mono. Mirrors ~/.config/noctalia/colors.json.
    vim.cmd("highlight clear")
    if vim.fn.exists("syntax_on") == 1 then
      vim.cmd("syntax reset")
    end
    vim.g.colors_name = "noctalia-mono"
    vim.o.background = "dark"
    vim.o.termguicolors = true

    local p = {
      bg       = "#111111", -- mSurface
      bg_alt   = "#191919", -- mSurfaceVariant
      bg_float = "#1a1a1a",
      fg       = "#aaaaaa", -- mPrimary
      fg_dim   = "#828282", -- mOnSurface
      fg_faint = "#5d5d5d", -- mOnSurfaceVariant
      border   = "#3c3c3c", -- mOutline
      accent   = "#cccccc", -- mTertiary / mHover
      bright   = "#dddddd", -- mError (brightest)
    }

    local function hi(g, o) vim.api.nvim_set_hl(0, g, o) end

    -- Editor core
    hi("Normal",         { fg = p.fg, bg = p.bg })
    hi("NormalFloat",    { fg = p.fg, bg = p.bg_float })
    hi("FloatBorder",    { fg = p.border, bg = p.bg_float })
    hi("FloatTitle",     { fg = p.accent, bg = p.bg_float, bold = true })
    hi("ColorColumn",    { bg = p.bg_alt })
    hi("Cursor",         { fg = p.bg, bg = p.fg })
    hi("CursorLine",     { bg = p.bg_alt })
    hi("CursorLineNr",   { fg = p.accent, bold = true })
    hi("LineNr",         { fg = p.fg_faint })
    hi("SignColumn",     { fg = p.fg_faint, bg = p.bg })
    hi("FoldColumn",     { fg = p.fg_faint, bg = p.bg })
    hi("Folded",         { fg = p.fg_dim, bg = p.bg_alt })
    hi("EndOfBuffer",    { fg = p.bg })
    hi("NonText",        { fg = p.fg_faint })
    hi("Whitespace",     { fg = p.border })
    hi("MatchParen",     { fg = p.bright, bold = true, underline = true })
    hi("Search",         { fg = p.bg, bg = p.accent })
    hi("IncSearch",      { fg = p.bg, bg = p.bright, bold = true })
    hi("CurSearch",      { fg = p.bg, bg = p.bright, bold = true })
    hi("Visual",         { bg = p.border })
    hi("StatusLine",     { fg = p.fg, bg = p.bg_alt })
    hi("StatusLineNC",   { fg = p.fg_dim, bg = p.bg_alt })
    hi("WinSeparator",   { fg = p.border })
    hi("TabLine",        { fg = p.fg_dim, bg = p.bg_alt })
    hi("TabLineFill",    { bg = p.bg })
    hi("TabLineSel",     { fg = p.bg, bg = p.accent, bold = true })
    hi("Title",          { fg = p.accent, bold = true })
    hi("Directory",      { fg = p.accent })
    hi("ModeMsg",        { fg = p.fg, bold = true })
    hi("MoreMsg",        { fg = p.accent })
    hi("Question",       { fg = p.accent })
    hi("WarningMsg",     { fg = p.bright })
    hi("ErrorMsg",       { fg = p.bright, bold = true })
    hi("Pmenu",          { fg = p.fg, bg = p.bg_alt })
    hi("PmenuSel",       { fg = p.bg, bg = p.accent, bold = true })
    hi("PmenuSbar",      { bg = p.bg_alt })
    hi("PmenuThumb",     { bg = p.border })

    -- Syntax
    hi("Comment",        { fg = p.fg_faint, italic = true })
    hi("Constant",       { fg = p.fg, bold = true })
    hi("String",         { fg = p.fg_dim })
    hi("Character",      { fg = p.fg_dim })
    hi("Number",         { fg = p.accent })
    hi("Boolean",        { fg = p.accent, bold = true })
    hi("Float",          { fg = p.accent })
    hi("Identifier",     { fg = p.fg })
    hi("Function",       { fg = p.bright, bold = true })
    hi("Statement",      { fg = p.fg, bold = true })
    hi("Keyword",        { fg = p.fg, bold = true })
    hi("Operator",       { fg = p.accent })
    hi("PreProc",        { fg = p.fg_dim })
    hi("Type",           { fg = p.accent })
    hi("Special",        { fg = p.accent })
    hi("Underlined",     { fg = p.accent, underline = true })
    hi("Todo",           { fg = p.bg, bg = p.bright, bold = true })

    -- Treesitter
    hi("@variable",                { fg = p.fg })
    hi("@property",                { fg = p.fg })
    hi("@field",                   { fg = p.fg })
    hi("@punctuation.delimiter",   { fg = p.fg_dim })
    hi("@punctuation.bracket",     { fg = p.fg_dim })

    -- Diagnostics
    hi("DiagnosticError",          { fg = p.bright, bold = true })
    hi("DiagnosticWarn",           { fg = p.accent })
    hi("DiagnosticInfo",           { fg = p.fg_dim })
    hi("DiagnosticHint",           { fg = p.fg_faint })
    hi("DiagnosticUnderlineError", { sp = p.bright, undercurl = true })
    hi("DiagnosticUnderlineWarn",  { sp = p.accent, undercurl = true })
    hi("DiagnosticUnderlineInfo",  { sp = p.fg_dim, undercurl = true })
    hi("DiagnosticUnderlineHint",  { sp = p.fg_faint, undercurl = true })

    -- Diff
    hi("DiffAdd",    { bg = p.bg_alt })
    hi("DiffChange", { bg = p.bg_alt })
    hi("DiffDelete", { fg = p.fg_faint, bg = p.bg_alt })
    hi("DiffText",   { fg = p.bright, bg = p.bg_alt, bold = true })

    -- Telescope
    hi("TelescopeNormal",        { fg = p.fg, bg = p.bg_float })
    hi("TelescopeBorder",        { fg = p.border, bg = p.bg_float })
    hi("TelescopePromptNormal",  { fg = p.fg, bg = p.bg_alt })
    hi("TelescopePromptBorder",  { fg = p.border, bg = p.bg_alt })
    hi("TelescopePromptTitle",   { fg = p.bg, bg = p.accent, bold = true })
    hi("TelescopePreviewTitle",  { fg = p.bg, bg = p.accent, bold = true })
    hi("TelescopeResultsTitle",  { fg = p.fg_dim, bg = p.bg_float })
    hi("TelescopeSelection",     { fg = p.accent, bg = p.bg_alt, bold = true })
    hi("TelescopeMatching",      { fg = p.bright, bold = true })

    -- Neo-tree
    hi("NeoTreeNormal",         { fg = p.fg, bg = p.bg })
    hi("NeoTreeNormalNC",       { fg = p.fg, bg = p.bg })
    hi("NeoTreeRootName",       { fg = p.accent, bold = true })
    hi("NeoTreeFileName",       { fg = p.fg })
    hi("NeoTreeDirectoryIcon",  { fg = p.fg_dim })
    hi("NeoTreeDirectoryName",  { fg = p.fg })
    hi("NeoTreeFloatBorder",    { fg = p.border, bg = p.bg_float })
    hi("NeoTreeTitleBar",       { fg = p.bg, bg = p.accent, bold = true })

    -- Which-key
    hi("WhichKey",          { fg = p.accent, bold = true })
    hi("WhichKeyGroup",     { fg = p.fg })
    hi("WhichKeyDesc",      { fg = p.fg_dim })
    hi("WhichKeySeparator", { fg = p.border })
    hi("WhichKeyFloat",     { bg = p.bg_float })
    hi("WhichKeyBorder",    { fg = p.border, bg = p.bg_float })

    -- Noice
    hi("NoiceCmdline",       { fg = p.fg, bg = p.bg_alt })
    hi("NoiceCmdlineIcon",   { fg = p.accent })
    hi("NoicePopup",         { fg = p.fg, bg = p.bg_float })
    hi("NoicePopupBorder",   { fg = p.border, bg = p.bg_float })

    -- Gitsigns
    hi("GitSignsAdd",    { fg = p.fg })
    hi("GitSignsChange", { fg = p.accent })
    hi("GitSignsDelete", { fg = p.fg_faint })
  '';

  xdg.configFile."nvim/lua/plugins/colorscheme.lua".text = ''
    -- Hooks LazyVim into the noctalia-mono colorscheme defined in
    -- ~/.config/nvim/colors/noctalia-mono.lua.
    return {
      {
        "LazyVim/LazyVim",
        opts = {
          colorscheme = "noctalia-mono",
        },
      },
    }
  '';

  # Post-install TODO checklist
  home.activation.todoMd = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
            if [ ! -f "$HOME/TODO.md" ]; then
              ${pkgs.coreutils}/bin/cat > "$HOME/TODO.md" <<'TODO'
      # Post-install TODO

      Things the flake can't do for you.

      - [ ] Connect to Wifi (or verify NetworkManager picked it up)
      - [ ] Sign into 1Password (desktop + Chromium extension)
      - [ ] Sign into Gmail
      - [ ] Sign into GitHub: `gh auth login`
      - [ ] Join Tailscale: `sudo tailscale up`
      - [ ] Set up Obsidian Sync + enable Iconize community plugin
      - [ ] Register Typora license
      - [ ] Pick Typora theme: Themes → Noctalia Mono
      - [ ] Chromium extensions: sign in to 1Password / Obsidian Web Clipper / Instapaper (the extensions install themselves via configuration.nix)
      - [ ] Sign in to Slack, Discord, Signal, Zoom
      - [ ] Download Playdate Simulator: https://play.date/dev/
      - [ ] Check mise toolchains landed: `mise ls` — if python/node/go show `(missing)`, re-run `mise install` (the rebuild hook's `|| true` swallows transient network failures)
      - [ ] Install pipx + jsongrep: `pip install --user pipx && pipx ensurepath && pipx install jsongrep`
      - [ ] Authenticate Claude Code: run `claude`
      - [ ] Authenticate Gemini CLI: `gemini auth`
      - [ ] Run `fizzy setup` (auth + config; the binary itself is packaged)
      - [ ] (Optional) Customize wallpaper in Noctalia — default ships in ~/Pictures/Wallpapers
      - [ ] Noctalia app themes (discord/obsidian/zed/steam/…) are community templates fetched from api.noctalia.dev at runtime — offline first-boot won't have them until the shell reaches the network. If they're missing, confirm connectivity and toggle the wallpaper (or restart Noctalia) to re-apply.
      - [ ] `sudo fwupdmgr update` for BIOS/EC firmware
      TODO
            fi
    '';
  };
}
