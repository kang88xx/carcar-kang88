#!/usr/bin/env bash
# Local Simulator captures only. Never installs or resets an app on a real phone.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS and Xcode are required.' >&2; exit 2; }
command -v flutter >/dev/null
command -v xcrun >/dev/null
command -v bundle >/dev/null
export CARCAR_STORE_OUTPUT="${CARCAR_STORE_OUTPUT:-$PWD/build/app-store-media-20261108/simulator}"
python3 - <<'PY'
import hashlib, json, os, re, selectors, signal, subprocess, time
from pathlib import Path

root = Path.cwd()
out = Path(os.environ['CARCAR_STORE_OUTPUT']).resolve()
if out.exists() and (not out.is_dir() or any(out.iterdir())):
    raise SystemExit('Capture output must be an empty directory. Set CARCAR_STORE_OUTPUT to a new path: ' + str(out))
out.mkdir(parents=True, exist_ok=True)
source = '069dd4ccb49add356706f909335f938994c2076b'
product_paths = ['lib', 'ios', 'android', 'assets', 'pubspec.yaml', 'pubspec.lock']

def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def read_json(args):
    return json.loads(subprocess.check_output(args, text=True))

# Refuse captures if the product differs from the released TestFlight 13 source.
run(['git', 'diff', '--exit-code', source, '--', *product_paths])
files = subprocess.check_output(['git', 'ls-files', '-z', '--', *product_paths]).decode().split('\0')
hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in files if p}
runtimes = read_json(['xcrun', 'simctl', 'list', 'runtimes', '--json'])['runtimes']
types = read_json(['xcrun', 'simctl', 'list', 'devicetypes', '--json'])['devicetypes']
targets = [('iphone', 'iPhone 18 Pro Max', (1320, 2868)),
           ('ipad', 'iPad Pro 13-inch (M5)', (2064, 2752))]
records = []

for family, model, expected_size in targets:
    device_type = next(d for d in types if d['name'] == model)
    compatible = [r for r in runtimes if r.get('isAvailable') and r.get('platform') == 'iOS'
                  and any(d['identifier'] == device_type['identifier'] for d in r.get('supportedDeviceTypes', []))]
    runtime = max(compatible, key=lambda r: tuple(int(x) for x in r['version'].split('.')))
    name = 'Carcar Store ' + family + ' 20261108'
    catalog = read_json(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'])['devices']
    matches = [d for d in catalog.get(runtime['identifier'], []) if d['name'] == name
               and d.get('deviceTypeIdentifier') == device_type['identifier']]
    if len(matches) > 1:
        raise RuntimeError('Ambiguous dedicated capture Simulator')
    if matches:
        device = matches[0]
        if device['state'] != 'Shutdown':
            raise RuntimeError('Dedicated capture Simulator is already in use; refusing to reset it')
        udid = device['udid']
    else:
        udid = subprocess.check_output(['xcrun', 'simctl', 'create', name,
            device_type['identifier'], runtime['identifier']], text=True).strip()
    # Only an ID returned by simctl's available-device catalog may reach drive.
    verified = read_json(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'])['devices']
    assert any(d['udid'] == udid and d['name'] == name and d.get('isAvailable')
               for d in verified.get(runtime['identifier'], []))
    target = out / family
    target.mkdir(exist_ok=True)
    raw = target / 'raw'
    raw.mkdir(exist_ok=True)
    watcher = None
    drive = None
    video = None
    log_handles = []
    started = False
    captured = []
    try:
        run(['xcrun', 'simctl', 'boot', udid])
        started = True
        run(['xcrun', 'simctl', 'bootstatus', udid, '-b'])
        run(['xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41',
             '--batteryState', 'charged', '--batteryLevel', '100'])
        watcher_dir = target / 'icon-watcher'
        env = dict(os.environ, BUNDLE_GEMFILE=str(root / 'fastlane/Gemfile'))
        run(['bundle', 'exec', 'ruby', 'scripts/generate_ios_alert_watcher.rb', str(watcher_dir)], env=env)
        # Only the generated QA host changes: allow its UI test on both families.
        project = watcher_dir / 'IconAlertWatcher.xcodeproj/project.pbxproj'
        project.write_text(project.read_text().replace('TARGETED_DEVICE_FAMILY = 1;', 'TARGETED_DEVICE_FAMILY = "1,2";'))
        xcode = ['xcodebuild', '-project', str(watcher_dir / 'IconAlertWatcher.xcodeproj'),
                 '-scheme', 'IconAlertWatcher', '-configuration', 'Debug',
                 '-destination', 'platform=iOS Simulator,id=' + udid,
                 '-derivedDataPath', str(watcher_dir / 'DerivedData')]
        with (target / 'icon-watcher-build.log').open('wb') as log:
            run(xcode + ['build-for-testing', 'CODE_SIGNING_ALLOWED=NO'], stdout=log, stderr=subprocess.STDOUT)
        watcher_log = (target / 'icon-watcher.log').open('wb')
        log_handles.append(watcher_log)
        watcher = subprocess.Popen(xcode + ['test-without-building', '-parallel-testing-enabled', 'NO',
            '-maximum-concurrent-test-simulator-destinations', '1'], stdout=watcher_log, stderr=subprocess.STDOUT)
        for _ in range(120):
            if '[CARCAR_ICON_WATCHER] ready' in (target / 'icon-watcher.log').read_text(errors='replace'):
                break
            if watcher.poll() is not None:
                raise RuntimeError('Icon watcher ended before readiness')
            time.sleep(1)
        else:
            raise RuntimeError('Icon watcher readiness timed out')

        env['CARCAR_QA_ARTIFACT_DIR'] = str(raw)
        command = ['flutter', 'drive', '--no-pub', '--driver=test_driver/native_qa_driver.dart',
                   '--target=integration_test/store_screenshots_test.dart', '--device-id=' + udid,
                   '--dart-define=CARCAR_STORE_SIMULATOR=true', '--dart-define=CARCAR_STORE_DEVICE_ID=' + udid,
                   '--dart-define=SUPABASE_URL=',
                   '--dart-define=SUPABASE_PUBLISHABLE_KEY=']
        drive = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(drive.stdout, selectors.EVENT_READ)
        pending = b''
        deadline = time.monotonic() + 900
        with (target / 'integration.log').open('wb') as log:
            while drive.poll() is None or selector.get_map():
                if time.monotonic() > deadline:
                    raise RuntimeError('Capture timed out')
                for key, _ in selector.select(timeout=1):
                    data = os.read(key.fd, 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    log.write(data); log.flush()
                    pending += data
                    while b'\n' in pending:
                        line, pending = pending.split(b'\n', 1)
                        text = line.decode(errors='replace')
                        marker = re.search(r'\[CARCAR_STORE\] ([a-z0-9:-]+)', text)
                        if not marker:
                            continue
                        stage = marker[1]
                        print(f'{family}: {stage}', flush=True)
                        if stage == 'video-start':
                            video_log = (target / 'video.log').open('wb')
                            log_handles.append(video_log)
                            video = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo',
                                '--codec=h264', '--force', str(target / 'simulator-demo-walkthrough.mov')],
                                stdout=video_log, stderr=subprocess.STDOUT)
                        elif stage == 'video-stop' and video is not None:
                            video.send_signal(signal.SIGINT)
                            video_exit = video.wait(timeout=20)
                            video = None
                            if video_exit != 0:
                                raise RuntimeError('Simulator recording failed with exit code ' + str(video_exit))
                        elif stage.startswith('capture:'):
                            scene = stage.split(':', 1)[1]
                            assert scene in ['01-home', '02-parking-entry', '03-family', '04-history']
                            run(['xcrun', 'simctl', 'io', udid, 'screenshot', '--type=jpeg', str(target / (scene + '.jpg'))], timeout=10)
                            captured.append(scene)
        if drive.wait() != 0:
            raise RuntimeError('Flutter screenshot integration failed: ' + str(target / 'integration.log'))
        if watcher.wait(timeout=30) != 0:
            raise RuntimeError('Native icon watcher did not pass')
        assert len(captured) == 4 and len(set(captured)) == 4
        screenshots = []
        for scene in captured:
            image = target / (scene + '.jpg')
            attributes = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', str(image)], text=True)
            width = int(re.search(r'pixelWidth: (\d+)', attributes)[1])
            height = int(re.search(r'pixelHeight: (\d+)', attributes)[1])
            assert (width, height) == expected_size, (family, width, height)
            assert 'hasAlpha: no' in attributes
            screenshots.append({'file': image.name, 'width': width, 'height': height,
                'hasAlpha': False, 'sha256': hashlib.sha256(image.read_bytes()).hexdigest()})
        video_path = target / 'simulator-demo-walkthrough.mov'
        assert video_path.stat().st_size > 10000
        record = {'deviceFamily': family, 'model': model, 'simulatorUDID': udid,
            'runtime': runtime['identifier'], 'screenshots': screenshots,
            'video': {'file': video_path.name, 'source': 'Simulator recording',
                      'intendedUse': 'local demo QA evidence, not a physical-device test or final App Preview'}}
        records.append(record)
        (target / 'capture.json').write_text(json.dumps(record, indent=2) + '\n')
    finally:
        if video is not None and video.poll() is None:
            video.send_signal(signal.SIGINT)
            video.wait(timeout=20)
        if drive is not None and drive.poll() is None:
            os.killpg(drive.pid, signal.SIGTERM)
            try:
                drive.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(drive.pid, signal.SIGKILL)
                drive.wait()
        if watcher is not None and watcher.poll() is None:
            watcher.terminate()
            watcher.wait(timeout=15)
        for handle in log_handles:
            handle.close()
        if started:
            subprocess.run(['xcrun', 'simctl', 'status_bar', udid, 'clear'], check=False)
            subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False)

run(['git', 'diff', '--exit-code', source, '--', *product_paths])
inspector = out / 'inspect-video.swift'
inspector.write_text('''import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main struct InspectVideo {
    static func main() async throws {
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite && duration > 0,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            fatalError("Recorded video has no playable video track")
        }
        let size = try await track.load(.naturalSize)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frame = try generator.copyCGImage(at: CMTime(seconds: duration / 2, preferredTimescale: 600), actualTime: nil)
        let thumbnail = file.deletingPathExtension().appendingPathExtension("frame.png")
        guard let output = CGImageDestinationCreateWithURL(thumbnail as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Cannot save video validation frame")
        }
        CGImageDestinationAddImage(output, frame, nil)
        guard CGImageDestinationFinalize(output) else { fatalError("Cannot finalize validation frame") }
        let report: [String: Any] = ["durationSeconds": duration, "width": Int(size.width), "height": Int(size.height), "decodedFrame": thumbnail.lastPathComponent]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
''')
inspector_binary = out / 'inspect-video'
run(['xcrun', 'swiftc', '-parse-as-library', str(inspector), '-o', str(inspector_binary)])
for record in records:
    target = out / record['deviceFamily']
    details = read_json([str(inspector_binary), str(target / record['video']['file'])])
    record['video'].update(details)
    (target / 'capture.json').write_text(json.dumps(record, indent=2) + '\n')
manifest = {'sourceCommit': source, 'testFlightBuild': '1.0.0 (13)',
    'captureSource': 'iOS Simulator native app', 'dataSource': 'built-in local demo',
    'productSourceMatchesTestFlight13': True, 'productSourceHashes': hashes,
    'physicalTestVerified': False, 'backendTested': False, 'authenticationTested': False,
    'nativeHomeWidgetCaptured': False, 'imageEditingApplied': False, 'devices': records}
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Captured and validated eight native screenshots and two Simulator recordings.', flush=True)
PY
