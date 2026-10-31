#!/usr/bin/env bash
# After the release workflow has built a tag's ZIP: put it in the Worker's KV (tools-hub-api), where installs and
# Cập nhật download it with the app password (the code repo is private). Needs gh and wrangler signed in.
#   scripts/publish-release.sh v2.0.56
set -euo pipefail
tag="${1:?Usage: scripts/publish-release.sh vX.Y.Z}"
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh release download "$tag" --repo hoangpham2263/tools-hub-app --pattern tools-hub.zip --dir "$tmp"
cd "$here/worker"
# The ZIP first, the version last: an update never sees a version whose ZIP is not there yet.
npx wrangler kv key put app:zip --path "$tmp/tools-hub.zip" --binding STORE --remote
npx wrangler kv key put app:version "$tag" --binding STORE --remote
echo "Published $tag ($(wc -c < "$tmp/tools-hub.zip") bytes)"
