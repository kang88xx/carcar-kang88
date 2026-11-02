"""Regenerate native floor icons using the repository's OFL-licensed Noto font.

Requires Pillow as a development tool; no app/runtime dependency is added.
Run from any directory. SVG design sources and all native sizes are generated.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / 'assets/fonts/NotoSansKR-Bold.ttf'
CATALOG = ROOT / 'ios/Runner/Assets.xcassets'
ANDROID = ROOT / 'android/app/src/main/res'
FLOORS = [f'F{i}' for i in range(1, 6)] + [f'B{i}' for i in range(1, 7)]
BACKGROUND = '#295C49'
FOREGROUND = '#F7F8F4'
IOS_CONTENTS = json.loads((CATALOG / 'AppIcon.appiconset/Contents.json').read_text())
DENSITIES = {'mdpi': (48, 108), 'hdpi': (72, 162), 'xhdpi': (96, 216), 'xxhdpi': (144, 324), 'xxxhdpi': (192, 432)}


def centered(draw, text, font, center):
    bounds = draw.textbbox((0, 0), text, font=font)
    x = center[0] - (bounds[2] - bounds[0]) / 2 - bounds[0]
    y = center[1] - (bounds[3] - bounds[1]) / 2 - bounds[1]
    draw.text((round(x), round(y)), text, font=font, fill=FOREGROUND)


def draw_icon(label, transparent=False):
    image = Image.new('RGBA' if transparent else 'RGB', (1024, 1024), (0, 0, 0, 0) if transparent else BACKGROUND)
    draw = ImageDraw.Draw(image)
    centered(draw, label, ImageFont.truetype(str(FONT), 480), (512, 465))
    centered(draw, '차곡', ImageFont.truetype(str(FONT), 92), (512, 745))
    return image


def main():
    for label in FLOORS:
        identifier = 'floor_' + label.lower()
        (ROOT / 'assets/launcher' / (label + '.svg')).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<rect width="1024" height="1024" fill="{BACKGROUND}"/>'
            f'<g fill="{FOREGROUND}" font-family="Noto Sans KR" font-weight="700" text-anchor="middle">'
            f'<text x="512" y="465" dominant-baseline="central" font-size="480">{label}</text>'
            '<text x="512" y="745" dominant-baseline="central" font-size="92">차곡</text></g></svg>\n'
        )
        opaque = draw_icon(label)
        foreground = draw_icon(label, transparent=True)
        folder = CATALOG / f'AppIconFloor{label}.appiconset'
        folder.mkdir(exist_ok=True)
        (folder / 'Contents.json').write_text(json.dumps(IOS_CONTENTS, indent=2) + '\n')
        for item in IOS_CONTENTS['images']:
            size = round(float(item['size'].split('x')[0]) * int(item['scale'][:-1]))
            opaque.resize((size, size), Image.Resampling.LANCZOS).save(folder / item['filename'])
        for density, (legacy_size, adaptive_size) in DENSITIES.items():
            folder = ANDROID / ('mipmap-' + density)
            folder.mkdir(exist_ok=True)
            opaque.resize((legacy_size, legacy_size), Image.Resampling.LANCZOS).save(folder / f'ic_launcher_{identifier}.png')
            foreground.resize((adaptive_size, adaptive_size), Image.Resampling.LANCZOS).save(folder / f'ic_launcher_{identifier}_foreground.png')
        for version in (26, 33):
            folder = ANDROID / f'mipmap-anydpi-v{version}'
            folder.mkdir(exist_ok=True)
            monochrome = f'    <monochrome android:drawable="@mipmap/ic_launcher_{identifier}_foreground" />\n' if version >= 33 else ''
            (folder / f'ic_launcher_{identifier}.xml').write_text(
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/launcher_background" />\n'
                f'    <foreground android:drawable="@mipmap/ic_launcher_{identifier}_foreground" />\n'
                f'{monochrome}</adaptive-icon>\n'
            )
    print(f'Generated {len(FLOORS)} floor icons for iPhone, iPad and Android, including adaptive/themed layers.')


if __name__ == '__main__':
    main()
