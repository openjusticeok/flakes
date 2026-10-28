# Predefined opi bundles, shipped with opi.
#
# A bundle is a named set of Nix packages / R packages / env / shellHook that
# projects include in one or more shells via
# `opi.shells.<name>.bundles = [ "<name>" ]`. The opi module merges this set into
# `opi.bundles`, so every project importing flakeModules.default gets them for
# free. Projects can extend (packages/rPackages append) or override (env values
# are mkDefault, so a project's own definition wins).
#
# Three bundles, one file: each is small enough that a file per bundle was more
# indirection than payload. Add a bundle by adding an entry here.
#
# The org-standard R set is deliberately *not* a bundle: it lives in
# lib/packageNames.nix and is present in every opi shell.
{
  pkgs,
  lib,
}: {
  # Geospatial development: GDAL/GEOS/PROJ toolchain for R packages like sf,
  # terra, and stars (the packages themselves are nix-built and carry their own
  # native deps).
  geo = {
    packages = with pkgs; [
      gdal
      geos
      proj
    ];

    env.PROJ_DATA = lib.mkDefault "${pkgs.proj}/share/proj";
  };

  # Shiny development: browser + node toolchain for running and testing apps
  # (shinytest2 drives Chromium headlessly).
  shiny = {
    packages = with pkgs; [
      chromium
      nodejs
    ];

    shellHook = ''
      echo "shiny bundle: chromium + nodejs ready."
    '';
  };
}
