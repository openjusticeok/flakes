{
  description = "opi census project";

  inputs = {
    opi.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs@{ opi, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi.flakeModules.default ];

      # Census data work on the geo bundle's gdal/geos/proj toolchain.
      perSystem = { ... }: {
        opi.shells.default = {
          bundles = [ "geo" ];
          rPackages = [
            "tidycensus"
            "tigris"
            "crsuggest"
            "sf"
            "dplyr"
            "targets"
            "rmarkdown"
            "knitr"
          ];
        };
      };
    };
}
