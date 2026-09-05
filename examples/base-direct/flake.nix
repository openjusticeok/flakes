{
  description = "opi project using the base dev shell directly";

  inputs = {
    opi-flakes.url = "path:../..";
    nixpkgs.follows = "opi-flakes/nixpkgs";
    flake-parts.follows = "opi-flakes/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = { system, ... }: {
        # The base shell as-is: R, Source Sans 3, rv/air/arf/jarl.
        # No project-specific extras; base.shellEnv vars are already set.
        devShells.default = opi-flakes.base.devShells.${system}.default;
      };
    };
}
