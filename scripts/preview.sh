#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f build/web/index.html ]; then
  echo '먼저 flutter build web을 실행해 주세요.' >&2
  exit 1
fi
exec python3 -m http.server 4173 --bind 0.0.0.0 --directory build/web
