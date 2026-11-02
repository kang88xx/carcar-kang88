#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
classes="$repo_root/build/app/tmp/kotlin-classes/debug"
test -f "$classes/com/kang88/carcar/PushRegistrationGate.class" || { echo 'Build the debug APK first.'; exit 1; }
stdlib="$(find "${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib" -name 'kotlin-stdlib-*.jar' | sort | tail -1)"
test -n "$stdlib"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
javac -cp "$classes:$stdlib" -d "$work_dir" "$repo_root/android/tests/PushRegistrationGateCheck.java"
java -cp "$work_dir:$classes:$stdlib" PushRegistrationGateCheck
