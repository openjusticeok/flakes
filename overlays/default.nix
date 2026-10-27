# The opi version-of-record overlay: system pins + public R overrides + private
# R packages. Consumed by dev shells and deployments alike.
{ inputs }:
let
  lib = inputs.nixpkgs.lib;
in
lib.composeManyExtensions [
  (import ./system.nix)
  (final: prev: {
    # Exactly one `rPackages.override` for every source of R overrides: calling
    # it twice would clobber the earlier `overrides`. Public CRAN fixes
    # (r-public.nix) and the org's own packages -- self-contained flakes declared
    # as inputs in flake.nix, listed in lib/orgPackages.nix -- merge here, so
    # `pkgs.rPackages.ojodb` and the overridden `pkgs.rPackages.arrow` are
    # first-class attributes for the resolver, the base shell, and consumers.
    rPackages = prev.rPackages.override {
      overrides =
        (import ./r-public.nix { pkgs = prev; })
        // (import ../lib/orgPackages.nix {
          inherit inputs lib;
          system = prev.stdenv.hostPlatform.system;
        }).packages;
    };
  })
]
