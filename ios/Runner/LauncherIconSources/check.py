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
print(f'PASS: {len(names)} alternate catalogs, {checked} iPhone/iPad/marketing entries, RGB PNG integrity, 3 build configurations')
