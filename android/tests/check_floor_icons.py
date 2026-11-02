"""Check the native launcher contract and raster dimensions without SDK dependencies."""
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
res = root / 'android/app/src/main/res'
android = '{http://schemas.android.com/apk/res/android}'
app = ET.parse(root / 'android/app/src/main/AndroidManifest.xml').getroot().find('application')
aliases = app.findall('activity-alias')
labels = [f'F{i}' for i in range(1, 6)] + [f'B{i}' for i in range(1, 7)]
expected = {'.LauncherDefault'} | {'.LauncherFloor' + label for label in labels}
assert {a.get(android + 'name') for a in aliases} == expected
assert [a.get(android + 'name') for a in aliases if a.get(android + 'enabled') == 'true'] == ['.LauncherDefault']
main = next(a for a in app.findall('activity') if a.get(android + 'name') == '.MainActivity')
assert main.get(android + 'enabled', 'true') == 'true'
assert not main.findall("intent-filter/category[@" + android + "name='android.intent.category.LAUNCHER']")
for host in ['login-callback', 'invite']:
    filters = [f for f in main.findall('intent-filter') if any(d.get(android + 'scheme') == 'com.kang88.carcar' and d.get(android + 'host') == host for d in f.findall('data'))]
    assert len(filters) == 1
    assert filters[0].find("action[@" + android + "name='android.intent.action.VIEW']") is not None
    assert filters[0].find("category[@" + android + "name='android.intent.category.BROWSABLE']") is not None
for alias in aliases:
    assert alias.get(android + 'targetActivity') == '.MainActivity'
    assert alias.get(android + 'exported') == 'true'
    assert alias.find("intent-filter/action[@" + android + "name='android.intent.action.MAIN']") is not None
    assert alias.find("intent-filter/category[@" + android + "name='android.intent.category.LAUNCHER']") is not None
checked = 0
for label in labels:
    for density, (legacy, adaptive) in {'mdpi': (48, 108), 'hdpi': (72, 162), 'xhdpi': (96, 216), 'xxhdpi': (144, 324), 'xxxhdpi': (192, 432)}.items():
        for suffix, size, color in [('', legacy, 2), ('_foreground', adaptive, 6)]:
            png = (res / f'mipmap-{density}/ic_launcher_floor_{label.lower()}{suffix}.png').read_bytes()
            assert png[:8] == b'\x89PNG\r\n\x1a\n'
            assert struct.unpack('>IIBB', png[16:26]) == (size, size, 8, color)
            checked += 1
    for api in [26, 33]:
        icon = ET.parse(res / f'mipmap-anydpi-v{api}/ic_launcher_floor_{label.lower()}.xml').getroot()
        assert icon.find('background').get(android + 'drawable') == '@color/launcher_background'
        assert icon.find('foreground').get(android + 'drawable') == '@mipmap/ic_launcher_floor_' + label.lower() + '_foreground'
        if api == 33: assert icon.find('monochrome') is not None
print(f'PASS: 12 aliases, exactly one default entry, enabled deep-link activity, {checked} Android rasters, 22 adaptive/themed descriptors')
