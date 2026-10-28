{
  description = "opi shiny project";

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

      # Shiny development: the shiny bundle adds chromium + nodejs for
      # shinytest2 headless testing.
      perSystem = {...}: {
        opi.shells.default = {
          bundles = ["shiny"];
          rPackages = [
            "shiny"
            "shinytest2"
            "bslib"
            "htmltools"
          ];
        };
      };
    };
}
