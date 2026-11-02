# NegPy — Tool for processing film negatives with film-physics simulation
# and direct support for Pacific Image Electronics / Reflecta film scanners.
{
  inputs,
  pkgs,
  ...
}:
let
  negpyRaw = inputs.negpy.packages.${pkgs.stdenv.hostPlatform.system}.default or null;

  gsettingsSchemas = [
    "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
    "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
  ];

  negpy =
    if negpyRaw != null then
      pkgs.symlinkJoin {
        name = "negpy-${negpyRaw.version}";
        paths = [ negpyRaw ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/negpy \
            --prefix XDG_DATA_DIRS : "${pkgs.lib.concatStringsSep ":" gsettingsSchemas}"

          rm -f $out/share/applications/NegPy.desktop
          substitute ${negpyRaw}/share/applications/NegPy.desktop $out/share/applications/NegPy.desktop \
            --replace-fail "${negpyRaw}/bin/negpy" "$out/bin/negpy"
        '';
      }
    else
      null;
in
{
  home.packages = pkgs.lib.optional (negpy != null) negpy;
}
