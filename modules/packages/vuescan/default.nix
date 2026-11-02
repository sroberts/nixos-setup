{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
  gtk3,
  glib,
  gdk-pixbuf,
  pango,
  cairo,
  libpng,
  libxkbcommon,
  util-linux,
  libx11,
  systemd,
  zlib,
  desktop-file-utils,
  coreutils,
  gtkTheme ? null,
}:

stdenv.mkDerivation rec {
  pname = "vuescan";
  version = "9.8.55";

  src = fetchurl (
    if stdenv.hostPlatform.isAarch64 then
      {
        url = "https://files.hamrick.com/version-archive/${version}/vuea6498.tgz";
        hash = "sha256-3raQs499/6AIx69UzYe8RNp5/Pfy6qHBDaKSn3ONwgo=";
      }
    else
      {
        url = "https://files.hamrick.com/version-archive/${version}/vuex6498.tgz";
        hash = "sha256-Q9oWI7m4KpQbOSMiRoYUeYogEOxbfFyOtlkEzzUv6UQ=";
      }
  );

  sourceRoot = "VueScan";
  # VueScan appends an internal resource archive (vuescan.dat, ~40MB) to the end
  # of the ELF binary. Standard strip removes it, causing an immediate null pointer dereference.
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    copyDesktopItems
  ];

  buildInputs = [
    gtk3
    glib
    gdk-pixbuf
    pango
    cairo
    libpng
    libxkbcommon
    util-linux
    libx11
    systemd
    zlib
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 vuescan $out/bin/vuescan
    install -Dm644 vuescan.svg $out/share/icons/hicolor/scalable/apps/vuescan.svg
    install -Dm644 vuescan.rul $out/lib/udev/rules.d/60-vuescan.rules

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          desktop-file-utils
          coreutils
        ]
      }
      ${lib.optionalString (gtkTheme != null) ''--set-default GTK_THEME "${gtkTheme}"''}
    )
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "vuescan";
      exec = "vuescan";
      icon = "vuescan";
      desktopName = "VueScan";
      genericName = "Scanning Software";
      comment = "Scan documents, photos, and film";
      categories = [
        "Graphics"
        "Scanning"
      ];
      startupNotify = true;
    })
  ];

  meta = with lib; {
    description = "Scanner software for photos, documents, and film";
    homepage = "https://www.hamrick.com/";
    license = licenses.unfree;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "vuescan";
  };
}
