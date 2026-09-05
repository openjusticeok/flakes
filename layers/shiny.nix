# Shiny development: browser + node toolchain for running and testing
# apps (shinytest2 drives Chromium headlessly).
pkgs:
{
  packages = with pkgs; [
    chromium
    nodejs
  ];

  shellHook = ''
    echo "shiny layer: chromium + nodejs ready."
  '';
}
