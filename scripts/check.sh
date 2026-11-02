#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
