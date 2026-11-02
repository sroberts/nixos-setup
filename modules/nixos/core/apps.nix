{
  config,
  lib,
  pkgs,
  ...
}:
let
  vuescan = pkgs.callPackage ../../packages/vuescan { };
in
{
  ############################################################
  # System-wide GUI applications
  ############################################################
  environment.systemPackages = with pkgs; [
    vscode
    nemo-with-extensions
    nemo-preview
    file-roller
    bulky
    p7zip
    zip
    ffmpegthumbnailer
    webp-pixbuf-loader
    evince
    gnome-epub-thumbnailer
    obsidian
    git
    curl
    wget
    unzip
    cryptsetup # handy for inspecting/managing the LUKS volume post-install
    google-chrome
    typora
  ];

  # Udev rules for USB scanner access (VueScan)
  services.udev.packages = [ vuescan ];
}
