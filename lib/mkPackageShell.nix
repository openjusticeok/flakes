# A dev shell for one org package repo, built on the opi base shell contract.
#
# Package repos cannot import this file themselves: `opi -> <pkg> -> opi` is a
# flake input cycle. So the org repo -- which already has every package as an
# input -- owns the supported dev environment and exposes it as
# `devShells.<pkg>-dev` (see shells/private.nix). Each package repo keeps only a
# minimal standalone `nix develop` shell for working on it outside opi.
#
# The package derivation carries its runtime deps as propagatedBuildInputs, so
# R's setup hook puts both the package and its deps on R_LIBS_SITE; nothing here
# has to enumerate them.
{
  pkgs,
  lib,
  base,
  package,
  name ? "${package.name}-dev",
}:
# shellEnv/shellHook passthru are the opi base shell's contract with this
# helper (see shells/base.nix). A base missing them is not an opi base shell;
# fail loudly rather than silently dropping R_HOME/FONTCONFIG_FILE and the base
# setup hook.
lib.throwIf (!(base ? shellEnv && base ? shellHook))
"opi.devShells.${name}: base is not an opi base shell (missing shellEnv/shellHook passthru)"
(pkgs.mkShell {
  inherit name;

  # base contributes its buildInputs (R, toolchain, standard R packages), its
  # shellHook, and its env. mkShell concatenates inputs' shellHooks ahead of
  # ours, so base.shellHook must NOT be prepended here or it runs twice.
  inputsFrom = [base];

  buildInputs = [package];

  env = base.shellEnv;
})
