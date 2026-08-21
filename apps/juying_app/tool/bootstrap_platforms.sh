#!/usr/bin/env sh
set -eu

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK not found. Install Flutter stable and add flutter to PATH.' >&2
  exit 1
fi

APP_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$APP_ROOT"
flutter create --platforms=android,ios,windows,linux --project-name juying --org com.flytech .
flutter pub get
flutter analyze
flutter test
