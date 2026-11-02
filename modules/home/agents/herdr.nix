# ogulcancelik/herdr — terminal workspace manager for AI coding agents.
{
  inputs,
  pkgs,
  ...
}:
{
  home.packages =
    let
      pkg = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default or null;
    in
    pkgs.lib.optional (pkg != null) pkg;
}
