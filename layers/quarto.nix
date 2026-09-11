# Quarto publishing: Chromium for `quarto preview` and HTML screenshots
# (same rationale as the shiny layer's browser). Core quarto tooling lives
# in the base shell; this adds the browser it needs for live preview.
pkgs:
{
  packages = with pkgs; [
    chromium
  ];

  shellHook = ''
    echo "quarto layer: chromium ready for quarto preview."
  '';
}
