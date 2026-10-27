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

  # --- "did you mean" hints ------------------------------------------------
  # PLAN invariant #4: unknown names fail with nearest matches, not just a list.

  # Scored in the caller's dialect (CRAN names use dots), so `dat.tabel` is one
  # edit away from `data.table` rather than four from `data_table`.
  knownNames = map (n: lib.replaceStrings [ "_" ] [ "." ] n) (builtins.attrNames pkgs.rPackages);

  # Up to three nearest known names, closest first; ties prefer the longer shared
  # prefix ("dplry" -> dplyr rather than dblr). Scoring all ~20k attributes on
  # every typo would dominate eval, so only same-initial, similar-length names
  # are scored -- enough to catch typos and misremembered names.
  nearest =
    name:
    if name == "" then
      [ ]
    else
      let
        initial = builtins.substring 0 1 name;
        len = lib.stringLength name;
        candidates = builtins.filter (
          n:
          let
            nl = lib.stringLength n;
          in
          lib.hasPrefix initial n && nl >= len - 2 && nl <= len + 2
        ) knownNames;
        scored = lib.sort (x: y: x.d < y.d || (x.d == y.d && x.p > y.p)) (
          map (n: {
            # nixpkgs exposes these under `lib.strings` only.
            d = lib.strings.levenshtein name n;
            p = lib.strings.commonPrefixLength name n;
            name = n;
          }) candidates
        );
        # `d < len` keeps a 1-2 character query from "matching" everything.
        close = builtins.filter (s: s.d <= 3 && s.d < len) scored;
      in
      map (s: s.name) (lib.take 3 close);

  hint =
    name:
    let
      suggestions = nearest name;
    in
    if suggestions == [ ] then "" else "\n  Did you mean: ${lib.concatStringsSep ", " suggestions}?";

  # Resolve one name to a derivation, or throw an actionable error.
  resolve =
    name:
    if has name then
      pkgs.rPackages.${name}
    else if has (underscored name) then
      pkgs.rPackages.${underscored name}
    else
      throw ''
        opi.rPackages: '${name}' is not in pkgs.rPackages (tried '${name}' and '${underscored name}').${hint name}
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
        opi.rPackages: unknown package(s): ${lib.concatStringsSep ", " missing}.${lib.concatMapStrings hint missing}
        If they are private, add them to the org package set.
        If they are public CRAN packages that are missing or broken, request an override.
      ''
    else
      map resolve names;
in
{
  inherit resolve resolveMany;
}
