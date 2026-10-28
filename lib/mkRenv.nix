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
#   env       the env attrset for an image's config.env (same values as the shell)
#   rPackages the resolved derivations, for checks and for image layers
{
  pkgs,
  lib,
  rPackages ? [],
  env ? {},
}: let
  rp = import ./rPackages.nix {inherit pkgs lib;};
  rShellEnv = import ./rShellEnv.nix {inherit pkgs;};

  resolved = rp.resolveMany rPackages;

  # R finds packages through library *directories*, and a nix R package installs
  # into $out/library/<pkg> — so the site list is one entry per package. A dev
  # shell gets the same list from R's setup hook; here there is no hook to run.
  rLibsSite = lib.concatMapStringsSep ":" (p: "${p}/library") resolved;

  shellEnv = rShellEnv // {R_LIBS_SITE = rLibsSite;} // env;

  exports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") shellEnv
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
  inherit (shellEnv) R_LIBS_SITE;

  # What an image copies and what a closure measurement covers.
  paths = [pkgs.R] ++ resolved;

  env = shellEnv;
}
