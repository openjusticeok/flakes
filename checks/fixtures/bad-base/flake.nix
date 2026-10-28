# Fixture: a base shell that is not an opi base shell must fail evaluation.
#
# `base` defaults to the opi input's base devShell; setting it to any package
# would otherwise drop R_HOME/FONTCONFIG_FILE and the base setup hook, so the
# module has to refuse. Scripts/check-consumers expects the refusal.
{
  description = "opi module fixture (must fail: non-opi base)";

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

      perSystem = {pkgs, ...}: {
        opi.shells.default.base = pkgs.hello;
      };
    };
}
