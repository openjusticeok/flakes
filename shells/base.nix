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
  };
}
