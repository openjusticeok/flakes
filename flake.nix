{
  description = "opi flakes collection";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    base.url = "path:./base";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, base, ... }: {
    base = base;
    lib = import ./lib { inherit inputs; };
  };
}
