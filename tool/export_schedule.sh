#!/usr/bin/env bash
# Read-only LoveHub schedule export. Writes schedule.json, schedule.ics, and
# README.md. This script does not write to Firestore and does not print tokens.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCK="${LOVEHUB_SCHEDULE_EXPORT_LOCK_FILE:-/tmp/lovehub-schedule-export.lock}"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "schedule export: another run holds ${LOCK}; leaving it to finish" >&2
  exit 0
fi

DART_BIN="${DART:-}"
if [[ -z "$DART_BIN" ]]; then
  DART_BIN="$(command -v dart || true)"
fi
if [[ -z "$DART_BIN" ]]; then
  echo "schedule export: dart was not found. Set DART to the Flutter dart binary." >&2
  exit 1
fi

exec "$DART_BIN" run tool/export_schedule.dart "$@"
