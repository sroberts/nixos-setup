# User-level configuration: packages, shell, dotfiles, Noctalia.
{ inputs, pkgs, ... }:

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
      "Mod+Ctrl+1".action.move-column-to-workspace = 1;
      "Mod+Ctrl+2".action.move-column-to-workspace = 2;
      "Mod+Ctrl+3".action.move-column-to-workspace = 3;
      "Mod+Ctrl+4".action.move-column-to-workspace = 4;
      "Mod+Ctrl+5".action.move-column-to-workspace = 5;
      "Mod+Ctrl+6".action.move-column-to-workspace = 6;
      "Mod+Ctrl+7".action.move-column-to-workspace = 7;
      "Mod+Ctrl+8".action.move-column-to-workspace = 8;
      "Mod+Ctrl+9".action.move-column-to-workspace = 9;

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
  #     HibernateDelaySec (5 min, configuration.nix) — hibernate at 20 min total.
  #
  # swayidle is kept for the ONE thing a Noctalia idle command can't do: lock
  # before a sleep Noctalia didn't initiate — namely a lid close (logind's
  # HandleLidSwitch). Its before-sleep hook holds a logind sleep inhibitor and
  # raises Noctalia's lock via IPC ahead of ANY suspend/hibernate, so the
  # screen is never left unlocked on resume. No timeouts here — they live in
  # Noctalia.
  services.swayidle = {
    enable = true;
    events = {
      before-sleep = "noctalia-shell ipc call lockScreen lock";
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
    # pipx is intentionally NOT installed via Nix: its build-time deps in
    # current nixos-unstable (black, black[extras], nox) cycle through
    # transient failures. Install pipx + the two tools we want manually
    # post-boot (mise provides python):
    #   pip install --user pipx
    #   pipx ensurepath
    #   pipx install q-text-as-data jsongrep
    # JFryy/qq also isn't in nixpkgs; `go install github.com/JFryy/qq@latest`
    # picks it up via mise's Go toolchain.

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

  programs.bat.enable = true;
  programs.starship.enable = true;

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

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Scott J Roberts";
        email = "scott.roberts@gmail.com";
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

  # pipx + its tools are installed manually post-boot — see the comment in
  # home.packages above. The previous home.activation.pipxTools hook was
  # removed because pipx itself currently fails to build in nixos-unstable
  # (test-time deps black/black[extras]/nox flap).

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

  # Wallpaper + theme are intentionally not auto-provisioned anymore.
  # Set them once in Noctalia's UI on first run; matugen-derived theming
  # follows from Noctalia's wallpaper-driven palette.

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
        }
      }
      SETTINGS
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
      - [ ] Chromium extensions: 1Password, Obsidian Web Clipper, Instapaper
      - [ ] Sign in to Slack, Discord, Signal, Zoom
      - [ ] Download Playdate Simulator: https://play.date/dev/
      - [ ] Pull Ollama models: `ollama pull llama3.2`
      - [ ] Install pipx + tools: `pip install --user pipx && pipx ensurepath && pipx install q-text-as-data jsongrep`
      - [ ] Install JFryy/qq: `go install github.com/JFryy/qq@latest`
      - [ ] Authenticate Claude Code: run `claude`
      - [ ] Authenticate Gemini CLI: `gemini auth`
      - [ ] Set wallpaper in Noctalia (right-click bar → Settings → Wallpaper)
      - [ ] `sudo fwupdmgr update` for BIOS/EC firmware
      TODO
            fi
    '';
  };
}
