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
qa_watcher_pid=
cleanup() {
  qa_exit=$?
  if [[ "$qa_exit" -ne 0 ]]; then
    # Last-resort capture also covers failures outside the drive watchdog.
    xcrun simctl io "$qa_udid" screenshot "$CARCAR_QA_ARTIFACT_DIR/failure-before-shutdown.png" >/dev/null 2>&1 || true
  fi
  if [[ -n "$qa_watcher_pid" ]]; then
    kill "$qa_watcher_pid" >/dev/null 2>&1 || true
    wait "$qa_watcher_pid" >/dev/null 2>&1 || true
  fi
  if [[ "$qa_started" == true ]]; then xcrun simctl shutdown "$qa_udid" || true; fi
}
trap cleanup EXIT
if [[ "$qa_state" != Booted ]]; then
  xcrun simctl boot "$qa_udid"
  qa_started=true
fi
xcrun simctl bootstatus "$qa_udid" -b
# A separate public XCTest runner acknowledges only the two known icon notices.
# Start it before Flutter launches the real app; it never launches/activates carcar.
qa_watcher_dir="$PWD/build/ios-icon-alert-watcher"
BUNDLE_GEMFILE="$PWD/fastlane/Gemfile" bundle exec ruby scripts/generate_ios_alert_watcher.rb "$qa_watcher_dir"
xcodebuild build-for-testing -project "$qa_watcher_dir/IconAlertWatcher.xcodeproj" \
  -scheme IconAlertWatcher -configuration Debug -destination "platform=iOS Simulator,id=$qa_udid" \
  -derivedDataPath "$qa_watcher_dir/DerivedData" CODE_SIGNING_ALLOWED=NO \
  > "$CARCAR_QA_ARTIFACT_DIR/icon-watcher-build.log" 2>&1
xcodebuild test-without-building -project "$qa_watcher_dir/IconAlertWatcher.xcodeproj" \
  -scheme IconAlertWatcher -configuration Debug -destination "platform=iOS Simulator,id=$qa_udid" \
  -derivedDataPath "$qa_watcher_dir/DerivedData" -resultBundlePath "$CARCAR_QA_ARTIFACT_DIR/icon-alerts.xcresult" \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  > "$CARCAR_QA_ARTIFACT_DIR/icon-watcher.log" 2>&1 &
qa_watcher_pid=$!
for qa_ready_attempt in {1..120}; do
  if grep -q '\[CARCAR_ICON_WATCHER\] ready' "$CARCAR_QA_ARTIFACT_DIR/icon-watcher.log"; then break; fi
  kill -0 "$qa_watcher_pid" 2>/dev/null || { echo 'Icon alert watcher exited before readiness.' >&2; exit 1; }
  sleep 1
done
grep -q '\[CARCAR_ICON_WATCHER\] ready' "$CARCAR_QA_ARTIFACT_DIR/icon-watcher.log" || { echo 'Icon alert watcher did not become ready.' >&2; exit 1; }
# The host watchdog remains active when a native modal prevents Flutter frames.
# Capture before terminating drive, because its cleanup uninstalls the app.
python3 - "$qa_udid" "$CARCAR_QA_ARTIFACT_DIR" <<'PY_DRIVE'
import json, os, selectors, signal, subprocess, sys, time
from pathlib import Path
udid, directory = sys.argv[1:]
out = Path(directory)

def capture(label):
    try:
        subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(out / (label + '.png'))],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=12)
    except (OSError, subprocess.TimeoutExpired):
        pass

def diagnostics():
    # Metadata only; unified-log eventMessage can contain URLs or user data.
    try:
        result = subprocess.run(['xcrun', 'simctl', 'spawn', udid, 'log', 'show',
            '--last', '2m', '--style', 'json', '--predicate',
            'process == "SpringBoard" OR process == "backboardd"'],
            capture_output=True, text=True, timeout=15)
        events = json.loads(result.stdout)
        safe = [{key: item.get(key) for key in ('timestamp', 'processImagePath', 'subsystem', 'category', 'messageType')}
                for item in events[-150:]]
        (out / 'failure-system-metadata.json').write_text(json.dumps(safe, indent=2))
    except (OSError, subprocess.TimeoutExpired, ValueError, TypeError):
        (out / 'failure-system-metadata.json').write_text('{"available":false}\n')

command = ['flutter', 'drive', '--no-pub', '--driver=test_driver/native_qa_driver.dart',
    '--target=integration_test/native_app_test.dart', '--device-id=' + udid,
    '--dart-define=SUPABASE_URL=', '--dart-define=SUPABASE_PUBLISHABLE_KEY=']
process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
started = time.monotonic()
test_started = None
last_capture = None
recent = b''
timed_out = False
with (out / 'integration.log').open('wb') as logfile:
    while process.poll() is None or selector.get_map():
        for key, _ in selector.select(timeout=1):
            data = os.read(key.fd, 65536)
            if not data:
                selector.unregister(key.fileobj)
                continue
            logfile.write(data); logfile.flush()
            sys.stdout.buffer.write(data); sys.stdout.buffer.flush()
            recent = (recent + data)[-8192:]
            if test_started is None and b'[CARCAR_QA] test-start' in recent:
                test_started = time.monotonic()
                last_capture = test_started
        now = time.monotonic()
        # A stalled native UI is visible even before Dart's timeout/cleanup.
        if test_started is not None and now - last_capture >= 10:
            capture('watchdog-test-' + str(int(now - test_started)) + 's')
            last_capture = time.monotonic()
        if (test_started is not None and now - test_started > 250) or now - started > 1200:
            timed_out = True
            capture('failure-before-drive-termination')
            diagnostics()
            print('[CARCAR_QA] host-watchdog-timeout', flush=True)
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            break
code = process.wait()
if code != 0 and not timed_out:
    capture('failure-after-drive')
    diagnostics()
sys.exit(124 if timed_out else code)
PY_DRIVE
# Require both native acknowledgements, including screenshots in the xcresult.
wait "$qa_watcher_pid"
qa_watcher_pid=
grep -q '\[CARCAR_ICON_WATCHER\] finished-count=2' "$CARCAR_QA_ARTIFACT_DIR/icon-watcher.log"
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
    'actualIconChangeTested': True,
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
