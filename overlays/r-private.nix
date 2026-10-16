# Private (org) R packages, as `rPackages.overrides` entries.
#
# Each private package is a self-contained flake consumed as an input (see
# flake.nix), pinned to this repo's nixpkgs via `inputs.nixpkgs.follows`. Merged
# with r-public.nix into one `rPackages.override` in overlays/default.nix.
#
# Lazy: only packages whose flake is actually an input are included, so absent
# inputs never force their thunk.
{ inputs, lib, system }:
let
  candidates = {
    ojodb = inputs.ojodb.packages.${system}.ojodb;
    ojothemes = inputs.ojothemes.packages.${system}.ojothemes;
    ojoutils = inputs.ojoutils.packages.${system}.ojoutils;
    ojoregex = inputs.ojoregex.packages.${system}.ojoregex;
  };
in
lib.filterAttrs (name: _: inputs ? ${name}) candidates
