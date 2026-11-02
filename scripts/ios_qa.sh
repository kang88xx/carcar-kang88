#!/usr/bin/env bash
# Runs real Vision + UI integration on an available iOS Simulator, never a phone.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS with Xcode and iOS Simulator is required.' >&2; exit 2; }
command -v flutter >/dev/null
command -v xcrun >/dev/null
export CARCAR_QA_ARTIFACT_DIR="${CARCAR_QA_ARTIFACT_DIR:-$PWD/build/ios-runtime-qa}"
mkdir -p "$CARCAR_QA_ARTIFACT_DIR"
xcrun simctl list devices available --json > "$CARCAR_QA_ARTIFACT_DIR/simulators.json"
qa_selection=$(python3 - "$CARCAR_QA_ARTIFACT_DIR/simulators.json" "${CARCAR_QA_DEVICE:-}" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    catalog = json.load(source)
choices = [(runtime, device) for runtime, devices in catalog['devices'].items()
           if '.iOS-' in runtime for device in devices
           if device.get('isAvailable') and device['name'].startswith('iPhone')]
if sys.argv[2]:
    choices = [(runtime, device) for runtime, device in choices if device['udid'] == sys.argv[2]]
if not choices:
    raise SystemExit('No matching available iPhone Simulator; install an iOS runtime in Xcode.')
# Prefer a running simulator, then the newest installed iOS runtime.
runtime, device = max(choices, key=lambda item: (
    item[1]['state'] == 'Booted', tuple(int(v) for v in item[0].split('.iOS-')[1].split('-')), item[1]['name']))
print(device['udid'], device['state'], runtime)
PY
)
read -r qa_udid qa_state qa_runtime <<< "$qa_selection"
printf 'Simulator: %s (%s, %s)\n' "$qa_udid" "$qa_state" "$qa_runtime" | tee "$CARCAR_QA_ARTIFACT_DIR/device.txt"
qa_started=false
cleanup() {
  if [[ "$qa_started" == true ]]; then xcrun simctl shutdown "$qa_udid" || true; fi
}
trap cleanup EXIT
if [[ "$qa_state" != Booted ]]; then
  xcrun simctl boot "$qa_udid"
  qa_started=true
fi
xcrun simctl bootstatus "$qa_udid" -b
flutter drive --no-pub --driver=test_driver/native_qa_driver.dart \
  --target=integration_test/native_app_test.dart --device-id="$qa_udid" \
  --dart-define=SUPABASE_URL= --dart-define=SUPABASE_PUBLISHABLE_KEY= \
  2>&1 | tee "$CARCAR_QA_ARTIFACT_DIR/integration.log"
# Flutter drive removes the installed app during cleanup. Inspect the Simulator
# bundle produced by the successful build above instead.
qa_app_path="build/ios/iphonesimulator/Runner.app"
test -d "$qa_app_path"
test -s "$qa_app_path/Info.plist"
python3 scripts/check_ios_deployment.py "$qa_app_path" > "$CARCAR_QA_ARTIFACT_DIR/deployment-targets.json"
python3 - "$qa_app_path/Info.plist" "$CARCAR_QA_ARTIFACT_DIR/native-capabilities.json" <<'PY_CAPABILITIES'
import json, plistlib, sys
from pathlib import Path

with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
if info.get('CFBundleIdentifier') != 'com.kang88.carcar':
    raise SystemExit('Unexpected app bundle in Simulator capability inspection.')
families = info.get('UIDeviceFamily', [])
if 1 not in families:
    raise SystemExit('The built Simulator app must support iPhone.')
names = {'AppIcon' + color for color in
         ['Blue', 'Black', 'White', 'Gold', 'Mint', 'Purple', 'Red', 'Gray']}
names |= {'AppIconFloorF' + str(i) for i in range(1, 6)}
names |= {'AppIconFloorB' + str(i) for i in range(1, 7)}
icon_sets = {}
for family, key in [(1, 'CFBundleIcons'), (2, 'CFBundleIcons~ipad')]:
    if family not in families:
        continue
    alternate = info.get(key, {}).get('CFBundleAlternateIcons', {})
    if not names.issubset(alternate):
        raise SystemExit(f'{key}: all nineteen alternate icons must be packaged.')
    for name in names:
        icon = alternate[name]
        if not isinstance(icon, dict) or icon.get('CFBundleIconName') != name:
            raise SystemExit(f'{key}: alternate icon asset mapping is invalid.')
    icon_sets[key] = sorted(names)
if info.get('CarcarAPNsEnvironment') != 'development':
    raise SystemExit('Simulator debug build must resolve the APNs development configuration.')
report = {
    'bundleId': info['CFBundleIdentifier'],
    'deviceFamilies': families,
    'alternateIconSets': icon_sets,
    'apnsBuildEnvironment': info['CarcarAPNsEnvironment'],
    'source': 'builtSimulatorApp',
    'actualIconChangeTested': False,
    'pushDeliveryTested': False,
}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + '\n')
print('Built Simulator app packaging passed: alternate icons and APNs build configuration.')
PY_CAPABILITIES
test -s "$CARCAR_QA_ARTIFACT_DIR/native-home.png"
test -s "$CARCAR_QA_ARTIFACT_DIR/native-history.png"
for qa_capture in native-widget-guide native-widget-settings native-settings-top native-launcher-floor native-settings-notifications native-settings-account native-profile-editor; do
  test -s "$CARCAR_QA_ARTIFACT_DIR/$qa_capture.png"
done
printf 'Native iOS integration passed; repository reopen is not a process-restart test.\n'
