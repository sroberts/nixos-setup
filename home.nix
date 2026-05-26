# User-level configuration: packages, shell, dotfiles, DMS.
{ inputs, pkgs, ... }:

{
  home.username = "sroberts";
  home.homeDirectory = "/home/sroberts";
  home.stateVersion = "26.05";

  ############################################################
  # DankMaterialShell + niri integration
  ############################################################
  imports = [
    inputs.dms.homeModules.dank-material-shell
    inputs.dms.homeModules.niri
  ];

  programs.dank-material-shell = {
    enable = true;
    enableSystemMonitoring = true;
    niri = {
      enableKeybinds = true;       # DMS preset binds (launcher, lock, power menu)
      enableSpawn = true;          # auto-start DMS with niri
      includes.enable = false;     # DMS warns if both enableKeybinds and includes.enable are on; enableKeybinds is the recommended path
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
    # niri upstream default keybinds, verbatim, with the terminal binary
    # swapped from alacritty to ghostty. DMS's enableKeybinds writes into
    # the same niri-flake bind option, so the upstream binds that DMS
    # already owns (Super+Alt+L lock, Mod+Comma settings, Mod+V clipboard,
    # XF86Audio* media) are omitted here — defining them again would be a
    # Nix eval error. Wrap a key in `lib.mkForce` to override DMS instead.
    binds = {
      # Help + spawn
      "Mod+Shift+Slash".action.show-hotkey-overlay = [];
      "Mod+T".action.spawn = "ghostty";
      "Mod+Return".action.spawn = "ghostty";
      "Mod+D".action.spawn = "fuzzel";

      # Window
      "Mod+Q".action.close-window = [];

      # Column focus (arrows + vim keys)
      "Mod+Left".action.focus-column-left = [];
      "Mod+Right".action.focus-column-right = [];
      "Mod+H".action.focus-column-left = [];
      "Mod+L".action.focus-column-right = [];

      # Window focus within column
      "Mod+Down".action.focus-window-down = [];
      "Mod+Up".action.focus-window-up = [];
      "Mod+J".action.focus-window-down = [];
      "Mod+K".action.focus-window-up = [];

      # Column / window move (Ctrl = move)
      "Mod+Ctrl+Left".action.move-column-left = [];
      "Mod+Ctrl+Right".action.move-column-right = [];
      "Mod+Ctrl+H".action.move-column-left = [];
      "Mod+Ctrl+L".action.move-column-right = [];
      "Mod+Ctrl+Down".action.move-window-down = [];
      "Mod+Ctrl+Up".action.move-window-up = [];
      "Mod+Ctrl+J".action.move-window-down = [];
      "Mod+Ctrl+K".action.move-window-up = [];

      # First / last column
      "Mod+Home".action.focus-column-first = [];
      "Mod+End".action.focus-column-last = [];
      "Mod+Ctrl+Home".action.move-column-to-first = [];
      "Mod+Ctrl+End".action.move-column-to-last = [];

      # Monitor focus (Shift = monitor)
      "Mod+Shift+Left".action.focus-monitor-left = [];
      "Mod+Shift+Right".action.focus-monitor-right = [];
      "Mod+Shift+Down".action.focus-monitor-down = [];
      "Mod+Shift+Up".action.focus-monitor-up = [];
      "Mod+Shift+H".action.focus-monitor-left = [];
      "Mod+Shift+L".action.focus-monitor-right = [];
      "Mod+Shift+J".action.focus-monitor-down = [];
      "Mod+Shift+K".action.focus-monitor-up = [];

      # Move column to monitor (Shift+Ctrl)
      "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [];
      "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [];
      "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [];
      "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [];
      "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = [];
      "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = [];
      "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = [];
      "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = [];

      # Workspace focus / move (Page keys + u/i)
      "Mod+Page_Down".action.focus-workspace-down = [];
      "Mod+Page_Up".action.focus-workspace-up = [];
      "Mod+U".action.focus-workspace-down = [];
      "Mod+I".action.focus-workspace-up = [];
      "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = [];
      "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = [];
      "Mod+Ctrl+U".action.move-column-to-workspace-down = [];
      "Mod+Ctrl+I".action.move-column-to-workspace-up = [];
      "Mod+Shift+Page_Down".action.move-workspace-down = [];
      "Mod+Shift+Page_Up".action.move-workspace-up = [];
      "Mod+Shift+U".action.move-workspace-down = [];
      "Mod+Shift+I".action.move-workspace-up = [];

      # Scroll wheel = workspaces / columns
      "Mod+WheelScrollDown" = {
        cooldown-ms = 150;
        action.focus-workspace-down = [];
      };
      "Mod+WheelScrollUp" = {
        cooldown-ms = 150;
        action.focus-workspace-up = [];
      };
      "Mod+Ctrl+WheelScrollDown" = {
        cooldown-ms = 150;
        action.move-column-to-workspace-down = [];
      };
      "Mod+Ctrl+WheelScrollUp" = {
        cooldown-ms = 150;
        action.move-column-to-workspace-up = [];
      };
      "Mod+WheelScrollRight".action.focus-column-right = [];
      "Mod+WheelScrollLeft".action.focus-column-left = [];
      "Mod+Ctrl+WheelScrollRight".action.move-column-right = [];
      "Mod+Ctrl+WheelScrollLeft".action.move-column-left = [];
      "Mod+Shift+WheelScrollDown".action.focus-column-right = [];
      "Mod+Shift+WheelScrollUp".action.focus-column-left = [];
      "Mod+Ctrl+Shift+WheelScrollDown".action.move-column-right = [];
      "Mod+Ctrl+Shift+WheelScrollUp".action.move-column-left = [];

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
      "Mod+Tab".action.focus-workspace-previous = [];

      # Consume / expel (Mod+Comma omitted — DMS owns it for the settings panel)
      "Mod+BracketLeft".action.consume-or-expel-window-left = [];
      "Mod+BracketRight".action.consume-or-expel-window-right = [];
      "Mod+Period".action.expel-window-from-column = [];

      # Sizing
      "Mod+R".action.switch-preset-column-width = [];
      "Mod+Shift+R".action.switch-preset-window-height = [];
      "Mod+Ctrl+R".action.reset-window-height = [];
      "Mod+F".action.maximize-column = [];
      "Mod+Shift+F".action.fullscreen-window = [];
      "Mod+Ctrl+F".action.expand-column-to-available-width = [];
      "Mod+C".action.center-column = [];
      "Mod+Ctrl+C".action.center-visible-columns = [];
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+Shift+Minus".action.set-window-height = "-10%";
      "Mod+Shift+Equal".action.set-window-height = "+10%";

      # Floating + tabbed display (Mod+V omitted — DMS owns it for clipboard)
      "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = [];
      "Mod+W".action.toggle-column-tabbed-display = [];

      # Screenshots
      "Print".action.screenshot = [];
      "Ctrl+Print".action.screenshot-screen = [];
      "Alt+Print".action.screenshot-window = [];

      # Session
      "Mod+Shift+E".action.quit = [];
      "Mod+Shift+P".action.power-off-monitors = [];
      "Mod+Ctrl+Shift+T".action.toggle-debug-tint = [];
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
    yara-x          # binary is `yr`
    gum
    crush           # charmbracelet/crush
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
    settings.user = {
      name = "Scott J Roberts";
      email = "scott.roberts@gmail.com";
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

  # DMS wallpaper, monochrome theme, imperial units. Downloads the wallpaper
  # if missing, jq-merges the four keys into DMS's settings.json (preserving
  # other runtime-written keys), then nudges a running DMS via `dms ipc` so
  # changes apply live without a log-out. "monochrome" is a built-in DMS
  # stock theme that drives matugen's scheme-monochrome algorithm —
  # grayscale UI regardless of wallpaper colors.
  home.activation.dmsWallpaperAndTheme = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      WALLPAPER="$HOME/Pictures/wallpapers/dms-default.jpg"
      SETTINGS_DIR="$HOME/.config/DankMaterialShell"
      SETTINGS="$SETTINGS_DIR/settings.json"
      URL="https://images.unsplash.com/photo-1533134486753-c833f0ed4866?q=80&w=2070&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"
      DMS_BIN="/etc/profiles/per-user/$USER/bin/dms"

      if [ ! -f "$WALLPAPER" ]; then
        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$WALLPAPER")"
        ${pkgs.curl}/bin/curl -fsSL -o "$WALLPAPER" "$URL"
      fi

      ${pkgs.coreutils}/bin/mkdir -p "$SETTINGS_DIR"
      TMP=$(${pkgs.coreutils}/bin/mktemp)
      MERGE='. + {wallpaperPath: $wp, currentThemeName: "monochrome", useFahrenheit: true, windSpeedUnit: "mph"}'
      if [ -f "$SETTINGS" ]; then
        ${pkgs.jq}/bin/jq --arg wp "$WALLPAPER" "$MERGE" "$SETTINGS" > "$TMP" \
          && ${pkgs.coreutils}/bin/mv "$TMP" "$SETTINGS"
      else
        ${pkgs.jq}/bin/jq -n --arg wp "$WALLPAPER" "$MERGE" > "$SETTINGS"
        ${pkgs.coreutils}/bin/rm -f "$TMP"
      fi

      # Best-effort: push changes to a running DMS via IPC so they apply
      # without log-out. Silently no-op on fresh installs where DMS isn't
      # running yet — settings.json will be picked up on its next startup.
      if [ -x "$DMS_BIN" ]; then
        "$DMS_BIN" ipc wallpaper set "$WALLPAPER" > /dev/null 2>&1 || true
        "$DMS_BIN" ipc settings set currentThemeName monochrome > /dev/null 2>&1 || true
        "$DMS_BIN" ipc settings set useFahrenheit true > /dev/null 2>&1 || true
        "$DMS_BIN" ipc settings set windSpeedUnit mph > /dev/null 2>&1 || true
      fi
    '';
  };

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
- [ ] Set up Obsidian Sync + enable Iconize community plugin
- [ ] Register Typora license
- [ ] Chromium extensions: 1Password, Obsidian Web Clipper, Instapaper
- [ ] Sign in to Slack, Discord, Signal, Zoom
- [ ] Download Playdate Simulator: https://play.date/dev/
- [ ] Pull Ollama models: `ollama pull llama3.2`
- [ ] Install pipx + tools: `pip install --user pipx && pipx ensurepath && pipx install q-text-as-data jsongrep`
- [ ] Install JFryy/qq: `go install github.com/JFryy/qq@latest`
- [ ] Authenticate Claude Code: run `claude`
- [ ] Authenticate Gemini CLI: `gemini auth`
- [ ] Verify `dms doctor -v` reports green
- [ ] `sudo fwupdmgr update` for BIOS/EC firmware
TODO
      fi
    '';
  };
}
