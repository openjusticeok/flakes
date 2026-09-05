{
  description = "opi project with domain shells";

  inputs = {
    opi-flakes.url = "path:../..";
    nixpkgs.follows = "opi-flakes/nixpkgs";
    flake-parts.follows = "opi-flakes/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi-flakes.flakeModules.opi ];

      # This is what most projects look like: reference the layers
      # shipped with opi-flakes (geo, shiny, ...) by name, and add only
      # what is specific to this project (packages, env, shellHook).
      #
      # Defining an opi.layers entry here is the exception, not the
      # rule — reserve it for a bundle shared by multiple shells in
      # this same repo (see the layer rules in DEVELOPMENT.md).
      perSystem = { pkgs, ... }: {
        # Day-to-day work: base + geo tooling this project depends on,
        # plus a couple of project-specific extras.
        opi.shells.default = {
          layers = [ "geo" ];

          packages = [
            pkgs.jq
            pkgs.richgo
          ];

          # Add or override env vars from base and layers, e.g. a
          # project-local value for a var a layer sets with mkDefault:
          # env.PROJ_DATA = "$PWD/data/proj";
          env.R_MAX_VSIZE = "32Gb";

          shellHook = ''
            echo "default shell ready: base + geo + project extras."
          '';
        };

        # A separate shell for shiny work. Independent of `default`:
        # they share nothing beyond the base shell. Run with
        # `nix develop .#shiny`.
        opi.shells.shiny.layers = [ "shiny" ];
      };
    };
}
