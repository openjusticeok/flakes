#!/usr/bin/env bash
set -euo pipefail

TOOL="$1"
OWNER="$2"
REPO="$3"
TAG_PREFIX="$4"

TOOLS="base/tools.json"

CURRENT_VERSION="$(jq -r --arg tool "$TOOL" '.[$tool].version' "$TOOLS")"
LATEST_TAG="$(gh api "repos/$OWNER/$REPO/releases/latest" --jq '.tag_name')"
LATEST_VERSION="${LATEST_TAG#$TAG_PREFIX}"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
  echo "up_to_date=true"
  exit 0
fi

echo "current_version=$CURRENT_VERSION"
echo "latest_version=$LATEST_VERSION"
echo "latest_tag=$LATEST_TAG"
echo "up_to_date=false"

# Compute the unpacked source hash expected by fetchFromGitHub.
SRC_HASH_BASE32="$(nix-prefetch-url --unpack "https://github.com/$OWNER/$REPO/archive/refs/tags/$LATEST_TAG.tar.gz")"
SRC_HASH="$(nix-hash --to-sri --type sha256 "$SRC_HASH_BASE32")"

# Update version, hash, and a placeholder cargo hash.
jq --arg tool "$TOOL" \
   --arg version "$LATEST_VERSION" \
   --arg hash "$SRC_HASH" \
   --arg cargo_hash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" \
   '.[$tool].version = $version | .[$tool].hash = $hash | .[$tool].cargo_hash = $cargo_hash' \
   "$TOOLS" > "$TOOLS.tmp"
mv "$TOOLS.tmp" "$TOOLS"

# Build to discover the correct cargo hash.
SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
if ! nix build "./base#devShells.$SYSTEM.default" 2>/tmp/build.log; then
  :
fi

CARGO_HASH="$(grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' /tmp/build.log | head -1 || true)"

if [ -z "$CARGO_HASH" ]; then
  echo "Failed to extract cargoHash from build log" >&2
  cat /tmp/build.log >&2
  exit 1
fi

# Update the real cargo hash.
jq --arg tool "$TOOL" \
   --arg cargo_hash "$CARGO_HASH" \
   '.[$tool].cargo_hash = $cargo_hash' \
   "$TOOLS" > "$TOOLS.tmp"
mv "$TOOLS.tmp" "$TOOLS"

# Final verification.
nix flake check
nix build "./base#devShells.$SYSTEM.default"
