{
  description = "opi — Open Justice Oklahoma's Nix package set, dev shells, and flake module";

  # Public cache with the fresh CRAN/Bioconductor builds and backported R fixes
  # we build on. Declared here so consumers get it without hand-editing nix.conf.
  # Nix prompts once per flake to accept this; opt out with `accept-flake-config
  # = false` in nix.conf.
  nixConfig = {
    extra-substituters = [ "https://rstats-on-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };

  inputs = {
    # R/CRAN freshness + backported R fixes. Pinned by rev in flake.lock;
    # Renovate bumps it (monthly, merge-when-green). See PLAN.md.
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/r-daily";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # Private package flakes (P1) go here, each with:
    #   inputs.nixpkgs.follows = "nixpkgs";
    # so the whole closure shares this repo's single nixpkgs pin.
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      imports = [
        ./shells/base.nix
        ./modules/flake/opi.nix
        ./checks
      ];

      perSystem = { self', system, lib, ... }: {
        # positron-bin is unfree; allow only it so the shell can ship Positron
        # (which must share this nixpkgs' glibc with R).
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "positron-bin" ];
        };

        # The repo's own dev environment is the base shell.
        devShells.default = self'.devShells.base;
      };

      flake = {
        # Exported for consumers: `imports = [ opi.flakeModules.default ];`
        flakeModules.default = import ./modules/flake/opi.nix;

        # Version-of-record overlays (system pins + R overrides + private R
        # packages). Consumed by dev shells and deployments alike.
        overlays.default = import ./overlays { inherit inputs; };

        templates = {
          default = {
            description = "opi project shell";
            path = ./templates/default;
          };
          census = {
            description = "opi census project shell";
            path = ./templates/census;
          };
          gis = {
            description = "opi gis project shell";
            path = ./templates/gis;
          };
          shiny = {
            description = "opi shiny project shell";
            path = ./templates/shiny;
          };
        };
      };
    };
}
