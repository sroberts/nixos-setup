{
  lib,
  stdenv,
  kernel,
}:

stdenv.mkDerivation {
  pname = "try-omarchy-battery";
  version = "1.3.0";
  src = ./.;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [
    "pic"
    "format"
  ];

  buildPhase = ''
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules
  '';

  installPhase = ''
    install -D -m 0644 try-omarchy-battery.ko $out/lib/modules/${kernel.modDirVersion}/extra/try-omarchy-battery.ko
  '';

  meta = with lib; {
    description = "Mirror host Mac battery into guest as BAT0/ADP0";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
