# The one way an opi shell is built.
#
# Base shell, project shells, and per-package dev shells are all this function
# with different extras. There is exactly one composition path — the org
# environment (lib/baseEnvironment.nix) plus whatever the caller adds — so
# nothing inherits from anything else: no `inputsFrom`, no `passthru` contract to
# keep in sync, no "don't prepend the shellHook or it runs twice" footgun.
#
# `pkgs` must already carry the version-of-record overlay. The module owns that
# instantiation (modules/flake/opi.nix), so `packages` and `rPackages` always
# resolve against the same package set — a project cannot get an unpatched
# `arrow` from one set and a patched one from another.
#
# `rPackages` are CRAN names, resolved against pkgs.rPackages and added to
# buildInputs so R's setup hook puts them on R_LIBS_SITE (no rWrapper; Positron's
# in-process `ark` cannot parse the wrapper shim).
{
  pkgs,
  lib,
  name ? "opi-shell",
  rPackages ? [],
  # Nix packages that must be on the include/link path, in addition to the org
  # environment and the resolved R packages.
  buildInputs ? [],
  # Tools that only need to be on PATH.
  packages ? [],
  # Extra environment variables; these win over the org defaults below.
  env ? {},
  # Runs after the readiness hook.
  shellHook ? "",
}: let
  base = import ./baseEnvironment.nix {inherit pkgs;};

  rp = import ./rPackages.nix {inherit pkgs lib;};

  fontsConf = pkgs.makeFontsConf {fontDirectories = [pkgs.source-sans];};

  # Env vars exported to every opi shell, base and project alike. Adding one
  # here propagates everywhere; projects override through
  # `opi.shells.<name>.env`, never in a home directory.
  shellEnv = {
    R_HOME = "${pkgs.R}/lib/R";
    FONTCONFIG_FILE = fontsConf;

    # Strict immutability: point R's user library at a read-only empty store
    # path so ad-hoc install.packages() cannot persist. Packages come from the
    # shell's rPackages (via R's setup hook -> R_LIBS_SITE).
    R_LIBS_USER = "${pkgs.emptyDirectory}";

    # R also sources machine-wide user config: ~/.Renviron (which can reset
    # R_LIBS_*/R_PROFILE and so defeat the immutability above) and ~/.R/Makevars
    # (which injects CFLAGS/LDFLAGS/BLAS into every local source compile, e.g.
    # devtools::load_all() on a package with compiled code). Both pin away so a
    # shell behaves identically on every machine.
    R_ENVIRON_USER = "/dev/null";
    R_MAKEVARS_USER = "/dev/null";
  };

  readinessHook = ''
    echo "opi shell ready: ${name}"
    echo "R: $(which R)"
    echo "R_HOME: $R_HOME"
    echo "air: $(air --version)"
    echo "arf: $(arf --version)"
    echo "jarl: $(jarl --version)"
    echo "quarto: $(quarto --version)"

    # Pin quarto's R explicitly (quarto's rWrapper override is null, so it
    # would otherwise discover R from PATH).
    export QUARTO_R="$(which R)"
  '';
in
  pkgs.mkShell {
    inherit name;

    # R packages go through buildInputs so R's setup hook populates
    # R_LIBS_SITE; the org environment contributes R itself and its toolchain.
    buildInputs =
      base.buildInputs
      ++ rp.resolveMany (base.rPackages ++ rPackages)
      ++ buildInputs;

    packages = base.packages ++ packages;

    env = shellEnv // env;

    shellHook = readinessHook + shellHook;
  }
