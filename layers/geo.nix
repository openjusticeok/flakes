# Geospatial development: GDAL/GEOS/PROJ toolchain wired up for R
# packages like sf, terra, and stars.
pkgs:
let
  hostConfig = pkgs.lib.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.config;
in
{
  packages = with pkgs; [
    gdal
    geos
    proj
  ];

  env.PROJ_DATA = "${pkgs.proj}/share/proj";

  # Runtime additions to base exports: expose the geo toolchain's
  # pkgconfig dirs to source-built R packages (sf, terra, ...) and
  # rpath the libs into their .so files.
  shellHook = ''
    export PKG_CONFIG_PATH="${pkgs.lib.getDev pkgs.gdal}/lib/pkgconfig:${pkgs.lib.getDev pkgs.geos}/lib/pkgconfig:${pkgs.lib.getDev pkgs.proj}/lib/pkgconfig:$PKG_CONFIG_PATH"

    export NIX_LDFLAGS_${hostConfig}="$NIX_LDFLAGS_${hostConfig} -rpath ${pkgs.lib.getLib pkgs.gdal}/lib -rpath ${pkgs.lib.getLib pkgs.geos}/lib -rpath ${pkgs.lib.getLib pkgs.proj}/lib"
  '';
}
