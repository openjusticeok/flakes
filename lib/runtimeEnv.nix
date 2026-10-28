# The runtime closure for a shell entry: the org standard R set, then the
# shell's own extras — the same order `mkOpiShell` uses for `buildInputs`, so the
# artifact a process runs and the shell a human works in resolve the same
# packages (invariant 10).
#
# This layer exists because it was missing: `mkRenv` is deliberately generic (R
# plus whatever it is handed), and the module once handed it only the shell's
# extras. A project's `<name>-env` then had no `targets`, no `dplyr` — nothing
# the org promises — while its dev shell had everything. Nothing failed until CI
# tried to run `tar_validate()` in the artifact. `mkRenv` stays generic; this is
# the policy that says what "handed" means for a shell.
{
  pkgs,
  lib,
  rPackages ? [],
  env ? {},
}: let
  base = import ./baseEnvironment.nix {inherit pkgs;};
in
  import ./mkRenv.nix {
    inherit pkgs lib;
    rPackages = base.rPackages ++ rPackages;
    inherit env;
  }
