{
  lib,
  stdenv,
  pkgs,
  python3,
  openssl,
  coreutils,
  wl-clipboard,
  pulseaudio,
  systemd,
  makeWrapper,
  symlinkJoin,
  kitty,
}:

stdenv.mkDerivation {
  pname = "mac-guest-tools";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin

    install -D -m 0755 native-authentication-broker $out/bin/native-authentication-broker
    wrapProgram $out/bin/native-authentication-broker \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          openssl
          coreutils
        ]
      }

    install -D -m 0755 mac-touch-id $out/bin/mac-touch-id
    substituteInPlace $out/bin/mac-touch-id \
      --replace-fail "@broker@" "$out"
    ln -s mac-touch-id $out/bin/try-omarchy-touch-id

    install -D -m 0755 omarchy-native-battery-bridge $out/bin/omarchy-native-battery-bridge
    wrapProgram $out/bin/omarchy-native-battery-bridge \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}

    install -D -m 0755 omarchy-native-clipboard-bridge $out/bin/omarchy-native-clipboard-bridge
    wrapProgram $out/bin/omarchy-native-clipboard-bridge \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          wl-clipboard
          coreutils
        ]
      }

    install -D -m 0755 omarchy-native-audio-bridge $out/bin/omarchy-native-audio-bridge
    wrapProgram $out/bin/omarchy-native-audio-bridge \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          pulseaudio
          coreutils
        ]
      }

    install -D -m 0755 omarchy-native-timezone-bridge $out/bin/omarchy-native-timezone-bridge
    wrapProgram $out/bin/omarchy-native-timezone-bridge \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          systemd
          coreutils
        ]
      }

    install -D -m 0755 omarchy-native-camera-bridge $out/bin/omarchy-native-camera-bridge
    wrapProgram $out/bin/omarchy-native-camera-bridge \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}

    install -D -m 0755 mac-guest-status $out/bin/mac-guest-status
    wrapProgram $out/bin/mac-guest-status \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}
  '';

  passthru.kittyWrapped = symlinkJoin {
    name = "kitty-virgl-${pkgs.kitty.version}";
    paths = [ pkgs.kitty ];
    postBuild = ''
            rm -f $out/bin/kitty
            cat << 'EOF' > $out/bin/kitty
      #!/bin/sh
      realKitty="${pkgs.kitty}/bin/kitty"
      if ls /sys/bus/virtio/drivers/virtio_gpu/virtio* >/dev/null 2>&1; then
        export LIBGL_ALWAYS_SOFTWARE=1
        case "$1" in
          +*|@*)
            exec "$realKitty" "$@"
            ;;
          *)
            exec "$realKitty" -o env=LIBGL_ALWAYS_SOFTWARE "$@"
            ;;
        esac
      fi
      exec "$realKitty" "$@"
      EOF
            chmod +x $out/bin/kitty
    '';
  };

  meta = with lib; {
    description = "Guest integration tools and daemons for macOS host in QEMU VirtIO";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
