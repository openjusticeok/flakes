# Public CRAN R package fixes — upstream candidates.
#
# Returns the `rPackages.overrides` entries for public packages (as opposed to
# `r-private.nix`, which is for org packages). Both are merged into a single
# `rPackages.override` in overlays/default.nix, because calling
# `rPackages.override` twice would clobber the earlier `overrides`.
{ pkgs, lib ? pkgs.lib }:
{
  # nixpkgs' arrow-cpp has GCS/S3 (enableGcs defaults on), but the R `arrow`
  # bindings' configure misdetects it (ArrowOptions.cmake writes "TRUE" where the
  # configure expects "ON"), so R arrow reports "built without GCS support".
  # Force the feature macros and a full (non-minimal) build so GCS/S3 are in.
  arrow = pkgs.rPackages.arrow.overrideAttrs (old: {
    env = (old.env or { }) // {
      ARROW_R_CXXFLAGS = "-DARROW_R_WITH_GCS -DARROW_R_WITH_S3";
      LIBARROW_MINIMAL = "false";
      ARROW_USE_PKG_CONFIG = "true";
    };
  });
}
