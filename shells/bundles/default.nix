# Predefined opi bundles, shipped with opi.
#
# A bundle is a named set of Nix packages / R packages / env / shellHook that
# projects include in one or more shells via
# `opi.shells.<name>.bundles = [ "<name>" ]`. The opi module merges this set into
# `opi.bundles` as defaults, so every project importing flakeModules.default gets
# them for free. Users can extend (packages/rPackages append) or override (env
# via mkDefault) any of them.
#
# Add a bundle by creating `<name>.nix` here (a `pkgs: { ... }` function) and
# listing it below.
pkgs:
{
  # Bundles may carry Nix packages and/or R packages (`rPackages`). The
  # org-standard R set is not a bundle: it lives in the base shell
  # (shells/base.nix) so it's present in every opi shell.
  geo = import ./geo.nix pkgs;
  shiny = import ./shiny.nix pkgs;
  quarto = import ./quarto.nix pkgs;
}
