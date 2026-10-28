# The opi base shell: the org environment with nothing added. Exposed as
# devShells.<system>.base, which is what `nix develop .#base` runs. A project that
# wants the org environment without a module entry uses
# `opi.devShells.<system>.base` directly.
#
# Every other opi shell is this plus extras — lib/mkOpiShell.nix is the single
# composition path, so this file is deliberately just a call.
{...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    devShells.base = import ../lib/mkOpiShell.nix {
      inherit pkgs lib;
      name = "opi-base-shell";
    };

    # The same org environment, materialized for a process instead of a human:
    # R + the standard R set + the shell env, with no Positron, compilers or CLI
    # tools (they were never inputs).
    # `nix run .#base-env -- -e '…'` (ARCHITECTURE §3, §10).
    packages.base-env = (import ../lib/runtimeEnv.nix {inherit pkgs lib;}).package;
  };
}
