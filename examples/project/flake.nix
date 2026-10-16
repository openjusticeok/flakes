{
  description = "opi project with domain shells";

  inputs = {
    opi.url = "path:../..";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs@{ opi, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi.flakeModules.default ];

      # Most projects look like this: reference the bundles shipped with opi
      # (geo, shiny, ...) by name and add only what is specific to this project
      # (rPackages, packages, env, shellHook). Define an opi.bundles entry only
      # for a bundle shared by multiple shells in this same repo.
      perSystem = { pkgs, ... }: {
        # Day-to-day work: base + geo tooling + a couple of project extras.
        opi.shells.default = {
          bundles = [ "geo" ];
          rPackages = [ "sf" "tidycensus" "tigris" "targets" "ggplot2" ];

          packages = [
            pkgs.jq
            pkgs.richgo
          ];

          # Add or override env vars from base and bundles.
          env.R_MAX_VSIZE = "32Gb";

          shellHook = ''
            echo "default shell ready: base + geo + project extras."
          '';
        };

        # A separate shell for shiny work (independent of `default`).
        # Run with `nix develop .#shiny`.
        opi.shells.shiny = {
          bundles = [ "shiny" ];
          rPackages = [ "shiny" "shinytest2" ];
        };
      };
    };
}
