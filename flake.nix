{
  description = "Scott's Framework 13 AMD — NixOS + niri + Noctalia (encrypted, hibernate, secure-boot-ready)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Terminal workspace manager for AI coding agents (panes, sessions
    # that survive detach). Tag-pinned to keep client + server in lockstep;
    # bump by editing the `v0.7.x` in the URL below (plain `nix flake
    # update herdr` won't move a tag-pinned ref).
    herdr = {
      url = "github:ogulcancelik/herdr/v0.7.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── SECURE BOOT ────────────────────────────────────────────────
    # Uncomment to enable lanzaboote. Do this ONLY after the system is
    # installed and booting (see secure-boot.md). Enabling it before
    # enrolling keys will leave you unbootable if you flip Secure Boot on.
    # lanzaboote = {
    #   url = "github:nix-community/lanzaboote/v1.0.0";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      niri,
      noctalia,
      claude-code-nix,
      herdr,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;

      # Every directory under ./hosts is a machine. Drop in a new
      # hosts/<hostname>/ (a default.nix + its hardware-configuration.nix) and
      # it becomes nixosConfigurations.<hostname> automatically — no edit to
      # this file. scripts/new-host.sh scaffolds one; see hosts/README.md.
      hostNames = builtins.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );

      # Shared system definition. Only the per-host module (./hosts/<name>)
      # carries machine-specific state (hardware-configuration.nix, hostname,
      # the nixos-hardware model module, swap/resume UUIDs); configuration.nix
      # and home.nix are identical on every host.
      mkHost =
        hostname:
        lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${hostname}
            ./configuration.nix

            niri.nixosModules.niri

            # ── SECURE BOOT ──
            # Uncomment together with the input in the inputs block and the
            # block in configuration.nix:
            # inputs.lanzaboote.nixosModules.lanzaboote

            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.sroberts = import ./home.nix;
            }
          ];
        };
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkHost;

      # `nix fmt` formats all .nix files in the tree. pkgs.nixfmt is the RFC 166
      # implementation that ships in nixpkgs; running it has not yet been
      # applied to existing files, so expect a churn diff on first run.
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
    };
}
