#!/usr/bin/env bash
# Bump hashes.json to the latest Cloudflare WARP release. Needs curl, jq and nix.
# The version is the one Cloudflare's apt repository lists for Ubuntu noble, the
# builds the package uses, and each Linux download must match the sha256 that
# index lists. The macOS installer has no upstream checksum: it is pinned by the
# hash of the download, and only when "macos/ga" (the latest GA installer) is
# the same version, so all three systems stay on one version.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source-path=SCRIPTDIR source=../../lib/update.sh
. ../../lib/update.sh

repo=https://pkg.cloudflareclient.com
download=https://downloads.cloudflareclient.com/v1/download

# newest ARCH: "VERSION SHA256" of the newest cloudflare-warp in the noble apt
# index for ARCH (amd64, arm64).
newest() {
  curl -fsSL "$repo/dists/noble/main/binary-$1/Packages" | awk -v RS= -F'\n' '
    {
      pkg = 0; v = ""; s = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "Package: cloudflare-warp") pkg = 1
        else if ($i ~ /^Version: /) v = substr($i, 10)
        else if ($i ~ /^SHA256: /) s = substr($i, 9)
      }
      if (pkg && v != "" && s != "") print v, s
    }' | sort -V | tail -n1
}

read -r version sha_amd64 <<<"$(newest amd64)"
read -r version_arm64 sha_arm64 <<<"$(newest arm64)"
[ -n "${version:-}" ] && [ -n "${version_arm64:-}" ] ||
  { echo "cloudflare-warp: no release in the apt index" >&2; exit 1; }
check_version cloudflare-warp "$version" '^[0-9]+(\.[0-9]+){3}$'
[ "$version" = "$version_arm64" ] ||
  { echo "cloudflare-warp: apt index has $version for amd64 but $version_arm64 for arm64; skipping"; exit 0; }
skip_if_current cloudflare-warp "$version"

# The macOS installer for the latest GA release redirects to its versioned URL.
macos="$(curl -fsSI "$download/macos/ga" | tr -d '\r' | awk 'tolower($1) == "location:" { print $2 }')"
macos="${macos##*/}"
[ "$macos" = "$version" ] ||
  { echo "cloudflare-warp: Linux has $version but the macOS installer is ${macos:-unknown}; skipping"; exit 0; }

declare -A paths=(
  [aarch64-darwin]=macos
  [aarch64-linux]=noble-arm
  [x86_64-linux]=noble-intel
)
# Upstream's checksums; none for macOS.
declare -A want=(
  [aarch64-darwin]=""
  [aarch64-linux]="$sha_arm64"
  [x86_64-linux]="$sha_amd64"
)

hashes='{}'
for system in "${!paths[@]}"; do
  hash="$(prefetch "$download/${paths[$system]}/version/$version" "${want[$system]}")"
  hashes="$(jq --arg s "$system" --arg h "$hash" '. + {($s): $h}' <<<"$hashes")"
done

jq -n --arg v "$version" --argjson h "$hashes" \
  '{version: $v, hashes: ($h | to_entries | sort_by(.key) | from_entries)}' > hashes.json
echo "cloudflare-warp: $current -> $version"
