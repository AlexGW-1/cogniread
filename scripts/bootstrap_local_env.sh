#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

copy_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ -f "$dst" ]]; then
    echo "Skip (exists): $dst"
    return
  fi
  if [[ ! -f "$src" ]]; then
    echo "Missing template: $src"
    return
  fi
  cp "$src" "$dst"
  echo "Created: $dst"
}

copy_if_missing "$ROOT_DIR/infra/compose/.env.example" "$ROOT_DIR/infra/compose/.env"
copy_if_missing "$ROOT_DIR/infra/gcp/prod.env.example" "$ROOT_DIR/infra/gcp/prod.env"
copy_if_missing "$ROOT_DIR/docs/examples/sync_oauth.example.json" "$ROOT_DIR/assets/sync_oauth.json"

echo "Done. Fill secrets in created files."
