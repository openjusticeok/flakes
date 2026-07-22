{ inputs }:

{
  # Wrap the opi base devShell with project-specific additions.

  # Example:
  #   opi-flakes.lib.mkOpiShell {
  #     pkgs = nixpkgs.legacyPackages.x86_64-linux;
  #     base = opi-flakes.base.devShells.default.x86_64-linux;
  #     extraPackages = [ pkgs.gdal ];
  #     extraShellHook = ''
  #       export PROJ_DATA="${pkgs.proj}/share/proj"
  #     '';
  #   }
  mkOpiShell = { pkgs, base, extraPackages ? [ ], extraShellHook ? "" }:
    pkgs.mkShell {
      name = "opi-project-shell";
      inputsFrom = [ base ];
      packages = extraPackages;
      shellHook = extraShellHook;
    };
}
