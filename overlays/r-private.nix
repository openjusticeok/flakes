# Private (org) R packages, injected into pkgs.rPackages so the name resolver
# and shells see one unified namespace.
#
# Private package repos are self-contained flakes consumed as inputs (see
# flake.nix), each pinned to this repo's nixpkgs via `inputs.nixpkgs.follows`.
# P1 wires them here, e.g.:
#
#   { inputs }:
#   final: prev:
#   let
#     system = prev.stdenv.hostPlatform.system;
#   in
#   {
#     rPackages = prev.rPackages.override {
#       overrides = prev.rPackages.overrides or { } // {
#         ojodb = inputs.ojodb.packages.${system}.ojodb;
#         ojoutils = inputs.ojoutils.packages.${system}.ojoutils;
#         ojothemes = inputs.ojothemes.packages.${system}.ojothemes;
#         ojoregex = inputs.ojoregex.packages.${system}.ojoregex;
#       };
#     };
#   }
{ inputs ? { } }:
final: prev: { }
