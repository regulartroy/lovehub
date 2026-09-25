#!/usr/bin/env bash
# Deploy LoveHub web Hosting and stamp Firestore so open browsers pick it up.
#
#   tool/deploy_hosting.sh
#   BUILD_ID=abc123-20260925T120000Z tool/deploy_hosting.sh
#
# BUILD_ID defaults to "<git short sha>-<UTC timestamp>". The same value is
# passed to Flutter as --dart-define=BUILD_ID=... and written to appMeta/web
# after Hosting deploy succeeds. Stamping first would reload tablets onto
# the previous files, and the loop guard would then ignore the real build.
#
# Requires flutter, firebase CLI (`firebase login`), and dart on PATH.
# See docs/web-deploy.md.

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${BUILD_ID:-}" ]]; then
  sha="$(git rev-parse --short HEAD)"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  BUILD_ID="${sha}-${ts}"
fi

echo "Building web with BUILD_ID=${BUILD_ID}"
flutter build web --release --dart-define=BUILD_ID="${BUILD_ID}"

echo "Deploying Hosting target love-hub"
firebase deploy --only hosting:love-hub --project lovehub-26107

echo "Stamping Firestore appMeta/web"
dart run tool/stamp_web_build.dart --build-id "${BUILD_ID}"
