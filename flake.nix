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
      # DELIBERATELY no `inputs.nixpkgs.follows = "nixpkgs"`, unlike every
      # other input here. Two reasons, in order of weight:
      #
      # 1. Upstream guidance. Noctalia's own NixOS docs
      #    (docs.noctalia.dev/noctalia/getting-started/nixos) describe the
      #    follows line as optional — "prevents downloading two versions of
      #    nixpkgs but disables cache". So following is the thing that costs
      #    you the binary cache; not following is the expected default.
      #
      # 2. It is currently load-bearing. niri-flake asks for
      #    `libdisplay-info_0_2`, which nixpkgs has removed (the attr is now a
      #    throw stub pointing at _0_3). Forcing niri onto our nixpkgs makes
      #    evaluation fail outright on programs.niri.package. Upstream
      #    niri-flake hasn't moved since 2026-08-04 — its main HEAD is the
      #    commit we pin — so there is nothing to bump to. Its own pin
      #    predates the removal, so letting it use that is what unblocks
      #    nixpkgs updates.
      #
      # Cost: a second nixpkgs in the closure; niri links a different
      # mesa/wayland than the rest of the system. Accepted, and it buys cache
      # hits for niri instead of source builds.
      #
      # Note we can't simply drop niri-flake for nixpkgs' `niri`: nixpkgs ships
      # the package (26.04, older than the unstable build we run) but NO
      # programs.niri module, and home.nix's binds/outputs/touchpad are all
      # written as `programs.niri.settings` with build-time validation.
    };

    noctalia = {
      # Pinned to the v5.0.0 beta tag (major bump from the v4 line). Beta: expect
      # schema/module changes vs 4.x — re-verify programs.noctalia options
      # and the seeded settings.json after bumping. Move to the stable v5.0.0 tag
      # once it ships.
      url = "github:noctalia-dev/noctalia-shell/v5.0.0-beta2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # noctalia-greeter — greetd greeter that mirrors Noctalia Shell's look.
    # Tracks main (no tagged releases yet). Bump with `nix flake update
    # noctalia-greeter`.
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
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

  # Only the inputs referenced directly in this file are destructured; the rest
  # (noctalia, claude-code-nix, herdr, …) are reached as `inputs.<name>` from
  # configuration.nix / home.nix via specialArgs + extraSpecialArgs below.
  outputs =
    {
      nixpkgs,
      home-manager,
      niri,
      noctalia-greeter,
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
            noctalia-greeter.nixosModules.default

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
      # implementation that ships in nixpkgs. The tree is already nixfmt-clean
      # and CI enforces it (`nix fmt --check` in .github/workflows/check.yml),
      # so running this is a no-op unless you introduced drift.
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
    };
}
