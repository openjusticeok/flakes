{
  description = "opi project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    opi-flakes.url = "github:openjusticeok/flakes";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = { pkgs, system, ... }: {
        devShells.default = opi-flakes.lib.mkOpiShell {
          pkgs = nixpkgs.legacyPackages.${system};
          base = opi-flakes.base.devShells.${system}.default;
        };
      };
    };
}
