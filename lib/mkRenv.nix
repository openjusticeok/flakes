# The runtime closure: R + the resolved R packages + the org env, and nothing
# else. This is the second materialization of an `opi.shells.<name>` declaration
# (ARCHITECTURE §3): a dev shell is what a human works in, this is what a process
# runs in — a Cloud Run job, an image's contents, or a CI step.
#
# Dev-only weight cannot reach it, and not because a list says so: Positron, the
# compilers and the CLI tools are simply not inputs here (invariant 8 by
# construction, ARCHITECTURE §5 fact 2).
#
#   package   a $out/bin/{R,Rscript} wrapper with the env baked in — `nix run`
#             it directly, e.g. `nix run .#default-env -- -e 'targets::tar_make()'`
#   paths     the store paths to put in an OCI image's copyToRoot
#   env       the env attrset for an image's config.env (same values as the shell,
#             minus R_LIBS_SITE: that is a build-time value produced by R's own
#             setup hook, so it lives in the wrapper. An image therefore runs R
#             through `package`'s bin on PATH, which opi.images sets up.)
#   resolved  the R package derivations, for checks and for image layers
#   rLibsSite the derivation holding the hook's R_LIBS_SITE
{
  pkgs,
  lib,
  rPackages ? [],
  env ? {},
}: let
  rp = import ./rPackages.nix {inherit pkgs lib;};
  rShellEnv = import ./rShellEnv.nix {inherit pkgs;};

  resolved = rp.resolveMany rPackages;

  # R_LIBS_SITE is nixpkgs' answer, not ours: R's setup hook does
  # `addToSearchPath R_LIBS_SITE "$1/library"` for every input *and everything
  # those inputs propagate*. Listing the resolved packages directly is what broke
  # this once — `targets` could not find `R6`, because a propagated dependency is
  # not in the direct list, and nothing failed until something loaded the
  # package. So the value is produced by that hook, in a build, and baked into
  # the wrapper. A dev shell gets the same value from the same hook.
  rLibsSite =
    pkgs.runCommandLocal "opi-r-libs-site" {
      nativeBuildInputs = [pkgs.R] ++ resolved;
    } ''
      printf '%s' "$R_LIBS_SITE" > $out
    '';

  shellEnv = rShellEnv // env;

  # The hook's value first, then the caller's env: an explicit R_LIBS_SITE in
  # `env` still wins, but the default is never a partial list.
  exports = lib.concatStringsSep "\n" (
    [''export R_LIBS_SITE="$(cat ${rLibsSite})"'']
    ++ lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") shellEnv
  );

  wrapper = bin:
    pkgs.writeShellScriptBin bin ''
      ${exports}
      exec ${pkgs.R}/bin/${bin} "$@"
    '';
in {
  package = pkgs.symlinkJoin {
    name = "opi-r-env";
    paths = [(wrapper "R") (wrapper "Rscript")];
    # `nix run .#<name>-env -- -e '…'` runs Rscript with the env applied; use
    # `$out/bin/R` for an interactive session.
    meta.mainProgram = "Rscript";
  };

  inherit resolved;
  inherit rLibsSite;

  # What an image copies and what a closure measurement covers.
  paths = [pkgs.R] ++ resolved;

  env = shellEnv;
}
