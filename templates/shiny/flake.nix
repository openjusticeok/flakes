{
  description = "opi shiny project";

  inputs = {
    opi.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs@{ opi, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi.flakeModules.default ];

      # Shiny development: the shiny bundle adds chromium + nodejs for
      # shinytest2 headless testing.
      perSystem = { ... }: {
        opi.shells.default = {
          bundles = [ "shiny" ];
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
