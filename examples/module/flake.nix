{
  description = "opi project using the opi flake-parts module";

  inputs = {
    # Pin everything to the versions opi itself uses, so pkgs (and everything
    # built from it) matches the base shell's nixpkgs exactly.
    opi.url = "path:../..";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs @ {
    opi,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      # The platforms opi supports, straight from the opi flake.
      inherit (opi.lib) systems;

      imports = [opi.flakeModules.default];

      # Each opi.shells entry becomes devShells.<name>. Adjacent shells are
      # independent: each is the org environment + its own opts, sharing nothing
      # beyond that.
      #
      # Typical projects reference shipped bundles (geo, shiny, ...) and add
      # project-specific extras — see examples/project. Defining an
      # opi.bundles entry here is the exception: this project has two shells
      # that share one bundle.
      perSystem = {pkgs, ...}: {
        opi.bundles.analysis = {
          packages = with pkgs; [
            duckdb
            postgresql
          ];

          shellHook = ''
            echo "analysis bundle ready: duckdb + postgresql."
          '';
        };

        opi.shells.default.shellHook = ''
          echo "opi default shell ready."
        '';

        opi.shells.analysis = {
          bundles = ["analysis"];
          packages = [pkgs.gnuplot];
        };

        opi.shells.shiny.bundles = ["shiny"];
      };
    };
}
