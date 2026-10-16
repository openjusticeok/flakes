# Geospatial development: GDAL/GEOS/PROJ toolchain for R packages like sf,
# terra, and stars (the packages themselves are nix-built and carry their own
# native deps).
pkgs:
{
  packages = with pkgs; [
    gdal
    geos
    proj
  ];

  env.PROJ_DATA = "${pkgs.proj}/share/proj";
}
