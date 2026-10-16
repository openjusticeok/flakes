# Resolve CRAN-style package names to derivations in pkgs.rPackages.
#
# R package names may contain dots but not underscores, so CRAN name -> nixpkgs
# attribute is a lossless mapping (`data.table` -> `data_table`). We try the
# literal name first, then the underscored form.
{ pkgs, lib }:
let
  underscored = lib.replaceStrings [ "." ] [ "_" ];
  has = name: pkgs.rPackages ? ${name};
  known = name: has name || has (underscored name);

  # Resolve one name to a derivation, or throw an actionable error.
  resolve =
    name:
    if has name then
      pkgs.rPackages.${name}
    else if has (underscored name) then
      pkgs.rPackages.${underscored name}
    else
      throw ''
        opi.rPackages: '${name}' is not in pkgs.rPackages (tried '${name}' and '${underscored name}').
        If it is a private package, it must be added to the org package set.
        If it is a public CRAN package that is missing or broken, request an override.
      '';

  # Resolve many names, reporting all unknown ones at once.
  resolveMany =
    names:
    let
      missing = builtins.filter (n: !known n) names;
    in
    if missing != [ ] then
      throw ''
        opi.rPackages: unknown package(s): ${lib.concatStringsSep ", " missing}.
        If they are private, add them to the org package set.
        If they are public CRAN packages that are missing or broken, request an override.
      ''
    else
      map resolve names;
in
{
  inherit resolve resolveMany;
}
