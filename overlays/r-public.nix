# Public CRAN R package fixes (native deps, postPatch, version bumps).
#
# These are upstream candidates: land the fix here, open a PR against
# NixOS/nixpkgs pkgs/development/r-modules/default.nix (and/or rstats-on-nix),
# and drop it here once the pinned revision carries it. Example:
#
#   final: prev: {
#     rPackages = prev.rPackages.override {
#       overrides = {
#         somepkg = prev.rPackages.somepkg.overrideAttrs (old: {
#           buildInputs = (old.buildInputs or [ ]) ++ [ prev.gdal ];
#         });
#       };
#     };
#   }
final: prev: { }
