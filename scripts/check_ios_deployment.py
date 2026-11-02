"""Check the compiled app, not just source settings, before distribution."""
import json
from pathlib import Path
import plistlib
import sys


app = Path(sys.argv[1])
report = {}
for relative, bundle, expected in [
    ('Info.plist', 'com.kang88.carcar', '15.0'),
    ('PlugIns/ParkingWidget.appex/Info.plist',
     'com.kang88.carcar.ParkingWidget', '17.0'),
]:
    with (app / relative).open('rb') as source:
        info = plistlib.load(source)
    if info.get('CFBundleIdentifier') != bundle:
        raise SystemExit(f'Unexpected bundle in {relative}')
    actual = info.get('MinimumOSVersion')
    if actual != expected:
        raise SystemExit(f'{bundle}: expected minimum iOS {expected}, got {actual}')
    report[bundle] = {'minimumOSVersion': actual}
print(json.dumps(report, indent=2))
