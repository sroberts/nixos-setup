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
    binds = {
      "Mod+Return".action.spawn = "ghostty";
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
- [ ] Set wallpaper (DMS derives the Material You theme from it)
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
