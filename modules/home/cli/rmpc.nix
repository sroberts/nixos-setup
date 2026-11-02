{
  config,
  pkgs,
  inputs,
  ...
}:
{
  home.packages = [
    pkgs.cava
    pkgs.yt-dlp
  ];

  programs.rmpc = {
    enable = true;
    # Master build from the flake input (custom_loader support; see flake.nix).
    package = inputs.rmpc.packages.${pkgs.stdenv.hostPlatform.system}.rmpc or pkgs.rmpc;
    config = builtins.readFile ../../data/rmpc/config.ron;
  };

  xdg.configFile."rmpc/themes/everforest-warm.ron".source = ../../data/rmpc/theme.ron;
  xdg.configFile."rmpc/scripts/radio_cover_loader" = {
    source = ../../data/rmpc/radio_cover_loader;
    executable = true;
  };

  home.file.".local/share/rmpc/covers" = {
    source = ../../data/radio/covers;
    recursive = true;
  };

  xdg.desktopEntries.rmpc = {
    name = "rmpc";
    genericName = "Rusty Music Player Client";
    exec = "rmpc";
    terminal = true;
    icon = "multimedia-audio-player";
    categories = [
      "AudioVideo"
      "Audio"
      "Player"
      "Music"
      "ConsoleOnly"
    ];
  };
}
