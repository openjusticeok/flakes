{
  description = "opi gis project";

  inputs = {
    opi.url = "github:openjusticeok/flakes";
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

      # Full GIS stack on the geo bundle's gdal/geos/proj toolchain. targets,
      # rmarkdown, knitr and the tidyverse core are already in every opi shell
      # (opi.lib.standardRPackages), so only the GIS extras are listed here.
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
            # census geometry
            "tidycensus"
            "tigris"
            "crsuggest"
            # browser maps
            "mapgl"
            # columnar geo data (duckdb is in the org environment)
            "geoarrow"
          ];
        };
      };
    };
}
