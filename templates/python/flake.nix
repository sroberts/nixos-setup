{
  description = "Python dev shell (python3 + uv)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python3;
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              pkgs.uv
            ];

            # Point uv at the Nix-provided interpreter instead of letting it
            # download a python-build-standalone build: the shell's python is
            # then the one `uv venv` / `uv run` use, and the project stays
            # pinned by flake.lock rather than by whatever uv fetched.
            env = {
              UV_PYTHON = python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };
          };
        }
      );
    };
}
