{
  description = "opi gis project";

  inputs = {
    opi-flakes.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi-flakes/nixpkgs";
    flake-parts.follows = "opi-flakes/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi-flakes.flakeModules.opi ];

      # Full GIS stack: terra, sfnetworks, spatial analysis, and
      # browser maps on the geo layer's gdal/geos/proj toolchain.
      # R dependencies live in rproject.toml.
      perSystem = { ... }: {
        opi.shells.default.layers = [ "geo" ];
      };
    };
}
