# Non-R package pins/fixes for system/deploy stability.
#
# Add overrides here when a package in the pinned rstats-on-nix revision needs a
# backport, version pin, or patch. These apply to dev shells and deployments
# alike. Example:
#
#   final: prev: {
#     someLib = prev.someLib.overrideAttrs (old: {
#       patches = (old.patches or [ ]) ++ [ ./patches/some-lib-fix.patch ];
#     });
#   }
final: prev: {
  # nixpkgs' jarl 0.6.0-unstable fails its check phase on aarch64-darwin: the
  # test suite's expected-output regex rejects the temporary directory paths a
  # nix build produces, so `nix develop` aborts while building the tool. The
  # binary itself is healthy on macOS (issue #34), so skip the check there and
  # keep it everywhere else. Drop this once nixpkgs carries the upstream fix.
  jarl =
    if prev.stdenv.hostPlatform.isDarwin
    then
      prev.jarl.overrideAttrs (_: {
        doCheck = false;
      })
    else prev.jarl;
}
