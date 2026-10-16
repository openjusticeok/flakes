# The opi version-of-record overlay: system pins + public R overrides + private
# R packages. Composed in order (system first, so R overrides/private packages
# build against pinned system libs). Consumed by dev shells and deployments.
{ inputs }:
let
  lib = inputs.nixpkgs.lib;
in
lib.composeManyExtensions [
  (import ./system.nix)
  (import ./r-public.nix)
  (import ./r-private.nix { inherit inputs; })
]
