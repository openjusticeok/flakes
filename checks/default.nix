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
    ...
  }: let
    rp = import ../lib/rPackages.nix {inherit pkgs lib;};

    check = name: cond: msg:
      if cond
      then pkgs.runCommand "check-${name}" {} "touch $out"
      else throw "check-${name}: ${msg}";

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
    };
  };
}
