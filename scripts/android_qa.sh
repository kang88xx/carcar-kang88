#!/usr/bin/env bash
# Native UI and OCR test: use an isolated emulator, not a family production phone.
set -euo pipefail
cd "$(dirname "$0")/.."
qa_serial="${CARCAR_QA_DEVICE:?Set CARCAR_QA_DEVICE to the isolated emulator serial}"
if [[ "$qa_serial" != emulator-* ]]; then
  echo 'This suite resets local demo data; only an isolated emulator is accepted.' >&2
  exit 2
fi
command -v flutter >/dev/null
command -v adb >/dev/null
if [[ "$(adb -s "$qa_serial" shell getprop sys.boot_completed | tr -d '\r')" != 1 ]]; then
  echo 'Android emulator has not finished booting.' >&2
  exit 3
fi
mkdir -p docs/qa
timeout 600s flutter test integration_test/native_app_test.dart -d "$qa_serial" --no-pub --reporter expanded 2>&1 | tee docs/qa/android-runtime-tests.txt
# The integration harness saves the real Flutter surface inside the app cache.
adb -s "$qa_serial" exec-out run-as com.kang88.carcar cat cache/carcar-native-home.png > docs/qa/android-runtime-home.png
printf 'Native integration suite passed. Rebuild the ordinary APK before distributing; this run used a test entrypoint.\n'
