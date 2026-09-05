# Geospatial development: GDAL/GEOS/PROJ toolchain wired up for R
# packages like sf, terra, and stars.
pkgs:
{
  packages = with pkgs; [
    gdal
    geos
    proj
  ];

  env.PROJ_DATA = "${pkgs.proj}/share/proj";

  shellHook = ''
    echo "geo layer: gdal, geos, proj ready (PROJ_DATA set)."
  '';
}
