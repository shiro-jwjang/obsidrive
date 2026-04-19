#!/bin/bash
# Build + cache-bust + deploy Obsidrive
# Usage: bash scripts/deploy.sh

set -e
cd "$(dirname "$0")/.."

FLUTTER="/home/openclaw/flutter/bin/flutter"
VERSION_TAG="v$(date +%Y%m%d%H%M)"

echo "=== Building Obsidrive ==="
$FLUTTER build web --no-wasm-dry-run --release --no-tree-shake-icons

echo "=== Applying cache-bust tags ($VERSION_TAG) ==="
# Add version to main.dart.js path in flutter_bootstrap.js
sed -i "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?$VERSION_TAG\"|" \
    build/web/flutter_bootstrap.js

# Add version to flutter_bootstrap.js in index.html
sed -i "s|src=\\\"flutter_bootstrap.js\\\"|src=\\\"flutter_bootstrap.js?$VERSION_TAG\\\"|" \
    build/web/index.html

# Add version to font assets in FontManifest.json (bust Cloudflare cache)
sed -i "s|MaterialIcons-Regular.otf|MaterialIcons-Regular.otf?$VERSION_TAG|" \
    build/web/assets/FontManifest.json
sed -i "s|CupertinoIcons.ttf|CupertinoIcons.ttf?$VERSION_TAG|" \
    build/web/assets/FontManifest.json

echo "=== Deploying ==="
docker restart obsidrive-web
sleep 2

echo "=== Verifying ==="
STATUS=$(docker ps --filter name=obsidrive-web --format '{{.Status}}')
echo "Container: $STATUS"

# Quick smoke check
HTTP_CODE=$(python3 -c "
import urllib.request
req = urllib.request.Request('https://obsidrive.indieloca.com/')
req.add_header('User-Agent', 'Mozilla/5.0')
resp = urllib.request.urlopen(req)
print(resp.status)
")
echo "HTTP status: $HTTP_CODE"

echo ""
echo "✅ Deploy complete!"
