{
  description = "opi gis project";

  inputs = {
    opi.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs @ {
    opi,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [opi.flakeModules.default];

      # Full GIS stack on the geo bundle's gdal/geos/proj toolchain.
      perSystem = {...}: {
        opi.shells.default = {
          bundles = ["geo"];
          rPackages = [
            # vector + raster
            "sf"
            "terra"
            "stars"
            "sfdep"
            "sfnetworks"
            "freestiler"
            # census geometry (kept from the rv-era template)
            "tidycensus"
            "tigris"
            "crsuggest"
            # browser maps
            "mapgl"
            # columnar geo data (duckdb is in the base shell)
            "geoarrow"
            # reporting
            "targets"
            "rmarkdown"
            "knitr"
          ];
        };
      };
    };
}
