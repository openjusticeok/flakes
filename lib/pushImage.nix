# Build → push → resolve the digest → pin it in the project's tfvars.
#
# This is the org-wide, most valuable piece (ARCHITECTURE §7): every repo that
# deploys a container reimplements it, and each reimplementation fails silently
# in the same three ways. All three are guarded here:
#
# 1. **Tag dedupe.** Cloud Run ignores a template update whose image reference
#    did not change, so re-applying `:latest` reports success and deploys
#    nothing (oscn-rs sat `Ready` and silent for ~1.5 h). A digest cannot be
#    deduped away, so the pin *is* the deploy trigger.
# 2. **Digest lag.** Artifact Registry may not resolve a tag for a few seconds
#    after the push. We poll, then validate the shape of what came back.
# 3. **Ordering.** The workload templates are rendered by `tofu apply`; a
#    migrate job run before it silently executes the *previous* image and
#    reports success. The closing message says so.
#
# A fourth, subtler failure: a `sed` that matches nothing exits 0. If the tfvars
# has no `image_name = …` line, the pin silently does not happen — so it is
# checked before the sed and verified after.
{
  pkgs,
  lib,
  image, # a lib/mkImage.nix result
  flakeAttr, # the flake output holding it, e.g. "default-image"
  tfvars ? "infra/tofu/terraform.tfvars",
  varName ? "image_name",
  migrateJob ? null,
  project ? null,
  region ? null,
}: let
  inherit (image) imageName imageTag;
  target = "${imageName}:${imageTag}";

  migrateHint =
    if migrateJob == null
    then []
    else [
      "  gcloud run jobs execute ${migrateJob}${lib.optionalString (region != null) " --region ${region}"}${lib.optionalString (project != null) " --project ${project}"} --wait"
    ];
in
  pkgs.writeShellScriptBin "opi-push-image" ''
    set -euo pipefail

    # Everything below is relative to the repository that declares the image.
    if [ ! -f ./flake.nix ] || [ ! -f ./${tfvars} ]; then
      echo "opi-push-image: run this from the repository root (expected ./flake.nix and ./${tfvars})." >&2
      exit 1
    fi

    dry_run=0
    case "''${1:-}" in
      --dry-run) dry_run=1 ;;
      "") ;;
      *)
        echo "opi-push-image: unknown argument '$1' (only --dry-run is accepted)." >&2
        exit 2
        ;;
    esac

    echo "target:  ${target}"
    echo "pins:    ${varName} in ./${tfvars}"

    previous=$(grep -E "^[[:space:]]*${varName}[[:space:]]*=" ./${tfvars} || true)
    if [ -z "$previous" ]; then
      # A sed that matches nothing exits 0; that is how a pin silently does not
      # happen. Refuse before doing anything expensive.
      echo "opi-push-image: ./${tfvars} has no '${varName} = …' line to pin." >&2
      exit 1
    fi
    echo "current: $previous"

    if [ "$dry_run" -eq 1 ]; then
      echo
      echo "would push:  ${pkgs.nix}/bin/nix run .#${flakeAttr}.copyToRegistry"
      echo "would pin:   ${varName} = \"${imageName}@sha256:…\""
      exit 0
    fi

    echo
    echo "pushing ${target} …"
    ${pkgs.nix}/bin/nix run .#${flakeAttr}.copyToRegistry

    # A tag can be pushed before Artifact Registry can resolve it by name.
    echo "resolving the digest …"
    digest=""
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      digest=$(${pkgs.google-cloud-sdk}/bin/gcloud artifacts docker images describe \
        "${target}" \
        --format='value(image_summary.digest)' 2>/dev/null || true)
      if [ -n "$digest" ]; then break; fi
      echo "  not visible yet, retrying …"
      sleep 2
    done

    case "$digest" in
      sha256:????????????????????????????????????????????????????????????????) ;;
      "")
        echo "opi-push-image: could not resolve a digest for ${target}." >&2
        echo "  check that you are authenticated for Artifact Registry:" >&2
        echo "  gcloud auth configure-docker ''${target%%/*}" >&2
        exit 1
        ;;
      *)
        echo "opi-push-image: unexpected digest '$digest' for ${target}." >&2
        exit 1
        ;;
    esac

    pinned="${imageName}@$digest"
    echo "pinning $pinned …"
    # Write-then-rename: an interrupted run must not leave a half-written tfvars.
    sed -E "s|^[[:space:]]*${varName}[[:space:]]*=.*|${varName} = \"$pinned\"|" \
      ./${tfvars} > ./${tfvars}.opi-pin.tmp
    mv ./${tfvars}.opi-pin.tmp ./${tfvars}

    if ! grep -qF "$pinned" ./${tfvars}; then
      echo "opi-push-image: the pin did not take effect in ./${tfvars}." >&2
      exit 1
    fi

    echo
    echo "pinned $pinned"
    echo
    echo "next, in this order — the workload templates only reference the new"
    echo "image once tofu has rendered them:"
    echo "  cd $(dirname ./${tfvars}) && tofu apply"
    ${lib.concatStringsSep "\n" migrateHint}
    echo
    echo "then check that the running revision is the one you just pinned:"
    echo "  gcloud run revisions list --service <service>${
      lib.optionalString (region != null) " --region ${region}"
    }${lib.optionalString (project != null) " --project ${project}"}"
  ''
  // {
    meta.mainProgram = "opi-push-image";
    inherit target;
  }
