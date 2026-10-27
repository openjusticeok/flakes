# Dev shells for the org's private package repos: devShells.<pkg>-dev.
#
# Each is the opi base shell + the package itself (whose propagatedBuildInputs
# bring its runtime deps onto R_LIBS_SITE), so working on ojodb/ojoutils/... uses
# the same R, toolchain, and environment as every opi project instead of a
# per-repo copy of the base shell. The package repos cannot depend on opi (flake
# input cycle); see lib/mkPackageShell.nix.
#
# Usage: nix develop .#ojodb-dev
{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, self', ... }:
    let
      base = self'.devShells.base;

      org = import ../lib/orgPackages.nix { inherit inputs system lib; };

      mkPackageShell = import ../lib/mkPackageShell.nix;
    in
    {
      devShells = lib.mapAttrs' (
        pkgName: package:
        lib.nameValuePair "${pkgName}-dev" (mkPackageShell {
          inherit pkgs lib base package;
          name = "opi-${pkgName}-dev";
        })
      ) org.packages;
    };
}
