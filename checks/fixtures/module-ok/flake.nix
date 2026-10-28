# Fixture: a consumer that exercises the whole module path.
#
# It is not an opi output and nothing imports it; scripts/check-consumers
# evaluates it against the working tree (and CI runs that script). Between this
# and the bad-* fixtures it is the only thing that proves `opi.shells` still
# composes: this repo's own devShells never traverse the module, so
# `nix flake check` alone cannot see a broken module.
#
# Covered here: shipped bundle lookup (geo, shiny), a locally defined bundle, a
# private org package by name, a dotted CRAN name, extra Nix packages, env, and
# shellHooks from both a bundle and a shell.
{
  description = "opi module fixture (must evaluate)";

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
        # A bundle defined by the consumer, referenced by a shell below.
        opi.bundles.project = {
          packages = [pkgs.jq];
          env.FIXTURE_BUNDLE = "1";
          shellHook = ''echo "fixture bundle ready."'';
        };

        opi.shells.default = {
          bundles = ["geo" "project"];
          rPackages = ["sf" "data.table" "ojodb"];
          packages = [pkgs.richgo];
          env.FIXTURE_SHELL = "1";
          shellHook = ''echo "fixture shell ready."'';
        };

        # A second, independent shell: base + the shipped shiny bundle.
        opi.shells.shiny = {
          bundles = ["shiny"];
          rPackages = ["shiny"];
        };
      };
    };
}
