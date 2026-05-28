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
      nixos-hardware,
      niri,
      noctalia,
      claude-code-nix,
      ...
    }@inputs:
    {
      nixosConfigurations.sjr-fw13 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix

          # Framework 13 AMD Ryzen 7040. Swap for framework-amd-ai-300-series
          # if you have a Ryzen AI 300.
          nixos-hardware.nixosModules.framework-13-7040-amd

          niri.nixosModules.niri

          # ── SECURE BOOT ──
          # Uncomment together with the input above and the block in
          # configuration.nix:
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

      # `nix fmt` formats all .nix files in the tree. nixfmt-rfc-style is the
      # RFC 166 implementation that ships in nixpkgs; running it has not yet
      # been applied to existing files, so expect a churn diff on first run.
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
    };
}
