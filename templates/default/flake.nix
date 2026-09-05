{
  description = "opi project";

  inputs = {
    opi-flakes.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi-flakes/nixpkgs";
    flake-parts.follows = "opi-flakes/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, opi-flakes, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi-flakes.flakeModules.opi ];

      # opi.shells entries become devShells.<name>, wrapping the opi
      # base shell (R, Source Sans 3, rv/air/arf/jarl) automatically.
      # Add project packages/env/hooks here, e.g.:
      #   perSystem = { pkgs, ... }: {
      #     opi.shells.default = {
      #       packages = [ pkgs.gdal ];
      #       env.PROJ_DATA = "${pkgs.proj}/share/proj";
      #     };
      #   };
      # For bundles shared by multiple shells, use opi.layers.<name>
      # and reference them via opi.shells.<name>.layers.
      perSystem = { ... }: {
        opi.shells.default = { };
      };
    };
}
