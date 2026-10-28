# Fixture: an unknown R package name must fail evaluation with a suggestion.
#
# scripts/check-consumers expects this flake to fail and the error to name the
# nearest known package ("dplyr" for "dplry"), so a broken resolver or a broken
# hint cannot pass silently.
{
  description = "opi module fixture (must fail: unknown R package)";

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
        opi.shells.default.rPackages = ["dplry"];
      };
    };
}
