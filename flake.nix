{
  description = "opi — Open Justice Oklahoma's Nix package set, dev shells, and flake module";

  # Public cache with the fresh CRAN/Bioconductor builds and backported R fixes
  # we build on. Declared here so consumers get it without hand-editing nix.conf.
  # Nix prompts once per flake to accept this; opt out with `accept-flake-config
  # = false` in nix.conf.
  nixConfig = {
    extra-substituters = ["https://rstats-on-nix.cachix.org"];
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

    # Private package flakes. Each is self-contained and pins nixpkgs, which
    # follows ours here so the whole closure shares one nixpkgs pin.
    ojodb = {
      url = "github:openjusticeok/ojodb/ojodb-v3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ojothemes = {
      url = "github:openjusticeok/ojothemes/ojothemes-v2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.ojodb.follows = "ojodb";
    };
    ojoutils = {
      url = "github:openjusticeok/ojoutils/ojoutils-v0.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ojoregex = {
      url = "github:openjusticeok/ojoregex/ojoregex-v0.10.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.ojodb.follows = "ojodb";
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    # The platforms opi supports. Exported as `opi.lib.systems` so a consumer
    # pins the same list instead of copying it (or, worse, using
    # `flakeExposed` and failing on a host opi does not build for).
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      inherit systems;

      imports = [
        ./shells/base.nix
        ./shells/private.nix
        ./modules/flake/opi.nix
        ./checks
      ];

      perSystem = {
        self',
        pkgs,
        ...
      }: {
        # `pkgs` comes from the module (modules/flake/opi.nix), which instantiates
        # it with the version-of-record overlay and the positron-bin unfree
        # exemption. There is no second definition here: the repo's own shells
        # and a consumer's shells are built from the same package set.

        # The repo's own dev environment is the base shell.
        devShells.default = self'.devShells.base;

        # `nix fmt`. CI runs `nix fmt -- --check .`, so formatting never has to
        # be a review topic; the formatter comes from our own nixpkgs pin, so
        # CI and a dev shell agree on the version.
        formatter = pkgs.alejandra;
      };

      flake = {
        # Exported for consumers: `imports = [ opi.flakeModules.default ];`
        flakeModules.default = import ./modules/flake/opi.nix;

        # Version-of-record overlays (system pins + R overrides + private R
        # packages). Consumed by dev shells and deployments alike.
        overlays.default = import ./overlays {inherit inputs;};

        # For consumers that want to say `systems = opi.lib.systems;` and to see
        # what every opi shell already provides before adding to it.
        lib = {
          inherit systems;
          standardRPackages = (import ./lib/packageNames.nix).standard;
        };

        templates = {
          default = {
            description = "opi project shell";
            path = ./templates/default;
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
