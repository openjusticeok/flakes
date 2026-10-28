# The R packages the org ships, by CRAN name.
#
# Two lists, one file:
#
#   standard  every opi shell carries these (see lib/baseEnvironment.nix), and
#             flake.lib.standardRPackages exports them so a project can see what
#             it already has instead of re-listing it
#   org       the org's private packages. Their *derivations* come from their own
#             flakes (lib/orgPackages.nix owns the stale-lock guard); the names
#             live here so naming a package never requires the org's inputs — a
#             consuming project reaches them through pkgs.rPackages
#
# Adding an org package: add the input in flake.nix, add the name below, then
# `nix flake update <name>`.
{
  standard = [
    # tidyverse core
    "dplyr"
    "tidyr"
    "purrr"
    "stringr"
    "tibble"
    "readr"
    "lubridate"
    "forcats"
    "ggplot2"
    # ergonomics, pipelines, reporting
    "fs"
    "glue"
    "here"
    "targets"
    "qs2"
    "rmarkdown"
    "knitr"
    # data I/O + quality
    "readxl"
    "googledrive"
    "pointblank"
    # data platform
    "arrow"
  ];

  org = [
    "ojodb"
    "ojoregex"
    "ojothemes"
    "ojoutils"
  ];
}
