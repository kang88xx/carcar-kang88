"""Validate icon catalogs and raster outputs without third-party dependencies."""
import json
import struct
import zlib
from pathlib import Path

root = Path(__file__).resolve().parents[3]
catalog = root / 'ios/Runner/Assets.xcassets'
names = ['Blue', 'Black', 'White', 'Gold', 'Mint', 'Purple', 'Red', 'Gray'] + [f'FloorF{i}' for i in range(1, 6)] + [f'FloorB{i}' for i in range(1, 7)]
project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
expected = 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "' + ' '.join('AppIcon' + n for n in names) + '";'
assert project.count(expected) == 3, 'Debug, Profile and Release must include all icons'
checked = 0
for name in names:
    folder = catalog / ('AppIcon' + name + '.appiconset')
    contents = json.loads((folder / 'Contents.json').read_text())
    assert any(i['idiom'] == 'ios-marketing' for i in contents['images'])
    assert any(i['idiom'] == 'iphone' for i in contents['images'])
    assert any(i['idiom'] == 'ipad' for i in contents['images'])
    for image in contents['images']:
        png = (folder / image['filename']).read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        width, height, depth, color = struct.unpack('>IIBB', png[16:26])
        size = int(float(image['size'].split('x')[0]) * int(image['scale'][:-1]))
        assert (width, height, depth, color) == (size, size, 8, 2), 'Opaque RGB dimensions required'
        offset = 8
        compressed = b''
        while offset < len(png):
            length = struct.unpack('>I', png[offset:offset+4])[0]
            content = png[offset+4:offset+8+length]
            checksum = struct.unpack('>I', png[offset+8+length:offset+12+length])[0]
            assert zlib.crc32(content) == checksum
            if content[:4] == b'IDAT': compressed += content[4:]
            offset += length + 12
        pixels = zlib.decompress(compressed)
        assert len(pixels) == size * (size * 3 + 1)
        checked += 1


def rgba_pixels(png):
    width, height, depth, color = struct.unpack('>IIBB', png[16:26])
    assert (depth, color) == (8, 6), 'RGBA layer required'
    offset, compressed = 8, b''
    while offset < len(png):
        length = struct.unpack('>I', png[offset:offset+4])[0]
        content = png[offset+4:offset+8+length]
        if content[:4] == b'IDAT': compressed += content[4:]
        offset += length + 12
    rows = zlib.decompress(compressed)
    stride = width * 4 + 1
    return width, lambda x, y: rows[y * stride + 1 + x * 4: y * stride + 5 + x * 4]


# Android 13+ themed icons use only alpha: the floor label must be transparent
# inside the otherwise opaque pin head, and each v33 XML must point at it.
floors = [f'f{i}' for i in range(1, 6)] + [f'b{i}' for i in range(1, 7)]
for floor in floors:
    xml = (root / f'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher_floor_{floor}.xml').read_text()
    assert f'ic_launcher_floor_{floor}_monochrome' in xml, f'v33 monochrome layer missing for {floor}'
    png = (root / f'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_floor_{floor}_monochrome.png').read_bytes()
    size, pixel = rgba_pixels(png)
    def scaled(v): return round(size * (512 + (v - 512) * 0.85) / 1024)
    assert pixel(size // 2, scaled(300))[3] == 255, f'{floor}: pin head should be opaque above the label'
    row = [pixel(x, scaled(430))[3] for x in range(scaled(300), scaled(724))]
    assert row.count(0) >= size // 20 and row.count(255) >= size // 20, f'{floor}: label must be knocked out of the monochrome pin'
print(f'PASS: {len(names)} alternate catalogs, {checked} iPhone/iPad/marketing entries, RGB PNG integrity, 3 build configurations, {len(floors)} themed monochrome layers')
