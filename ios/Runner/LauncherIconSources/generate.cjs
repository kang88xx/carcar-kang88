// Render source SVGs, never modify an existing bitmap. Uses the already installed
// browser QA tool; no app/runtime dependency is added.
// PLAYWRIGHT_MODULE=/path/to/playwright node ios/Runner/LauncherIconSources/generate.cjs
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const catalog = path.resolve(__dirname, '../Assets.xcassets');
const template = JSON.parse(fs.readFileSync(path.join(catalog, 'AppIcon.appiconset/Contents.json')));
const icons = {
  Default: ['2563EB', 'FFFFFF', 'DBEAFE'],
  Blue: ['577AA4', 'F7F8F4', 'DCEBB4'],
  Black: ['343B39', 'F7F8F4', 'DCEBB4'],
  White: ['B3BBB5', '203C34', 'F7F8F4'],
  Gold: ['C8A35B', '203C34', 'F7F8F4'],
  Mint: ['669E84', '203C34', 'F7F8F4'],
  Purple: ['9985B4', '203C34', 'F7F8F4'],
  Red: ['C77669', '203C34', 'F7F8F4'],
  Gray: ['8C9297', '203C34', 'F7F8F4'],
};
function crc32(bytes) {
  let crc = -1;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit=0; bit<8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ -1) >>> 0;
}
function chunk(type, data) {
  const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
  const content = Buffer.concat([Buffer.from(type), data]);
  const checksum = Buffer.alloc(4); checksum.writeUInt32BE(crc32(content));
  return Buffer.concat([length, content, checksum]);
}
function encodeRGB(size, pixels) {
  const header=Buffer.alloc(13); header.writeUInt32BE(size,0); header.writeUInt32BE(size,4);
  header[8]=8; header[9]=2; // RGB, not RGBA: no alpha channel for App Store icons.
  const rows=Buffer.alloc(size*(size*3+1));
  for(let y=0;y<size;y++) for(let x=0;x<size;x++) {
    const from=(y*size+x)*4, to=y*(size*3+1)+1+x*3;
    if(pixels[from+3]!==255) throw new Error('Icon must be opaque');
    rows[to]=pixels[from]; rows[to+1]=pixels[from+1]; rows[to+2]=pixels[from+2];
  }
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);
}
(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox'],...(process.env.CHROME_EXECUTABLE?{executablePath:process.env.CHROME_EXECUTABLE}:{})});
  try {
    const page=await browser.newPage();
    for(const [name,[background,foreground,dot]] of Object.entries(icons)) {
      if (process.argv.includes('--default-only') && name !== 'Default') continue;
      const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#${background}"/><path fill="#${foreground}" fill-rule="evenodd" d="M300 274H530C672 274 746 343 746 464C746 585 668 653 530 653H421V787H300ZM421 384V543H524C590 543 624 516 624 464C624 410 590 384 524 384Z"/><circle cx="696" cy="735" r="58" fill="#${dot}"/></svg>\n`;
      fs.writeFileSync(path.join(__dirname,`${name}.svg`),svg);
      const dir=path.join(catalog,name === 'Default' ? 'AppIcon.appiconset' : `AppIcon${name}.appiconset`); fs.mkdirSync(dir,{recursive:true});
      const sizes=new Map(template.images.map(i=>[i.filename,Number(i.size.split('x')[0])*Number(i.scale.slice(0,-1))]));
      if (name === 'Default') {
        const root = path.resolve(__dirname, '../../..');
        for (const [density,size] of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192})) {
          sizes.set(path.join(root,`android/app/src/main/res/mipmap-${density}/ic_launcher.png`),size);
        }
        for (const [filename,size] of Object.entries({'favicon.png':32,'icons/Icon-192.png':192,'icons/Icon-512.png':512,'icons/Icon-maskable-192.png':192,'icons/Icon-maskable-512.png':512})) {
          sizes.set(path.join(root,'web',filename),size);
        }
      }
      for(const [filename,size] of sizes) {
        const pixels=await page.evaluate(async({svg,size})=>{
          const image=new Image(); image.src='data:image/svg+xml;base64,'+btoa(svg); await image.decode();
          const canvas=document.createElement('canvas'); canvas.width=size;canvas.height=size;
          const ctx=canvas.getContext('2d',{alpha:false});ctx.drawImage(image,0,0,size,size);
          return Array.from(ctx.getImageData(0,0,size,size).data);
        },{svg,size});
        fs.writeFileSync(path.isAbsolute(filename) ? filename : path.join(dir,filename),encodeRGB(size,pixels));
      }
      fs.writeFileSync(path.join(dir,'Contents.json'),JSON.stringify(template,null,2)+'\n');
    }
  } finally {await browser.close();}
})();
