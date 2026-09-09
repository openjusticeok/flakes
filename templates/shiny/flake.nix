{
  description = "opi shiny project";

  inputs = {
    opi-flakes.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi-flakes/nixpkgs";
    flake-parts.follows = "opi-flakes/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi-flakes.flakeModules.opi ];

      # Shiny development: chromium + nodejs for shinytest2 headless
      # testing. R dependencies live in rproject.toml.
      perSystem = { ... }: {
        opi.shells.default.layers = [ "shiny" ];
      };
    };
}
