# Quarto publishing: Chromium for `quarto preview` and HTML screenshots (same
# rationale as the shiny bundle's browser). Core quarto tooling lives in the
# base shell; this adds the browser it needs for live preview.
pkgs:
{
  packages = with pkgs; [
    chromium
  ];

  shellHook = ''
    echo "quarto bundle: chromium ready for quarto preview."
  '';
}
