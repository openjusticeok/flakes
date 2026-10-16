# The opi version-of-record overlay: system pins + public R overrides + private
# R packages. Consumed by dev shells and deployments alike.
{ inputs }:
let
  lib = inputs.nixpkgs.lib;
in
lib.composeManyExtensions [
  (import ./system.nix)
  (final: prev: {
    rPackages = prev.rPackages.override {
      overrides =
        (import ./r-public.nix { pkgs = prev; inherit lib; })
        // (import ./r-private.nix {
          inherit inputs lib;
          system = prev.stdenv.hostPlatform.system;
        });
    };
  })
]
