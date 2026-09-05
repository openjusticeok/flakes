{
  description = "opi project using the opi flake-parts module";

  inputs = {
    # Pin everything to the versions opi-flakes itself uses, so pkgs (and
    # everything built from it) matches the base shell's nixpkgs exactly.
    opi-flakes.url = "path:../..";
    nixpkgs.follows = "opi-flakes/nixpkgs";
    flake-parts.follows = "opi-flakes/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi-flakes.flakeModules.opi ];

      # `base` is auto-wired from the opi-flakes input above; each
      # opi.shells entry below becomes devShells.<name> (`nix develop
      # .#geo` etc.). Adjacent shells are independent: each is base +
      # its own opts, and they share nothing beyond base.
      #
      # Typical projects just reference shipped layers (geo, shiny, ...)
      # and add project-specific packages/env/hooks — see examples/project.
      # Defining an opi.layers entry here is rare; it's shown once for
      # completeness: this project has two shells that share one bundle.
      perSystem = { pkgs, ... }: {
        opi.layers.analysis = {
          packages = with pkgs; [
            duckdb
            postgresql
          ];

          shellHook = ''
            echo "analysis layer ready: duckdb + postgresql."
          '';
        };

        opi.shells.default.shellHook = ''
          echo "opi default shell ready."
        '';

        opi.shells.analysis = {
          layers = [ "analysis" ];

          packages = [ pkgs.gnuplot ];
        };

        opi.shells.shiny.layers = [ "shiny" ];
      };
    };
}
