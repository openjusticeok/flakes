[
  # The org's private R packages, by name.
  #
  # This is the single source of truth for *which* ones exist, and it is
  # deliberately input-free: consumers reach these packages through
  # pkgs.rPackages (overlays/default.nix injects them), so nothing downstream of
  # a shell needs the org's own flake inputs to be able to name them.
  # lib/orgPackages.nix pairs these names with the derivations and owns the
  # stale-lock guard.
  "ojodb"
  "ojoregex"
  "ojothemes"
  "ojoutils"
]
