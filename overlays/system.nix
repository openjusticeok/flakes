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
final: prev: { }
