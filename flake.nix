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

      imports = [ ./modules/opi.nix ];

      perSystem = { inputs', ... }: {
        # Repo devshell: the opi base shell via our own module. This flake
        # owns `base` directly (no opi-flakes input), so wire it here.
        opi.shells.default.base = inputs'.base.devShells.default;
      };

      flake = {
        inherit base;
        flakeModules.opi = import ./modules/opi.nix;
        templates.default = {
          description = "opi project shell";
          path = ./templates/default;
        };
      };
    };
}
