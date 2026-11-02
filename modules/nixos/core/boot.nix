{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  theme = import ../../themes/${config.systemSettings.theme};

  # Читаем boot-note: сначала локальный для хоста, затем общий из корня репо
  hostNoteFile = ../../../hosts/${config.networking.hostName}/boot-note;
  rootNoteFile = ../../../boot-note;
  rawNote =
    if builtins.pathExists hostNoteFile then
      builtins.readFile hostNoteFile
    else if builtins.pathExists rootNoteFile then
      builtins.readFile rootNoteFile
    else
      "system update";
  bootNote =
    let
      trimmed = lib.strings.trim rawNote;
    in
    if trimmed != "" then trimmed else "system update";
in
{
  ############################################################
  # Boot Loader — Limine (современный графический UEFI загрузчик)
  ############################################################

  # Сохраняем заметку в текущее поколение, чтобы старые поколения помнили свое описание
  environment.etc."boot-note".text = bootNote + "\n";

  # Отключаем systemd-boot в пользу Limine
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.loader.limine = {
    enable = lib.mkDefault true;
    maxGenerations = 3; # автоматическая ротация старых ядер на ESP
    enableEditor = false; # безопасность: запрет ручного ввода init=/bin/sh

    style = theme.limine;

    # Пост-обработка limine.conf: форматирует заголовки (Generation N (DD.MM HH:MM))
    # и подставляет человеческую заметку из /etc/boot-note в comment: каждого поколения.
    extraInstallCommands = "${pkgs.callPackage ../../packages/limine-enrich { }}/bin/limine-enrich";
  };

  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.loader.timeout = lib.mkDefault 2;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Plymouth boot splash screen (Everforest Warm Minimal Theme)
  boot.plymouth = {
    enable = true;
    theme = theme.plymouth.themeName;
    themePackages = [
      (pkgs.callPackage ../../packages/plymouth-theme-everforest {
        bgColor = theme.plymouth.bgColor;
        surfaceColor = theme.plymouth.surfaceColor;
        fgColor = theme.plymouth.fgColor;
        accentColor = theme.plymouth.accentColor;
      })
    ];
    font = "${pkgs.nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFont-Regular.ttf";
  };
  boot.initrd.verbose = false;
  boot.consoleLogLevel = 0;
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];
}
