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

  programs.noctalia-shell = {
    enable = true;
    # systemd.enable is upstream-deprecated — Noctalia is intended to be
    # spawned by the compositor (see spawn-at-startup below). Leaving it off.
  };

  # niri input — natural scrolling, tap-to-click, disable-while-typing.
  # Schema is validated at build time by niri-flake.
  programs.niri.settings = {
    input.touchpad = {
      tap = true;
      natural-scroll = true;
      dwt = true;
    };
    # Auto-start Noctalia with niri. Noctalia's home-module writes the
    # config files; the compositor is responsible for launching the
    # process. `noctalia-shell` is on PATH via programs.noctalia-shell.
    spawn-at-startup = [
      { command = [ "noctalia-shell" ]; }
    ];
    # niri upstream default keybinds, verbatim, with the terminal binary
    # swapped from alacritty to ghostty. The session/media/lock/brightness
    # binds at the bottom of this block were previously owned by DMS's
    # `enableKeybinds`; with Noctalia in charge of the shell UI we wire
    # them directly to the underlying utilities (wpctl, playerctl,
    # brightnessctl, loginctl). Noctalia's own panels are driven over its
    # IPC surface (`noctalia-shell ipc call <target> <fn>`); Mod+Space
    # toggles the launcher below. Add settings/clipboard/etc. the same way —
    # `noctalia-shell ipc show` lists every target and function.
    binds = {
      # Help + spawn
      "Mod+Shift+Slash".action.show-hotkey-overlay = [ ];
      "Mod+T".action.spawn = "ghostty";
      "Mod+Return".action.spawn = "ghostty";
      # App launcher — Noctalia's, toggled over IPC.
      "Mod+Space".action.spawn = [
        "noctalia-shell"
        "ipc"
        "call"
        "launcher"
        "toggle"
      ];
      "Mod+D".action.spawn = "fuzzel";

      # Window
      "Mod+Q".action.close-window = [ ];

      # Column focus (arrows + vim keys)
      "Mod+Left".action.focus-column-left = [ ];
      "Mod+Right".action.focus-column-right = [ ];
      "Mod+H".action.focus-column-left = [ ];
      "Mod+L".action.focus-column-right = [ ];

      # Window focus within column
      "Mod+Down".action.focus-window-down = [ ];
      "Mod+Up".action.focus-window-up = [ ];
      "Mod+J".action.focus-window-down = [ ];
      "Mod+K".action.focus-window-up = [ ];

      # Column / window move (Ctrl = move)
      "Mod+Ctrl+Left".action.move-column-left = [ ];
      "Mod+Ctrl+Right".action.move-column-right = [ ];
      "Mod+Ctrl+H".action.move-column-left = [ ];
      "Mod+Ctrl+L".action.move-column-right = [ ];
      "Mod+Ctrl+Down".action.move-window-down = [ ];
      "Mod+Ctrl+Up".action.move-window-up = [ ];
      "Mod+Ctrl+J".action.move-window-down = [ ];
      "Mod+Ctrl+K".action.move-window-up = [ ];

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
        "noctalia-shell"
        "ipc"
        "call"
        "lockScreen"
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
  # configured in its settings.json (seeded in home.activation.noctaliaConfigSeed):
  #
  #   - LOCK (5 min):  idle.lockTimeout = 300. Locks via WlSessionLock — the
  #     ONLY path that works, since Noctalia ignores logind's Lock signal, so
  #     `loginctl lock-session` is a no-op here.
  #   - SUSPEND-THEN-HIBERNATE (15 min): an idle.customCommands entry running
  #     `systemctl suspend-then-hibernate`. (Noctalia's built-in idle-suspend
  #     does a plain `systemctl suspend`, so we use a custom command and leave
  #     idle.suspendTimeout = 0.) Suspends to RAM, then hibernates after
  #     HibernateDelaySec (3h, configuration.nix) — hibernate at 3h 15m total.
  #
  # swayidle is kept for the ONE thing a Noctalia idle command can't do: lock
  # before a sleep Noctalia didn't initiate — namely a lid close (logind's
  # HandleLidSwitch). Its before-sleep hook holds a logind sleep inhibitor and
  # raises Noctalia's lock via IPC ahead of ANY suspend/hibernate, so the
  # screen is never left unlocked on resume. No timeouts here — they live in
  # Noctalia.
  #
  # The before-sleep command resolves noctalia-shell by absolute store path:
  # swayidle.service runs under user@.service's app.slice with a minimal PATH
  # that does NOT inherit the niri/login-shell PATH where `programs.noctalia-
  # shell` puts the binary. Bare `noctalia-shell` would fail with `command not
  # found`, which is exactly what lid close did before this fix.
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = "${config.programs.noctalia-shell.package}/bin/noctalia-shell ipc call lockScreen lock";
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
    lazygit
    lazydocker
    btop
    fastfetch
    jq
    fd
    mosh
    # q-text-as-data is packaged in nixpkgs, so we pull it in here instead of
    # via pipx. JFryy/qq is built from source in the `let` above.
    q-text-as-data
    qq
    # pipx itself is still NOT installed via Nix: build-time deps in current
    # nixos-unstable (black, black[extras], nox) cycle through transient
    # failures. Install pipx + jsongrep (not in nixpkgs) manually post-boot
    # (mise provides python):
    #   pip install --user pipx
    #   pipx ensurepath
    #   pipx install jsongrep

    # Wayland / niri ergonomics
    wl-clipboard
    brightnessctl
    playerctl
    alacritty
    foot
    ghostty
    fuzzel
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
    # line and add `claude-code` to this list instead.
    inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    gemini-cli
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
    initExtra = ''
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

  # starship — Noctalia-mono palette + module styles. The palette names
  # below (bg/fg/dim/faint/accent/bright/border) match the nvim/zellij
  # palettes so all themed surfaces use the same color vocabulary.
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      palette = "noctalia-mono";
      palettes.noctalia-mono = {
        bg = "#111111";
        fg = "#aaaaaa";
        dim = "#828282";
        faint = "#5d5d5d";
        accent = "#cccccc";
        bright = "#dddddd";
        border = "#3c3c3c";
      };
      character = {
        success_symbol = "[➜](bold accent)";
        error_symbol = "[➜](bold bright)";
      };
      directory.style = "fg bold";
      git_branch.style = "dim";
      git_status.style = "accent";
      cmd_duration.style = "faint";
      hostname.style = "dim";
      # username uses style_user/style_root (not `style` like the others).
      username.style_user = "dim";
      username.style_root = "bright bold";
    };
  };

  # ghostty — primary terminal (see niri binds + home.sessionVariables.TERMINAL).
  # Stays in home.packages above per [[feedback-nixos-programs-module-install]]:
  # don't trust the programs.X module to install on its own until rebuild +
  # `which ghostty` confirms. The mono ANSI palette is a deliberate choice —
  # matches zellij/nvim aesthetics. Colored programs (git status, ls --color)
  # will surface differences via brightness/bold rather than hue.
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "noctalia-mono";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
    };
    themes.noctalia-mono = {
      background = "#111111";
      foreground = "#aaaaaa";
      cursor-color = "#cccccc";
      cursor-text = "#111111";
      selection-background = "#3c3c3c";
      selection-foreground = "#cccccc";
      palette = [
        "0=#111111"
        "1=#dddddd"
        "2=#aaaaaa"
        "3=#cccccc"
        "4=#a7a7a7"
        "5=#828282"
        "6=#cccccc"
        "7=#cccccc"
        "8=#3c3c3c"
        "9=#dddddd"
        "10=#aaaaaa"
        "11=#cccccc"
        "12=#a7a7a7"
        "13=#828282"
        "14=#cccccc"
        "15=#dddddd"
      ];
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
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    globalConfig.tools = {
      python = "latest";
      node = "lts";
      go = "latest";
    };
  };

  # GTK theming. adw-gtk3-dark is a libadwaita-style GTK3 port — it's
  # exactly what Noctalia's gtk-refresh.py expects to switch to (script
  # hardcodes "adw-gtk3" / "adw-gtk3-dark" as the target via gsettings).
  # The Noctalia template writes ~/.config/gtk-{3,4}.0/noctalia.css on each
  # wallpaper change; the @import in our managed gtk.css pulls those
  # @define-color overrides into every GTK app without us touching gtk.css
  # ourselves. enableUserTheming stays off — we use only the built-in gtk
  # template, which is enabled per activeTemplates in noctaliaConfigSeed.
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

  # Default wallpaper. Copies the tracked asset (assets/default-wallpaper.jpg)
  # into the Noctalia-configured wallpaper directory and seeds the wallpaper
  # cache so it's the active wallpaper on first boot (and the source palette
  # matugen feeds into noctalia.css → GTK). Idempotent: skips the copy if
  # the file already exists and only seeds the cache if Noctalia hasn't
  # already written one. Once Noctalia picks something else via its UI it
  # rewrites the cache and ownership transfers cleanly. The asset lives in
  # the repo so a fresh install never depends on a third-party URL.
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

      CACHE="$HOME/.cache/noctalia"
      ${pkgs.coreutils}/bin/mkdir -p "$CACHE"
      if [ ! -f "$CACHE/wallpapers.json" ] && [ -f "$DEST" ]; then
        ${pkgs.coreutils}/bin/cat > "$CACHE/wallpapers.json" <<JSON
      {
        "wallpapers": {},
        "defaultWallpaper": "$DEST",
        "usedRandomWallpapers": {}
      }
      JSON
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

  # Seed Noctalia's config files on first run.
  #
  # Why settings.json: Noctalia opens a modal SetupWizard whenever this
  # file is missing (Commons/Settings.qml: `shouldOpenSetupWizard = true`
  # on ENOENT). The wizard hides the bar until dismissed — on an
  # unattended fresh boot the user sees a bare wallpaper and assumes the
  # shell didn't start. A stub is enough to skip it; Noctalia fills in
  # defaults and runs all migrations on next load. We seed the default weather
  # location (Greenville, SC, °F) and Noctalia's idle escalation: a 5-min lock
  # plus a custom command for suspend-then-hibernate at 15 min (see the
  # services.swayidle comment for why the hibernate is a custom command and
  # what swayidle is still doing). Noctalia merges the rest and owns the file
  # thereafter (it hot-reloads external edits via a watched FileView, so this
  # only ever applies on a fresh $HOME).
  #
  # Why plugins.json: mirrors CachyOS's curated default, enabling the
  # official Noctalia plugin source plus `polkit-agent`. The matching
  # disable for niri-flake's polkit-kde-agent lives in configuration.nix
  # — both would otherwise race on the PolicyKit1 bus name.
  #
  # Why home.activation and not xdg.configFile / programs.noctalia-shell:
  # Noctalia writes these files at runtime (settings UI, plugin toggles),
  # and a store-path symlink would silently break those writes. Seeding
  # once + handing ownership to Noctalia keeps the UI functional.
  home.activation.noctaliaConfigSeed = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      CFG="$HOME/.config/noctalia"
      ${pkgs.coreutils}/bin/mkdir -p "$CFG"

      if [ ! -e "$CFG/settings.json" ]; then
        ${pkgs.coreutils}/bin/cat > "$CFG/settings.json" <<'SETTINGS'
      {
        "location": {
          "name": "Greenville, SC",
          "useFahrenheit": true
        },
        "idle": {
          "enabled": true,
          "lockTimeout": 300,
          "suspendTimeout": 0,
          "customCommands": "[{\"timeout\":900,\"command\":\"systemctl suspend-then-hibernate\"}]"
        },
        "general": {
          "allowPasswordWithFprintd": true,
          "autoStartAuth": true
        },
        "templates": {
          "activeTemplates": [
            { "id": "gtk", "enabled": true }
          ]
        }
      }
      SETTINGS
      fi

      # Lock-screen fingerprint-or-password fix. Noctalia auto-detects its
      # PAM service as /etc/pam.d/login (LockContext.qml:22), which we've
      # enabled fprintAuth on for TTY login (configuration.nix). Two flags
      # are needed to make both unlock paths work:
      #
      # autoStartAuth=true: LockContext only calls pam.start() automatically
      # when this is set (LockContext.qml:60-62). Without it, PAM is dormant
      # until Enter is pressed via tryUnlock(), so pam_fprintd is never
      # listening for the sensor — touching the reader does nothing. With it
      # on, PAM runs at lock time, pam_fprintd (first "sufficient" rule in
      # /etc/pam.d/login) waits for a finger, and a single touch unlocks.
      #
      # allowPasswordWithFprintd=true: handles the "user types instead of
      # touching the sensor" path. On first keypress, LockContext aborts
      # PAM and spawns fprintd-verify to occupy the sensor; the next
      # pam.start() (on Enter) finds pam_fprintd blocked from claiming
      # the device, falls through to pam_unix, and the password path
      # runs alone. Without this flag, pam_fprintd would still race for
      # the sensor and the unlock UX becomes "password THEN fingerprint".
      #
      # Asserted every activation because Noctalia owns this file after
      # the initial seed.
      if [ -e "$CFG/settings.json" ]; then
        TMP=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.jq}/bin/jq '
          .general.allowPasswordWithFprintd = true |
          .general.autoStartAuth = true
        ' "$CFG/settings.json" > "$TMP" \
          && ${pkgs.coreutils}/bin/mv "$TMP" "$CFG/settings.json"
      fi

      # Ensure Noctalia's `gtk` template is active so wallpaper changes
      # regenerate ~/.config/gtk-{3,4}.0/noctalia.css. The managed gtk.css
      # in our gtk module @imports that file, so this is what wires
      # matugen output through to every GTK app on the system. Idempotent:
      # set if missing, force enabled=true if present, no duplicates.
      if [ -e "$CFG/settings.json" ]; then
        TMP=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.jq}/bin/jq '
          .templates = (.templates // {}) |
          .templates.activeTemplates = (
            (.templates.activeTemplates // [])
            | map(select(.id != "gtk"))
            | . + [{"id": "gtk", "enabled": true}]
          )
        ' "$CFG/settings.json" > "$TMP" \
          && ${pkgs.coreutils}/bin/mv "$TMP" "$CFG/settings.json"
      fi

      if [ ! -e "$CFG/plugins.json" ]; then
        ${pkgs.coreutils}/bin/cat > "$CFG/plugins.json" <<'PLUGINS'
      {
        "sources": [
          {
            "enabled": true,
            "name": "Noctalia Plugins",
            "url": "https://github.com/noctalia-dev/noctalia-plugins"
          }
        ],
        "states": {
          "polkit-agent": {
            "enabled": true,
            "sourceUrl": "https://github.com/noctalia-dev/noctalia-plugins"
          }
        },
        "version": 2
      }
      PLUGINS
      fi
    '';
  };

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
      - [ ] Install pipx + jsongrep: `pip install --user pipx && pipx ensurepath && pipx install jsongrep`
      - [ ] Authenticate Claude Code: run `claude`
      - [ ] Authenticate Gemini CLI: `gemini auth`
      - [ ] (Optional) Customize wallpaper in Noctalia — default ships in ~/Pictures/Wallpapers
      - [ ] `sudo fwupdmgr update` for BIOS/EC firmware
      TODO
            fi
    '';
  };
}
