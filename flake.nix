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

    # OpenWhispr — local-first voice dictation (Electron). Upstream ships its
    # own flake AND a NixOS module, so we take both rather than hand-rolling
    # an appimageTools wrapper: the module wires the Wayland auto-paste
    # plumbing (ydotoold + the uinput module/udev rule + the two group
    # memberships), which is the part that is fiddly to get right and the
    # thing upstream's own issue #728 exists about.
    #
    # Version caveat: upstream's nix/package.nix pins the AppImage by hash and
    # was last bumped to v1.7.4 (2026-07-08), while releases are at v1.11.0.
    # `nix flake update openwhispr` tracks their main branch, so it only moves
    # the app when THEY bump that hash — a flake update is not enough on its
    # own. If the gap matters, the alternative is vendoring a copy of their
    # package.nix with a newer version + hash, at the cost of maintaining the
    # extraPkgs list ourselves.
    openwhispr = {
      url = "github:OpenWhispr/openwhispr";
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

    # Herdr UI (https://herdrui.dev/) — a native GPUI window that is a CLIENT
    # for the `herdr` daemon above. It attaches to that daemon's
    # herdr-client.sock and paints its cells; it owns no terminals and never
    # installs or upgrades a daemon, so it pairs with the `herdr` input and
    # is unrelated to the herdr-app/herdr-core pair in home.nix.
    #
    # THIRD PARTY, not herdr.dev: published by Fabien Penso (penso/herdr-gpui)
    # under Apache-2.0. The name and domain closely mirror the official ones,
    # which is worth knowing because this is a client for the daemon that runs
    # coding agents. It is pinned to a tag and read on purpose rather than
    # tracking a branch.
    #
    # Tag-pinned like `herdr`: versions are date-stamped (v2026MMDD.N), and a
    # plain `nix flake update herdr-gpui` won't move a tag-pinned ref — bump
    # the tag in the URL. Upstream's own flake builds it from source with the
    # toolchain rust-toolchain.toml pins, so there is no binary cache for it
    # and the first build is a long one.
    herdr-gpui = {
      url = "github:penso/herdr-gpui/v20261103.1";
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
            inputs.openwhispr.nixosModules.default

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

      # Per-project dev environments — the Nix-native take on Omarchy's
      # dev-env installer / Bluefin's devcontainers. Instead of installing a
      # language toolchain globally, each project carries its own flake.nix
      # devShell, and direnv + nix-direnv (programs.direnv in home.nix) load it
      # on `cd`. Scaffold one into the current directory with:
      #
      #   nix flake init -t ~/nixos-setup#python    # or node / rust / go
      #
      # Each template is a minimal flake.nix devShell + an `.envrc` (`use
      # flake`) + a .gitignore that already excludes `.direnv/`. The template
      # flakes are standalone (their own nixpkgs input, their own flake.lock
      # on first use) — they do NOT follow this repo's nixpkgs, so a project
      # stays reproducible when cloned onto a machine without this config.
      #
      # Referenced by local path, never as `github:sroberts/nixos-setup` —
      # same reason this repo is never a flake input (see CONTRIBUTING.md).
      templates =
        let
          # Shared hint printed after `nix flake init`. In a git repo, flakes
          # only see tracked files, so flake.nix must be `git add`ed before
          # `direnv allow` can evaluate it. Nix renders this as Markdown (and
          # reflows plain lines), hence the fenced block.
          welcomeText = ''
            Dev shell scaffolded. Next:

            ```sh
            git add flake.nix .envrc .gitignore   # flakes only see tracked files
            direnv allow                          # load the shell now and on every cd
            ```
          '';
        in
        {
          python = {
            path = ./templates/python;
            description = "Python dev shell: python3 + uv (uv pinned to the Nix interpreter)";
            inherit welcomeText;
          };
          node = {
            path = ./templates/node;
            description = "Node.js dev shell: nodejs + pnpm";
            inherit welcomeText;
          };
          rust = {
            path = ./templates/rust;
            description = "Rust dev shell: cargo, rustc, rust-analyzer, clippy, rustfmt";
            inherit welcomeText;
          };
          go = {
            path = ./templates/go;
            description = "Go dev shell: go + gopls";
            inherit welcomeText;
          };
        };
    };
}
