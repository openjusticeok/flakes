{
  description = "opi project using the base dev shell directly";

  inputs = {
    opi.url = "path:../..";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs@{ opi, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = { system, ... }: {
        # The base shell as-is: R + toolchain + dev tools. No project extras.
        devShells.default = opi.devShells.${system}.base;
      };
    };
}
