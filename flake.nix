{
  description = "Scott's Framework 13 AMD — NixOS + niri + Noctalia (encrypted, hibernate, secure-boot-ready)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # niri — compositor packages + NixOS/home-manager modules.
    #
    # This is niri-nix, NOT sodiboo/niri-flake. The swap happened because
    # niri-flake's main has not moved since 2026-08-04 and cost us real
    # breakage twice: it pins `libdisplay-info_0_2`, which nixpkgs removed, so
    # it cannot follow our nixpkgs at all; and not following meant niri linked
    # a different glibc from the system mesa it dlopens, which black-screened
    # login after a nixpkgs bump. The standing fix for that — rebuilding niri
    # from nixpkgs' recipe with niri-flake's source — is no longer needed.
    #
    # niri-nix builds against `libdisplay-info_0_3`, so it follows our nixpkgs
    # cleanly: one nixpkgs in the closure, and niri/mesa/glibc stay in lockstep
    # by construction rather than by workaround. It also tracks niri daily
    # (source 2026-10-26 vs niri-flake's 2026-08-02), which picks up upstream's
    # removal of the deprecated `systemctl --user import-environment` call.
    #
    # Trade-off: following nixpkgs forfeits niri-nix.cachix.org, so niri builds
    # from source — exactly the cost we already paid under niri-flake. Keeping
    # glibc aligned is worth more than the cache.
    #
    # Option namespaces differ from niri-flake: NixOS side is still
    # `programs.niri.*`, but home-manager moved to
    # `wayland.windowManager.niri.*` (see home.nix).
    niri = {
      url = "git+https://codeberg.org/BANanaD3V/niri-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      # Pinned to a stable v5 tag (the v5 line renamed the home-manager module
      # from programs.noctalia-shell to programs.noctalia, swapped the ipc
      # surface for `noctalia msg`, and moved config to a declarative
      # config.toml). Bump by editing the tag below and re-verifying the
      # programs.noctalia options in home.nix still exist — a plain
      # `nix flake update noctalia` won't move a tag-pinned ref.
      url = "github:noctalia-dev/noctalia-shell/v5.3.0";
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
    # bump by editing the `v0.9.x` in the URL below (plain `nix flake
    # update herdr` won't move a tag-pinned ref).
    herdr = {
      url = "github:ogulcancelik/herdr/v0.9.5";
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

            # niri-nix exposes `nixosModules.default` (niri-flake used
            # `nixosModules.niri`). The home-manager side is imported in
            # home.nix alongside noctalia's.
            niri.nixosModules.default
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
