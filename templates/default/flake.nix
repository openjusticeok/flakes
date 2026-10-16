{
  description = "opi project";

  inputs = {
    opi.url = "github:openjusticeok/flakes";
    nixpkgs.follows = "opi/nixpkgs";
    flake-parts.follows = "opi/flake-parts";
  };

  outputs = inputs@{ opi, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [ opi.flakeModules.default ];

      # Each opi.shells.<name> entry becomes devShells.<name>, wrapping the opi
      # base shell automatically. List R packages by CRAN name; they resolve
      # against pkgs.rPackages (org + nixpkgs). Add Nix packages, env, hooks:
      #   opi.shells.default = {
      #     rPackages = [ "dplyr" "data.table" ];
      #     packages = [ pkgs.jq ];
      #     env.R_MAX_VSIZE = "32Gb";
      #     shellHook = ''echo ready'';
      #   };
      perSystem = { ... }: {
        opi.shells.default = {
          rPackages = [ "dplyr" "ggplot2" ];
        };
      };
    };
}
