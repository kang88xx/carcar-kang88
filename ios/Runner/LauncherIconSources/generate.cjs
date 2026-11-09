// Render launcher icons from SVG sources; never edit an existing bitmap by hand.
// Uses the already installed browser QA tool; no app/runtime dependency is added.
//
//   PLAYWRIGHT_MODULE=/path/to/playwright node ios/Runner/LauncherIconSources/generate.cjs
//
// Default run: the pin mark (Default) plus the eleven floor pins F1–F5/B1–B6 for
// iPhone, iPad, Android (legacy + adaptive foreground + themed monochrome layers)
// and the web icons. The written *.svg sources reference the bundled Noto font by
// name; it is embedded only while rasterising, so the PNGs are the real output.
// `--legacy` also regenerates the eight compatibility color variants (old P mark).
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const root = path.resolve(__dirname, '../../..');
const catalog = path.resolve(__dirname, '../Assets.xcassets');
const android = path.join(root, 'android/app/src/main/res');
const template = JSON.parse(fs.readFileSync(path.join(catalog, 'AppIcon.appiconset/Contents.json')));
const font = fs.readFileSync(path.join(root, 'assets/fonts/NotoSansKR-Bold.ttf')).toString('base64');

// 차자리 pin palette (design direction A, 2026-11-10).
const BLUE = '#2563EB', DEEP = '#1D4ED8', WHITE = '#FFFFFF';
const FLOORS = ['F1', 'F2', 'F3', 'F4', 'F5', 'B1', 'B2', 'B3', 'B4', 'B5', 'B6'];
const DENSITIES = {mdpi: [48, 108], hdpi: [72, 162], xhdpi: [96, 216], xxhdpi: [144, 324], xxxhdpi: [192, 432]};
const legacy = {
  Blue: ['577AA4', 'F7F8F4', 'DCEBB4'],
  Black: ['343B39', 'F7F8F4', 'DCEBB4'],
  White: ['B3BBB5', '203C34', 'F7F8F4'],
  Gold: ['C8A35B', '203C34', 'F7F8F4'],
  Mint: ['669E84', '203C34', 'F7F8F4'],
  Purple: ['9985B4', '203C34', 'F7F8F4'],
  Red: ['C77669', '203C34', 'F7F8F4'],
  Gray: ['8C9297', '203C34', 'F7F8F4'],
};

const PIN = 'M512 830 C420 700 276 590 276 430 A236 236 0 0 1 748 430 C748 590 604 700 512 830 Z';
const CAR =
  `<rect x="432" y="290" width="160" height="280" rx="60" fill="${BLUE}"/>` +
  `<circle cx="424" cy="382" r="16" fill="${BLUE}"/><circle cx="600" cy="382" r="16" fill="${BLUE}"/>` +
  `<rect x="454" y="344" width="116" height="58" rx="18" fill="${WHITE}"/>` +
  `<rect x="454" y="470" width="116" height="44" rx="14" fill="${WHITE}"/>`;

function label(text) {
  return `<text x="512" y="430" text-anchor="middle" dominant-baseline="central" font-family="Noto Sans KR" font-weight="700" font-size="236" fill="${BLUE}">${text}</text>`;
}

/// Pin mark. `floor` = null draws the car; otherwise the floor label.
/// `opaque` = false omits the background for Android adaptive foregrounds and
/// scales the mark into the 66/108 safe zone.
function pinSvg(floor, opaque) {
  const inner = floor ? label(floor) : CAR;
  const mark = `<ellipse cx="512" cy="846" rx="130" ry="26" fill="${DEEP}"/><path d="${PIN}" fill="${WHITE}"/>${inner}`;
  const body = opaque
    ? `<rect width="1024" height="1024" fill="${BLUE}"/>${mark}`
    : `<g transform="translate(512 512) scale(0.85) translate(-512 -512)">${mark}</g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${body}</svg>\n`;
}

/// Android 13+ themed icons read only the alpha channel, so the floor label is
/// knocked out of the pin (transparent) instead of painted in blue.
function monochromeSvg(floor) {
  const mask = `<mask id="m"><rect width="1024" height="1024" fill="white"/>${label(floor).replace(`fill="${BLUE}"`, 'fill="black"')}</mask>`;
  const mark = `<g mask="url(#m)"><ellipse cx="512" cy="846" rx="130" ry="26" fill="${WHITE}"/><path d="${PIN}" fill="${WHITE}"/></g>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>${mask}</defs><g transform="translate(512 512) scale(0.85) translate(-512 -512)">${mark}</g></svg>\n`;
}

function legacySvg([background, foreground, dot]) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#${background}"/><path fill="#${foreground}" fill-rule="evenodd" d="M300 274H530C672 274 746 343 746 464C746 585 668 653 530 653H421V787H300ZM421 384V543H524C590 543 624 516 624 464C624 410 590 384 524 384Z"/><circle cx="696" cy="735" r="58" fill="#${dot}"/></svg>\n`;
}

function crc32(bytes) {
  let crc = -1;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ -1) >>> 0;
}
function chunk(type, data) {
  const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
  const content = Buffer.concat([Buffer.from(type), data]);
  const checksum = Buffer.alloc(4); checksum.writeUInt32BE(crc32(content));
  return Buffer.concat([length, content, checksum]);
}
const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
function encodeRGB(size, pixels) {
  const header = Buffer.alloc(13); header.writeUInt32BE(size, 0); header.writeUInt32BE(size, 4);
  header[8] = 8; header[9] = 2; // RGB, not RGBA: no alpha channel for App Store icons.
  const rows = Buffer.alloc(size * (size * 3 + 1));
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const from = (y * size + x) * 4, to = y * (size * 3 + 1) + 1 + x * 3;
    if (pixels[from + 3] !== 255) throw new Error('Icon must be opaque');
    rows[to] = pixels[from]; rows[to + 1] = pixels[from + 1]; rows[to + 2] = pixels[from + 2];
  }
  return Buffer.concat([SIGNATURE, chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}
function encodeRGBA(size, pixels) {
  const header = Buffer.alloc(13); header.writeUInt32BE(size, 0); header.writeUInt32BE(size, 4);
  header[8] = 8; header[9] = 6; // RGBA for Android adaptive foreground layers.
  const rows = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) rows.set(pixels.subarray(y * size * 4, (y + 1) * size * 4), y * (size * 4 + 1) + 1);
  return Buffer.concat([SIGNATURE, chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}

const iosSizes = template.images.map((i) => [i.filename, Number(i.size.split('x')[0]) * Number(i.scale.slice(0, -1))]);

function writeIosSet(name, pixelsAt) {
  const dir = path.join(catalog, name === 'Default' ? 'AppIcon.appiconset' : `AppIcon${name}.appiconset`);
  fs.mkdirSync(dir, {recursive: true});
  for (const [filename, size] of iosSizes) fs.writeFileSync(path.join(dir, filename), encodeRGB(size, pixelsAt(size)));
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify(template, null, 2) + '\n');
}

(async () => {
  const browser = await chromium.launch({headless: true, args: ['--no-sandbox'], ...(process.env.CHROME_EXECUTABLE ? {executablePath: process.env.CHROME_EXECUTABLE} : {})});
  try {
    const page = await browser.newPage({viewport: {width: 1024, height: 1024}, deviceScaleFactor: 1});
    // Renders the SVG inline (so the bundled Noto font applies), screenshots it at
    // 1024px and downsamples step by step inside the page.
    async function raster(svg, transparent) {
      await page.setContent(
        `<!doctype html><html><head><meta charset="utf-8"><style>@font-face{font-family:'Noto Sans KR';font-weight:700;src:url(data:font/ttf;base64,${font}) format('truetype')}html,body{margin:0;background:transparent}svg{display:block}</style></head><body>${svg}</body></html>`,
      );
      const loaded = await page.evaluate(() => document.fonts.load("700 236px 'Noto Sans KR'").then((faces) => document.fonts.ready.then(() => faces.length)));
      if (!loaded) throw new Error('Noto Sans KR Bold did not load; refusing to render floor labels in a fallback font');
      const png = await page.screenshot({clip: {x: 0, y: 0, width: 1024, height: 1024}, omitBackground: transparent, type: 'png'});
      const cache = new Map();
      return async (size) => {
        if (!cache.has(size)) {
          cache.set(size, Uint8Array.from(await page.evaluate(async ({data, size}) => {
            const image = new Image(); image.src = 'data:image/png;base64,' + data; await image.decode();
            let source = image, width = 1024;
            while (width / 2 >= size) {
              width /= 2;
              const step = document.createElement('canvas'); step.width = step.height = width;
              const ctx = step.getContext('2d'); ctx.imageSmoothingQuality = 'high'; ctx.drawImage(source, 0, 0, width, width);
              source = step;
            }
            const canvas = document.createElement('canvas'); canvas.width = canvas.height = size;
            const ctx = canvas.getContext('2d'); ctx.imageSmoothingQuality = 'high'; ctx.drawImage(source, 0, 0, size, size);
            return Array.from(ctx.getImageData(0, 0, size, size).data);
          }, {data: png.toString('base64'), size})));
        }
        return cache.get(size);
      };
    }

    // Default pin: iOS, Android legacy raster, web.
    const defaultSvg = pinSvg(null, true);
    fs.writeFileSync(path.join(__dirname, 'Default.svg'), defaultSvg);
    const defaultPixels = await raster(defaultSvg, false);
    // writeIosSet is synchronous, so pre-render the sizes it needs first.
    async function prepared(pixelsAt, sizes) {
      const map = new Map();
      for (const size of new Set(sizes)) map.set(size, await pixelsAt(size));
      return map;
    }
    const defaultMap = await prepared(defaultPixels, [...iosSizes.map(([, s]) => s), 48, 72, 96, 144, 192, 32, 512]);
    writeIosSet('Default', (size) => defaultMap.get(size));
    for (const [density, [size]] of Object.entries(DENSITIES)) {
      fs.writeFileSync(path.join(android, `mipmap-${density}/ic_launcher.png`), encodeRGB(size, defaultMap.get(size)));
    }
    for (const [filename, size] of Object.entries({'favicon.png': 32, 'icons/Icon-192.png': 192, 'icons/Icon-512.png': 512, 'icons/Icon-maskable-192.png': 192, 'icons/Icon-maskable-512.png': 512})) {
      fs.writeFileSync(path.join(root, 'web', filename), encodeRGB(size, defaultMap.get(size)));
    }

    // Floor pins: iOS alternate sets, Android legacy raster + adaptive foreground.
    for (const floor of FLOORS) {
      const id = 'floor_' + floor.toLowerCase();
      const opaqueSvg = pinSvg(floor, true);
      fs.writeFileSync(path.join(root, 'assets/launcher', `${floor}.svg`), opaqueSvg);
      const opaque = await prepared(await raster(opaqueSvg, false), [...iosSizes.map(([, s]) => s), 48, 72, 96, 144, 192]);
      const foreground = await prepared(await raster(pinSvg(floor, false), true), [108, 162, 216, 324, 432]);
      const monochrome = await prepared(await raster(monochromeSvg(floor), true), [108, 162, 216, 324, 432]);
      writeIosSet(`Floor${floor}`, (size) => opaque.get(size));
      for (const [density, [legacySize, adaptiveSize]] of Object.entries(DENSITIES)) {
        fs.writeFileSync(path.join(android, `mipmap-${density}/ic_launcher_${id}.png`), encodeRGB(legacySize, opaque.get(legacySize)));
        fs.writeFileSync(path.join(android, `mipmap-${density}/ic_launcher_${id}_foreground.png`), encodeRGBA(adaptiveSize, foreground.get(adaptiveSize)));
        fs.writeFileSync(path.join(android, `mipmap-${density}/ic_launcher_${id}_monochrome.png`), encodeRGBA(adaptiveSize, monochrome.get(adaptiveSize)));
      }
      fs.writeFileSync(path.join(android, `mipmap-anydpi-v33/ic_launcher_${id}.xml`),
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n' +
        '    <background android:drawable="@color/launcher_background" />\n' +
        `    <foreground android:drawable="@mipmap/ic_launcher_${id}_foreground" />\n` +
        `    <monochrome android:drawable="@mipmap/ic_launcher_${id}_monochrome" />\n` +
        '</adaptive-icon>\n');
    }

    if (process.argv.includes('--legacy')) {
      for (const [name, colors] of Object.entries(legacy)) {
        const svg = legacySvg(colors);
        fs.writeFileSync(path.join(__dirname, `${name}.svg`), svg);
        const map = await prepared(await raster(svg, false), iosSizes.map(([, s]) => s));
        writeIosSet(name, (size) => map.get(size));
      }
    }
    console.log(`Generated the default pin, ${FLOORS.length} floor pins (iPhone, iPad, Android legacy + adaptive, web)${process.argv.includes('--legacy') ? ' and 8 legacy variants' : ''}.`);
  } finally { await browser.close(); }
})();
