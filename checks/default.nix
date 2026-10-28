# Flake checks.
#
# These are eval-time assertions, not builds. `nix flake check` evaluates every
# devShell but builds nothing, so the failures worth catching here are the ones
# that happen during evaluation: an R name the resolver cannot find, a stale
# org-package lock, a base shell that lost its contract. Each check is a trivial
# derivation gated on an assertion, so a red build means the assertion failed —
# not that some other build produced $out.
#
# What is deliberately not here:
#
#   - Anything that builds an R package. Minutes to hours times three platforms;
#     that belongs behind the Cachix push (P2), not in an eval check.
#   - Anything that needs a second `nix` process to evaluate another flake
#     (examples/, templates/, the module fixtures under checks/fixtures/). Those
#     are covered by scripts/check-consumers, which CI runs.
{...}: {
  perSystem = {
    pkgs,
    lib,
    config,
    ...
  }: let
    rp = import ../lib/rPackages.nix {inherit pkgs lib;};

    check = name: cond: msg:
      if cond
      then pkgs.runCommand "check-${name}" {} "touch $out"
      else throw "check-${name}: ${msg}";

    # Every opi shell is built by lib/mkOpiShell.nix, so asserting the contract
    # on the base shell asserts it for project shells and `<pkg>-dev` shells too
    # (scripts/check-consumers proves the composition actually reaches a project).
    # mkShell lifts `env` entries to attributes, so this is readable at eval time.
    baseShell = config.devShells.base;

    arrowInBase =
      builtins.filter (
        p: builtins.match "r-arrow-.*" (p.name or "") != null
      )
      baseShell.buildInputs;

    # The runtime closure for the org environment, composed exactly as
    # `packages.base-env` is. Its claim is that dev-only weight cannot be in it
    # (invariant 8 by construction), so the checks assert absence rather than a
    # shorter list.
    baseEnv = import ../lib/mkRenv.nix {
      inherit pkgs lib;
      rPackages = (import ../lib/baseEnvironment.nix {inherit pkgs;}).rPackages;
    };

    inEnv = needle: builtins.any (p: lib.hasInfix needle (p.name or "")) baseEnv.paths;

    envArrowCount = builtins.length (
      builtins.filter (
        p: builtins.match "r-arrow-.*" (p.name or "") != null
      )
      baseEnv.paths
    );

    # A project-shaped shell, composed the way the module composes one (extras
    # on top of the org environment, same pkgs). S1's acceptance criterion is
    # that this path carries exactly one `arrow` — the patched one — and still
    # has the org env and the project's own overrides.
    projectShell = import ../lib/mkOpiShell.nix {
      inherit pkgs lib;
      name = "check-opi-project-shell";
      rPackages = ["sf" "data.table"];
      packages = [pkgs.jq];
      env.FIXTURE_PROJECT = "1";
    };

    arrowInProject =
      builtins.filter (
        p: builtins.match "r-arrow-.*" (p.name or "") != null
      )
      projectShell.buildInputs;

    # A lock missing an org package is the signature of a stale opi input in a
    # consuming flake; lib/orgPackages.nix must throw rather than ship a base
    # shell without the org packages.
    orgPackagesWithoutInputs = import ../lib/orgPackages.nix {
      inputs = {};
      system = "x86_64-linux";
      inherit lib;
    };
  in {
    checks = {
      # The resolver maps CRAN names onto pkgs.rPackages, including the dot ->
      # underscore spelling, and finds the org's own packages — which only
      # resolve if overlays/default.nix is applied to this repo's pkgs.
      opi-resolver-resolves =
        check "opi-resolver-resolves"
        (builtins.all (n: (builtins.tryEval (rp.resolve n)).success) [
          "dplyr"
          "ggplot2"
          "data.table"
          "arrow"
          "ojodb"
        ])
        "a known R package name failed to resolve (dot -> underscore mapping, or the version-of-record overlay, is broken)";

      # PLAN invariant #4: unknown names throw rather than silently skipping.
      opi-resolver-unknown-throws =
        check "opi-resolver-unknown-throws"
        (!(builtins.tryEval (rp.resolveMany ["dplry"])).success)
        "resolveMany accepted an unknown package name";

      # ... and the throw is actionable. This is the part a tryEval-only check
      # misses: a broken hint path once passed `flake check` and only failed on a
      # deliberate typo test.
      opi-resolver-suggests =
        check "opi-resolver-suggests"
        (builtins.elem "dplyr" (rp.nearest "dplry") && lib.hasInfix "Did you mean" (rp.hint "dplry"))
        "the unknown-name suggestion did not offer 'dplyr' for 'dplry'";

      opi-orgpackages-stale-lock-throws =
        check "opi-orgpackages-stale-lock-throws"
        (!(builtins.tryEval (lib.isAttrs orgPackagesWithoutInputs)).success)
        "orgPackages accepted inputs that do not carry the org package flakes";

      # The runtime closure carries nothing a process does not need. This is
      # invariant 8 as an assertion rather than a promise: if someone adds a
      # dev-only package to the runtime path, this fails by name.
      opi-env-runtime-only =
        check "opi-env-runtime-only"
        (
          !(inEnv "positron")
          && !(inEnv "gcc")
          && !(inEnv "cmake")
          && !(inEnv "cargo")
          && !(inEnv "rustc")
          && !(inEnv "quarto")
          && !(inEnv "postgresql")
          && !(inEnv "duckdb")
          && !(inEnv "google-cloud-sdk")
          && envArrowCount == 1
        )
        "the runtime closure picked up dev-only weight (Positron, a compiler, a CLI tool, or a second arrow) — it should be R + rPackages + env only";

      # Same env as the shell (invariant 10) plus an explicit R_LIBS_SITE, since
      # there is no R setup hook to compute one for a process.
      opi-env-contract =
        check "opi-env-contract"
        (
          baseEnv.env.R_HOME
          == "${pkgs.R}/lib/R"
          && baseEnv.env.R_LIBS_USER == "${pkgs.emptyDirectory}"
          && baseEnv.env.R_ENVIRON_USER == "/dev/null"
          && baseEnv.env.R_MAKEVARS_USER == "/dev/null"
          && lib.hasPrefix "/nix/store/" (toString (baseEnv.env.FONTCONFIG_FILE or null))
          && builtins.length (lib.splitString ":" baseEnv.R_LIBS_SITE) == builtins.length baseEnv.resolved
        )
        "the runtime closure's env diverged from the shell's, or R_LIBS_SITE does not list every resolved package";

      # The shell contract: R_HOME, the three immutability pins, the fontconfig
      # path, and the QUARTO_R export. Losing any of these is silent otherwise —
      # the shell still opens, R just behaves differently than documented.
      opi-shell-contract =
        check "opi-shell-contract"
        (
          baseShell.R_HOME
          == "${pkgs.R}/lib/R"
          && baseShell.R_LIBS_USER == "${pkgs.emptyDirectory}"
          && baseShell.R_ENVIRON_USER == "/dev/null"
          && baseShell.R_MAKEVARS_USER == "/dev/null"
          # FONTCONFIG_FILE is the makeFontsConf derivation; mkShell keeps it as
          # an attrset, so compare its store path rather than its type.
          && lib.hasPrefix "/nix/store/" (toString (baseShell.FONTCONFIG_FILE or null))
          && lib.hasInfix "QUARTO_R" baseShell.shellHook
        )
        "the base shell lost part of its contract (R_HOME, the immutability pins, FONTCONFIG_FILE, or the QUARTO_R export)";

      # One `arrow`, from the package set the shells are built from. Zero means
      # the overlay stopped injecting it; more than one is the mixed-pkgs bug
      # (F1) coming back — a project would get an unpatched arrow on R_LIBS_SITE.
      opi-shell-one-arrow =
        check "opi-shell-one-arrow"
        (
          builtins.length arrowInBase
          == 1
          && builtins.any (p: p.drvPath == pkgs.rPackages.arrow.drvPath) baseShell.buildInputs
        )
        "the base shell carries zero or several `arrow` derivations — a second package set is leaking in";

      # The project path (org environment + extras) keeps the same properties:
      # one arrow, the org env intact, the project's own env applied on top.
      opi-shell-project-compose =
        check "opi-shell-project-compose"
        (
          builtins.length arrowInProject
          == 1
          && builtins.any (p: p.drvPath == pkgs.rPackages.arrow.drvPath) projectShell.buildInputs
          && projectShell.R_HOME == "${pkgs.R}/lib/R"
          && projectShell.FIXTURE_PROJECT == "1"
        )
        "a project shell did not compose as org environment + extras (missing arrow, second package set, lost R_HOME, or an env override was dropped)";
    };
  };
}
