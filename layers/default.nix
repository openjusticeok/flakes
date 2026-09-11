# Predefined opi layers, shipped with opi-flakes.
#
# A layer is a bundle of packages / env / shellHook that projects include
# in one or more shells via `opi.shells.<name>.layers = [ "<name>" ]`.
# The opi module merges this set into `opi.layers` as defaults, so every
# project importing flakeModules.opi gets them for free. Users can
# extend (packages append) or override (env via mkDefault) any of them.
#
# Add a layer by creating `<name>.nix` here (a `pkgs: { ... }` function)
# and listing it below.
pkgs:
{
  geo = import ./geo.nix pkgs;
  shiny = import ./shiny.nix pkgs;
  quarto = import ./quarto.nix pkgs;
}
