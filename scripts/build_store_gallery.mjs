import {readFile, writeFile, mkdir, copyFile, access} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
export const scenes = [
  ['01-widgets-icons', '앱을 열기 전,\n주차 층부터.', '홈 화면 위젯으로 위치를, 층수 아이콘으로 주차 층을 확인해요.'],
  ['02-parking-entry', '층과 구역을 고르고,\n주차 기록 끝.', '필요한 위치만 남기세요. 주차 번호는 선택이에요.', '02-parking-entry.jpg'],
  ['03-home', '“차 어디 뒀어?”\n이제 함께 확인해요.', '마지막 주차 위치와 기록한 사람, 시간을 한눈에.', '01-home.jpg'],
  ['04-family', '같이 쓰는 차,\n같이 보는 위치.', '초대한 가족과 같은 차량의 주차 위치를 확인해요.', '03-family.jpg'],
  ['05-history', '지난 주차도,\n기록에 남아 있어요.', '이전 위치와 기록 시각을 주차 이력에서 찾아보세요.', '04-history.jpg'],
];
export const states = ['off-b2', 'on-b2', 'on-b3'];
const labels = ['층수 아이콘 끔 · B2 기록', '층수 아이콘 켬 · B2 기록', '층수 아이콘 켬 · B3 기록'];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export async function verifiedFile(root, entry) {
  if (!entry || typeof entry.file !== 'string' || entry.file.includes('..') || entry.file.startsWith('/')) throw Error('Invalid source path');
  const bytes = await readFile(resolve(root, entry.file));
  if (hash(bytes) !== entry.sha256) throw Error('Source hash mismatch: ' + entry.file);
  return bytes;
}
export function nativeComplete(captures) {
  return ['iphone','ipad'].every(f => states.every(s => captures.filter(c => c.deviceFamily === f && c.state === s).length === 1));
}
export async function buildGallery({sourceRoot, output, nativeRoot, playwrightModule, chrome}) {
  const original = JSON.parse(await readFile(resolve(sourceRoot,'manifest.json')));
  execFileSync('git',['diff','--exit-code',original.sourceCommit,'--','lib','ios','android','assets','pubspec.yaml','pubspec.lock']);
  let native = {captures:[]};
  if (nativeRoot) {
    native = JSON.parse(await readFile(resolve(nativeRoot,'manifest.json')));
    if (native.sourceCommit !== original.sourceCommit) throw Error('Native source commit mismatch');
  }
  try { await access(output); throw Error('Output already exists; use a fresh directory'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  await mkdir(output,{recursive:true});
  const {chromium} = await import(playwrightModule ? pathToFileURL(resolve(playwrightModule)).href : 'playwright');
  const copy = JSON.parse(await readFile('docs/app-store/public-listing-ko.json'));
  const captions = scenes.map((scene,i)=>[scene[0],copy.screenshotPlan[i].headline,copy.screenshotPlan[i].caption,scene[3]]);
  const browser = await chromium.launch({executablePath:chrome,headless:true});
  const manifest = {sourceCommit:original.sourceCommit, submissionReady:false, captureSource:'Native Simulator captures with HTML editorial captions', imageEditingApplied:true, devices:[]};
  let gallery = '';
  try {
    for (const [family,width,height] of [['iphone',1320,2868],['ipad',2064,2752]]) {
      const dir=resolve(output,family); await mkdir(resolve(dir,'source'),{recursive:true});
      const device={deviceFamily:family,screenshots:[]};
      const nativeEntries=states.map(state=>native.captures.find(c=>c.deviceFamily===family&&c.state===state));
      const component=native.captureSource === 'native-component-render';
      const complete=component ? ['widget-b2.png','widget-b3.png'].every(file=>native.captures.filter(c=>c.file===file).length===1) : nativeEntries.every(Boolean);
      const page=await browser.newPage({viewport:{width,height},deviceScaleFactor:1});
      gallery+=`<section data-family="${family}"><h2>${family==='iphone'?'iPhone':'iPad'}</h2><div class="strip">`;
      for (const [id,title,subtitle,file] of captions) {
        if (!file && !complete) {gallery+='<article class="missing">01 · 위젯·아이콘<br>실제 네이티브 촬영 대기</article>';continue;}
        let content='', provenance=[];
        if (file) {
          const entry=original.devices.find(d=>d.deviceFamily===family).screenshots.find(s=>s.file===file);
          await verifiedFile(resolve(sourceRoot,family),entry);
          await copyFile(resolve(sourceRoot,family,file),resolve(dir,'source',file));
          content=`<img class="screen" src="source/${file}" alt="${esc(title)}">`; provenance=[{...entry,sourceFile:family+'/'+file}];
        } else if (component) {
          for (let i=0;i<3;i++) {
            const widgetName=i===2?'widget-b3.png':'widget-b2.png';
            const entry=native.captures.find(c=>c.file===widgetName);
            const bytes=await verifiedFile(nativeRoot,entry);
            await writeFile(resolve(dir,'source',widgetName),bytes);
            const iconPath='ios/Runner/Assets.xcassets/'+['AppIcon','AppIconFloorB2','AppIconFloorB3'][i]+'.appiconset/Icon-App-1024x1024@1x.png';
            const icon=await readFile(iconPath), iconName=states[i]+'-icon.png';
            await writeFile(resolve(dir,'source',iconName),icon);
            content+=`<figure><figcaption>${labels[i]}</figcaption><div class=pair><img class=widget src="source/${widgetName}" alt="주차 위젯"><span>+</span><img class=icon src="source/${iconName}" alt="${labels[i]} 앱 아이콘"></div></figure>`;
            provenance.push({...entry,captureSource:'native-component-render'}, {file:iconPath,sha256:hash(icon)});
          }
          content='<div class=example>위젯·아이콘 보기 예시</div><div class=components>'+content+'</div><p class=footnote>위젯은 직접 추가 · 층수 아이콘은 설정에서 켜기<br>위젯은 iOS 17 이상에서 지원해요. 아이콘을 바꿀 때 시스템 안내가 나타나요.<br>가족이 바꾼 층은 앱을 다시 열 때 아이콘에 반영돼요.</p>';
        } else {
          for (let i=0;i<3;i++) {
            const entry=nativeEntries[i], bytes=await verifiedFile(nativeRoot,entry), name=states[i]+(entry.file.endsWith('.png')?'.png':'.jpg');
            await writeFile(resolve(dir,'source',name),bytes);
            content+=`<figure><figcaption>${labels[i]}</figcaption><img src="source/${name}" alt="${labels[i]}"></figure>`; provenance.push(entry);
          }
          content='<div class="compare">'+content+'</div><p class="footnote">위젯은 홈 화면에 직접 추가해요. iPhone 층수 아이콘은 설정에서 켠 기기에 적용돼요.<br>아이콘 변경 시 시스템 안내가 표시되며, 가족이 바꾼 층은 앱을 다시 열 때 반영돼요.</p>';
        }
        const html=`<!doctype html><html lang="ko"><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;width:${width}px;height:${height}px;overflow:hidden;background:#f5f7fa;color:#1e293b;font-family:-apple-system,BlinkMacSystemFont,'Apple SD Gothic Neo',sans-serif;padding:${height*.045}px ${width*.065}px}.brand{font-size:${width*.025}px;color:#2563eb;font-weight:750;letter-spacing:.06em}h1{font-size:${width*.069}px;line-height:1.23;letter-spacing:-.045em;margin:40px 0 28px;white-space:pre-line}p{white-space:pre-line;font-size:${width*.027}px;line-height:1.6;color:#526176;margin:0 0 50px}.screen{display:block;height:${height*.72}px;max-width:100%;object-fit:contain;margin:auto;border-radius:35px;box-shadow:0 25px 65px #1e293b18}.compare{display:flex;gap:22px;margin-top:100px}.compare figure{margin:0;flex:1;min-width:0}.compare img{width:100%;border-radius:20px}.compare figcaption{font-size:${width*.022}px;font-weight:700;margin-bottom:25px}.example{font-size:32px;color:#2563eb;font-weight:700;margin:20px 0}.components{display:grid;gap:28px}.components figure{background:white;border:1px solid #e2e8f0;border-radius:30px;margin:0;padding:28px 40px}.components figcaption{font-size:36px;font-weight:700;margin-bottom:24px}.pair{display:flex;align-items:center;justify-content:space-evenly;gap:24px}.pair .widget{width:${Math.min(width*.31,height*.125)}px;border-radius:28px}.pair .icon{width:${Math.min(width*.19,height*.08)}px;border-radius:32px}.pair span{font-size:32px;color:#94a3b8}.footnote{font-size:${width*.022}px;margin-top:50px}</style><div class="brand">차자리 · 가족 주차 기록</div><h1>${esc(title)}</h1><p>${esc(subtitle)}</p>${content}</html>`;
        await writeFile(resolve(dir,id+'.html'),html); await page.goto(pathToFileURL(resolve(dir,id+'.html')).href);
        await page.evaluate(async()=>{await document.fonts.ready;await Promise.all([...document.images].map(i=>i.decode()));
          const screen=document.querySelector('.screen');
          if(screen){screen.style.height=Math.min(parseFloat(getComputedStyle(screen).height),innerHeight-screen.getBoundingClientRect().top-innerHeight*.035)+'px';screen.style.width='auto';}
          const components=document.querySelector('.components');
          if(components){
            const foot=document.querySelector('.footnote');
            const available=innerHeight-components.getBoundingClientRect().top-foot.getBoundingClientRect().height-90;
            if(components.getBoundingClientRect().height>available){
              const ratio=available/components.getBoundingClientRect().height;
              components.querySelectorAll('.widget,.icon').forEach(i=>i.style.width=i.getBoundingClientRect().width*ratio+'px');
              components.querySelectorAll('figure').forEach(f=>f.style.padding='20px 32px');
            }
          }
          for(const el of document.querySelectorAll('h1,p,img,.components,.compare')){const r=el.getBoundingClientRect();if(r.bottom>innerHeight-12||r.right>innerWidth||r.left<0)throw Error('Poster content clipped: '+el.tagName+' '+el.className);}
        });
        const bytes=await page.screenshot({type:'jpeg',quality:96});await writeFile(resolve(dir,id+'.jpg'),bytes);
        device.screenshots.push({file:id+'.jpg',width,height,hasAlpha:false,sha256:hash(bytes),provenance});
        gallery+=`<article><a href="${family}/${id}.jpg"><img src="${family}/${id}.jpg" alt="${esc(title)}"></a><p>${esc(title)}</p></article>`;
      }
      gallery+='</div>';
      if(complete && !component)gallery+='<details><summary>설정별 실제 촬영 원본 비교</summary>'+nativeEntries.map((e,i)=>`<figure><figcaption>${labels[i]}</figcaption><img width="240" src="${family}/source/${states[i]}${e.file.endsWith('.png')?'.png':'.jpg'}"></figure>`).join('')+'</details>';
      gallery+='</section>';manifest.devices.push(device);await page.close();
    }
  } finally {await browser.close();}
  manifest.submissionReady=native.captureSource !== 'native-component-render' && nativeComplete(native.captures);
  manifest.reviewRequired=native.captureSource === 'native-component-render';
  manifest.complete=manifest.devices.every(d=>d.screenshots.length===5);
  manifest.reviewNote=manifest.reviewRequired?'첫 장은 실제 제품 SwiftUI 위젯 렌더와 원본 아이콘을 조합한 보기 예시이며 홈 화면 실촬영이 아닙니다. 최종 제출 전 검토가 필요합니다.':null;
  await writeFile(resolve(output,manifest.submissionReady?'manifest.json':'review-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  await writeFile(resolve(output,'index.html'),`<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>차자리 스토어 미리보기</title><style>body{margin:32px;background:#f5f7fa;color:#1e293b;font:17px/1.6 -apple-system,sans-serif}.strip{display:flex;gap:20px;overflow:auto}article{flex:0 0 240px}article img{width:240px;border-radius:16px}.missing{background:#e2e8f0;padding:30px;border-radius:16px;min-height:400px}button{padding:12px 24px;margin-right:12px}details figure{display:inline-block}section[hidden]{display:none}</style><h1>차자리 · 스토어 미리보기</h1><p>${manifest.submissionReady?'새 스크린샷 5장 · 기기별 자료 준비 완료. 스토어에는 게시하지 않았습니다.':manifest.reviewRequired && manifest.complete?'5장 구성 완료 · 첫 장은 위젯·아이콘 보기 예시입니다. 최종 제출 전 검토가 필요하며 스토어에 게시하지 않았습니다.':'위젯·아이콘 실제 촬영 대기 · 나머지 4장 검토용. 제출용 manifest는 생성하지 않았습니다.'}</p><nav><button data-select="iphone">iPhone</button><button data-select="ipad">iPad</button></nav>${gallery}<script>function select(v){document.querySelectorAll('section').forEach(s=>s.hidden=s.dataset.family!==v);document.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.select===v))}document.querySelectorAll('button').forEach(b=>b.onclick=()=>select(b.dataset.select));select('iphone')</script></html>`);
  return manifest;
}
if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
 const arg=name=>{const i=process.argv.indexOf(name);return i<0?undefined:process.argv[i+1]};
 const result=await buildGallery({sourceRoot:resolve(arg('--source-root')||'build/app-store-media-20261111'),output:resolve(arg('--output')||'build/app-store-refresh-20261113/gallery'),nativeRoot:arg('--native-root'),playwrightModule:process.env.PLAYWRIGHT_MODULE,chrome:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});console.log(JSON.stringify({submissionReady:result.submissionReady,images:result.devices.map(d=>d.screenshots.length)}));
}
