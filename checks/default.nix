# Flake checks.
#
# We only build lightweight checks here. `nix flake check` evaluates every
# devShell but does not build it, so devShells (and the heavy GUI bits they carry
# for users, e.g. positron-bin) are eval-checked without being pulled into CI.
{ ... }:
{
  perSystem = { pkgs, lib, ... }:
    let
      rp = import ../lib/rPackages.nix { inherit pkgs lib; };

      resolverSanity =
        (builtins.tryEval (rp.resolve "dplyr")).success
        && (builtins.tryEval (rp.resolve "ggplot2")).success
        && (builtins.tryEval (rp.resolve "data.table")).success;
    in
    {
      checks = {
        # Fails evaluation if the CRAN-name resolver breaks (including the
        # dot -> underscore mapping).
        opi-rpackages-resolver =
          if resolverSanity then
            pkgs.runCommand "check-opi-rpackages-resolver" { } "touch $out"
          else
            throw "opi.rPackages resolver sanity check failed";
      };
    };
}
