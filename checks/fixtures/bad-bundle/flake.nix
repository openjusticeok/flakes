# Fixture: an unknown bundle name must fail evaluation.
#
# Scripts/check-consumers expects this flake to fail and the error to name the
# offending bundle, so a shell that silently ignores a typo'd bundle — losing
# gdal or chromium without saying so — cannot pass.
{
  description = "opi module fixture (must fail: unknown bundle)";

  inputs = {
    opi.url = "path:../../..";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs @ {
    opi,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

      imports = [opi.flakeModules.default];

      perSystem = _: {
        opi.shells.default.bundles = ["no-such-bundle"];
      };
    };
}
