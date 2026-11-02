{
  description = "NixOS + niri + Noctalia configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # import-tree — auto-import every .nix module under modules/nixos/core
    # and modules/home (hosts/common.nix wires the trees). A new file in the
    # tree is a new feature; no flake or import-list edits. Deps-free
    # callable flake; paths containing "/_" are ignored by default.
    import-tree.url = "github:denful/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
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
      # programs.niri module, and modules/home/desktop/niri.nix's
      # binds/outputs/touchpad are all written as `programs.niri.settings`
      # with build-time validation.
    };

    noctalia = {
      # On the stable v5 line (the v4→v5 beta migration is done). Re-pinned
      # from v5.0.0-beta2 (Jul 2026): the plugin manifest schema moved to
      # canonical `plugin_api` in v5.0.0-beta.9, so current community plugins
      # (keybind cheatsheet et al.) require >=5.0.x. After every bump,
      # re-verify programs.noctalia option names in
      # modules/home/desktop/noctalia.nix (widget/settings renames surface as
      # eval errors) and the seeded config.toml migration.
      url = "github:noctalia-dev/noctalia-shell/v5.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # noctalia-greeter — greetd greeter that mirrors Noctalia Shell's look.
    # Tracks main (no tagged releases yet). Bump with `nix flake update
    # noctalia-greeter`.
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Oh My Pi (omp) prebuilt standalone binaries (auto-updated from upstream releases).
    # Multi-platform: x86_64-linux, aarch64-linux (Asahi 16K pages), aarch64-darwin.
    omp = {
      url = "github:gosha20777/omp-bin-flake";
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

    # LazyVim starter template — cloned to ~/.config/nvim once at activation
    # if missing. Flake input downloads at build time (zero network at boot);
    # updates via `nix flake update lazyvim-starter` apply only to fresh setups.
    lazyvim-starter = {
      url = "github:LazyVim/starter";
      flake = false;
    };

    # rmpc — MPD TUI client. Pinned to a master commit (not a release):
    # album_art.custom_loader (per-station radio covers via
    # modules/data/rmpc/radio_cover_loader) exists only on master; last
    # release v0.11.0 predates it. Upstream ships its own crane-based
    # flake; nixpkgs is deliberately NOT followed (their build is pinned
    # against their own lock). Built from source on first switch (cached
    # afterwards). Bump with `nix flake update rmpc` after re-verifying
    # modules/data/rmpc/{config,theme}.ron against master's changelog
    # (breaking theme/Browser-pane changes happen between releases).
    rmpc = {
      url = "github:mierak/rmpc/fbc57536abcd8dc7deb4dc7b42614c896a2992a3";
    };

    # NegPy — Tool for processing film negatives with film-physics simulation.
    # Ships its own uv2nix flake; nixpkgs is not followed to preserve its
    # pinned uv2nix/pyproject-nix dependencies and cache.
    negpy = {
      url = "github:marcinz606/NegPy";
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

  # Only the inputs referenced directly in this file are destructured; the
  # rest (noctalia, herdr, …) are reached as `inputs.<name>` from the module
  # tree via specialArgs + extraSpecialArgs (hosts/common.nix wires both).
  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;

      # Every directory under ./hosts is a machine. Drop in a new
      # hosts/<hostname>/ (a default.nix + its hardware-configuration.nix) and
      # it becomes nixosConfigurations.<hostname> automatically — no edit to
      # this file. hosts/common.nix is a FILE and doesn't match the directory
      # filter. scripts/new-host.sh scaffolds one; see hosts/README.md.
      hostNames = builtins.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts)
      );

      # A host is one directory under ./hosts: its default.nix imports
      # hosts/common.nix (the shared module trees + home-manager wiring),
      # ./hardware-configuration.nix, and any roles (modules/nixos/roles/)
      # and per-host home overrides (./home.nix) it needs.
      mkHost =
        hostname:
        lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${hostname}

            # ── SECURE BOOT ──
            # Uncomment together with the input in the inputs block and the
            # block in modules/nixos/core/boot.nix; the module is wired in
            # hosts/common.nix (commented there too):
            # inputs.lanzaboote.nixosModules.lanzaboote
          ];
        };
      # The live installer ISO is NOT a target machine, so it lives outside
      # hosts/ (auto-discovery must only pick target machines). It boots into
      # the full shared desktop (modules/installer imports hosts/common.nix)
      # and runs the Python installer; target installation is network-based
      # (nixos-install --flake). The module itself is architecture-neutral —
      # a future ARM image is one line: live-aarch64 = mkLive "aarch64-linux".
      mkLive =
        system:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
            repoRoot = self.outPath;
          };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./modules/installer
          ];
        };
    in
    {
      nixosConfigurations = lib.genAttrs hostNames mkHost // {
        live-x86_64 = mkLive "x86_64-linux";
        live-aarch64 = mkLive "aarch64-linux";
      };

      # `nix fmt` formats all .nix files in the tree. pkgs.nixfmt is the RFC 166
      # implementation that ships in nixpkgs; the tree is already nixfmt-clean
      # and CI enforces it (`nix fmt -- --check` in .github/workflows/check.yml).
      #
      # The wrapper exists because Nix ≥ 2.24 runs the formatter with NO
      # arguments for a bare `nix fmt`, and nixfmt 1.5.0 deprecates bare
      # invocation (treats it as anonymous stdin and dies on empty input).
      # So: no args -> walk the git tree ourselves; any args (CI's
      # `nix fmt -- --check <files…>`, or explicit paths) -> pass through.
      formatter = lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (
        sys:
        let
          pkgs = nixpkgs.legacyPackages.${sys};
        in
        pkgs.writeShellApplication {
          name = "fmt";
          runtimeInputs = [
            pkgs.nixfmt
            pkgs.git
            pkgs.findutils
          ];
          text = ''
            # Bare `nix fmt` / `nix fmt -- --check`: walk the tree ourselves
            # (Nix >= 2.24 passes no file args; nixfmt 1.5.0 can't do bare runs).
            if [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = "--check" ]; }; then
              check=()
              if [ "$#" -eq 1 ]; then
                check=(--check)
              fi
              if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                # Tracked + untracked (non-ignored) .nix files, NUL-safe
                git ls-files --cached --others --exclude-standard -z -- '*.nix' \
                  | xargs -0 -r nixfmt "''${check[@]}"
              else
                find . -name '*.nix' -not -path './.git/*' -print0 \
                  | xargs -0 -r nixfmt "''${check[@]}"
              fi
              exit $?
            fi
            # Any other args (CI's `nix fmt -- --check <files…>`, explicit paths): pass through
            exec nixfmt "$@"
          '';
        }
      );
    };
}
