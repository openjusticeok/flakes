# Dev shells for the org's private package repos: devShells.<pkg>-dev.
#
# Each is the org environment plus the package itself (whose
# propagatedBuildInputs bring its runtime deps onto R_LIBS_SITE), so working on
# ojodb/ojoutils/... uses the same R, toolchain, and environment as every opi
# project instead of a per-repo copy of the base shell.
#
# The package repos cannot depend on opi (`opi -> <pkg> -> opi` is a flake input
# cycle), so the org repo — which already has every package as an input — owns
# the supported dev environment. Each package repo keeps only a minimal
# standalone `nix develop` shell for working on it outside opi.
#
# Usage: nix develop .#ojodb-dev
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: {
    devShells =
      lib.mapAttrs' (
        pkgName: package:
          lib.nameValuePair "${pkgName}-dev" (
            import ../lib/mkOpiShell.nix {
              inherit pkgs lib;
              name = "opi-${pkgName}-dev";
              packages = [package];
            }
          )
      )
      (import ../lib/orgPackages.nix {inherit inputs system lib;}).packages;
  };
}
