#!/usr/bin/env bash
# Bounded C2 rota reconcile. Default is dry-run; pass --apply to write.
# See docs/c2-rota-reconcile.md. This script does not print the feed token.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCK="${C2_ROTA_LOCK_FILE:-/tmp/lovehub-c2-rota-reconcile.lock}"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "c2 rota reconcile: another run holds ${LOCK}; leaving it to finish" >&2
  exit 0
fi

DART_BIN="${DART:-}"
if [[ -z "$DART_BIN" ]]; then
  DART_BIN="$(command -v dart || true)"
fi
if [[ -z "$DART_BIN" ]]; then
  echo "c2 rota reconcile: dart was not found. Set DART to the Flutter dart binary." >&2
  exit 1
fi

exec "$DART_BIN" run tool/reconcile_c2_rota.dart "$@"
