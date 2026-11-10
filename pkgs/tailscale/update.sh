#!/usr/bin/env bash
# Bump hashes.json to the latest stable Tailscale release. Needs curl, jq and
# nix. Each tarball is checked against the .sha256 file upstream publishes
# beside it (the bare hash, with no file name, so `sums` does not apply).
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source-path=SCRIPTDIR source=../../lib/update.sh
. ../../lib/update.sh

base=https://pkgs.tailscale.com/stable
# The stable track's current tarball version.
version="$(curl -fsSL "$base/?mode=json" | jq -er .TarballsVersion)"
check_version tailscale "$version"
skip_if_current tailscale "$version"

declare -A arches=([aarch64-linux]=arm64 [x86_64-linux]=amd64)
hashes='{}'
for system in "${!arches[@]}"; do
  url="$base/tailscale_${version}_${arches[$system]}.tgz"
  want="$(curl -fsSL "$url.sha256" | tr -d '[:space:]')"
  [[ $want =~ ^[0-9a-fA-F]{64}$ ]] || { echo "$url: no sha256 upstream" >&2; exit 1; }
  hash="$(prefetch "$url" "$want")"
  hashes="$(jq --arg s "$system" --arg h "$hash" '. + {($s): $h}' <<<"$hashes")"
done

jq -n --arg v "$version" --argjson h "$hashes" \
  '{version: $v, hashes: ($h | to_entries | sort_by(.key) | from_entries)}' > hashes.json
echo "tailscale: $current -> $version"
