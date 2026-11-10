# The generic image builder: org conventions over nix2container, and nothing
# ecosystem-specific. It must never learn about R or Rust (ARCHITECTURE §7) —
# the caller hands it `contents` (for R: `mkRenv`'s wrapper, whose closure brings
# R and the packages) and `env` (for R: the runtime env), which is why the same
# builder serves a Rust artifact.
#
# What it adds over nix2container:
#
# - **OCI-cased config keys.** nix2container serialises `config` verbatim into
#   config.json, so `{ entrypoint = …; env = …; }` writes dead `entrypoint`/`env`
#   keys and an image that has no Entrypoint and no Env — the failure is silent
#   until the container will not start. (oscn-rs has exactly this bug.) The
#   `opi-image-config` check asserts the capitalised keys exist.
# - **requiredEnv enforced at boot** (inv 13). A process missing a declared
#   variable exits 78 (EX_CONFIG) instead of failing later, deep inside a query.
# - **Provenance as labels** (inv 14): git revision, flake source hash, and the
#   required-env list, readable from the registry without pulling the image.
# - **Non-root by default.**
{
  pkgs,
  lib,
  nix2container,
  name,
  tag ? null,
  contents ? [],
  env ? {},
  requiredEnv ? [],
  entrypoint,
  cmd ? null,
  user ? "1000:1000",
  workingDir ? null,
  port ? null,
  labels ? {},
  revision ? null,
  source ? null,
}: let
  envList = lib.mapAttrsToList (k: v: "${k}=${toString v}") env;

  # The runtime half of inv 13. The declaration half — that the deploy mounts
  # exactly these names — is the project's tofu; this makes a mismatch loud.
  #
  # Generated per variable and checked without leaving bash (`[` is a builtin),
  # because a container's PATH is not guaranteed: a `printenv`-based guard with
  # no PATH would report *every* declared variable as missing, and with a PATH
  # would trust whatever the base image happens to carry. `''${` is a literal
  # shell `${`; `${v}` is the name, interpolated at build time.
  badEnvNames = builtins.filter (v: builtins.match "[A-Za-z_][A-Za-z0-9_]*" v == null) requiredEnv;

  guardChecks =
    lib.concatMapStrings (v: ''
      if [ -z "''${${v}:-}" ]; then
        missing="$missing ${v}"
      fi
    '')
    requiredEnv;

  guardBody =
    ''
      missing=""
    ''
    + guardChecks
    + ''
      if [ -n "$missing" ]; then
        echo "opi: refusing to start: missing required env:$missing" >&2
        echo "opi: declared by this image and provided at deploy time (Secret Manager / config)." >&2
        exit 78
      fi
      exec "$@"
    '';

  guard =
    if badEnvNames != []
    then throw "mkImage: requiredEnv entries must be valid env var names, got: ${lib.concatStringsSep ", " badEnvNames}"
    else pkgs.writeShellScriptBin "opi-entrypoint" guardBody;

  guarded = requiredEnv != [];

  provenanceLabels =
    lib.optionalAttrs (revision != null) {
      "org.opencontainers.image.revision" = revision;
    }
    // lib.optionalAttrs (source != null) {
      # The flake source hash, which covers flake.lock: the reproducible unit of
      # inv 11 without reading the lockfile at eval time (reading it from a
      # consumer's tree throws when the lock is untracked, which a fixture's
      # always is).
      "org.openjusticeok.source" = source;
    }
    // lib.optionalAttrs guarded {
      "org.openjusticeok.required-env" = lib.concatStringsSep "," requiredEnv;
    }
    // {"org.openjusticeok.builder" = "opi/mkImage";};

  # Capitalised OCI field names, deliberately: see the header.
  config =
    {
      Env = envList;
      Entrypoint =
        if guarded
        then ["/bin/opi-entrypoint"] ++ entrypoint
        else entrypoint;
      User = user;
      Labels = labels // provenanceLabels;
    }
    // lib.optionalAttrs (cmd != null) {Cmd = cmd;}
    // lib.optionalAttrs (workingDir != null) {WorkingDir = workingDir;}
    // lib.optionalAttrs (port != null) {
      ExposedPorts."${toString port}/tcp" = {};
    };

  # copyToRoot entries are flattened to `/`: a store path's contents are unpacked
  # at the image root, and its closure follows at the original store paths. That
  # is the distinction that matters for a runtime — the entrypoint belongs at a
  # stable path, the runtime belongs at the path its own config refers to.
  image = nix2container.buildImage {
    inherit name tag;
    copyToRoot = contents ++ lib.optional guarded guard;
    inherit config;
    meta.description = "opi image ${name}";
  };
in
  image
  // {
    inherit requiredEnv envList;
    # What the image claims about where it came from, exposed so the push helper
    # and a project's tofu can read it (`nix eval .#<n>-image.provenance`) instead
    # of re-deriving it. `null` fields mean "unknown", which a local path build
    # legitimately is.
    provenance = {inherit revision source;};
  }
  // lib.optionalAttrs guarded {inherit guard;}
