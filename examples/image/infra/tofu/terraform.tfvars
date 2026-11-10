# Pinned by `nix run .#dashboard-push`, which rewrites the image_name line to
# <registry>/<image>@sha256:<digest> after pushing. Tofu reads it as
# var.image_name; deploys reference the digest, never a tag (inv 7).
image_name = "us-central1-docker.pkg.dev/EXAMPLE_PROJECT/EXAMPLE_REPO/dashboard:placeholder"
