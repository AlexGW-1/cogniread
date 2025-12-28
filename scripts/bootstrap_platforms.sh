#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Generate platform folders only if they don't exist
need_create=false
for d in android ios macos web; do
  if [ ! -d "$d" ]; then
    need_create=true
  fi
done

if [ "$need_create" = true ]; then
  echo "Generating platform folders with: flutter create ..."
  flutter create . --platforms=android,ios,macos,web --org com.cogniread
else
  echo "Platform folders already exist. Skipping flutter create."
fi

flutter pub get
echo "Done."
