{
  description = "opi project";

  inputs = {
    opi.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs @ {
    opi,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      # The platforms opi supports, straight from the opi flake.
      inherit (opi.lib) systems;

      imports = [opi.flakeModules.default];

      # Each opi.shells.<name> entry becomes devShells.<name>. The org
      # environment is already in every shell — R, the toolchain, quarto,
      # positron, and the standard R set (opi.lib.standardRPackages, which
      # includes tidyverse core, targets, arrow and the ojo packages). List only
      # what this project adds, by CRAN name.
      perSystem = {pkgs, ...}: {
        opi.shells.default = {
          rPackages = ["patchwork" "gt"];

          # Anything else the org environment does not carry:
          packages = [pkgs.jq];

          # Extra environment variables and hook lines run after the org setup.
          env.R_MAX_VSIZE = "32Gb";
          shellHook = ''echo "project shell ready"'';
        };
      };
    };
}
