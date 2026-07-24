{
  description = "opi flakes collection";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    base.url = "path:./base";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, base, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        devShells.default = pkgs.mkShell {
          name = "opi-flakes-shell";
          packages = with pkgs; [ jq gh ];
        };
      };

      flake = {
        inherit base;
        lib = import ./lib { inherit inputs; };
      };
    };
}
