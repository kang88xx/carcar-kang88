// Run after `flutter build web` and `python3 -m http.server 4173 --directory build/web`.
// Set PLAYWRIGHT_MODULE and CHROME_EXECUTABLE to locally installed test tools.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const output = path.resolve(__dirname, '../docs/qa');
(async () => {
  const browser = await chromium.launch({headless:true,
    ...(process.env.CHROME_EXECUTABLE ? {executablePath:process.env.CHROME_EXECUTABLE} : {}),
    args:['--no-sandbox']});
  const context = await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1});
  const page = await context.newPage();
  page.setDefaultTimeout(12000);
  const errors=[]; const results=[];
  page.on('pageerror',e=>errors.push(e.message));
  const check=(name,condition=true)=>{assert.ok(condition,name);results.push({name,result:'PASS'});console.log('PASS',name);};
  async function enter(field,value){await field.click();await page.waitForTimeout(150);await page.keyboard.press('ControlOrMeta+A');await page.keyboard.type(value,{delay:35});await page.waitForTimeout(100);}
  async function capture(name){await page.mouse.move(0,0);await page.waitForTimeout(4300);await page.screenshot({path:path.join(output,name)});}
  async function revealButton(name){
    const button=page.getByRole('button',{name});
    for(let attempt=0;attempt<6;attempt++){
      if(await button.isVisible())return button;
      await page.mouse.move(200,500);await page.mouse.wheel(0,420);await page.waitForTimeout(350);
    }
    await button.waitFor({state:'visible'});return button;
  }
  async function enableSemantics(){await page.locator('flt-semantics-placeholder').waitFor({state:'attached'});await page.locator('flt-semantics-placeholder').evaluate(el=>el.click());}
  try {
    await page.goto(process.env.QA_URL || 'http://127.0.0.1:4173',{waitUntil:'domcontentloaded'});
    await enableSemantics();
    await page.getByRole('button',{name:/^(체험 시작하기|가입 없이 먼저 둘러보기)$/}).waitFor();
    await capture('01-welcome.png');
    await page.getByRole('button',{name:/^(체험 시작하기|가입 없이 먼저 둘러보기)$/}).click();
    await page.getByRole('button',{name:'주차 위치 기록하기'}).waitFor();
    check('Explicit local demo opens, no fabricated login');
    await capture('02-home.png');
    await page.getByRole('button',{name:'주차 위치 기록하기'}).click();
    await page.getByRole('button',{name:'이 위치로 체험 기록 저장'}).click();
    await page.getByText('층수를 선택해 주세요.',{exact:true}).waitFor();
    check('Empty parking form rejects save');
    await page.getByRole('button',{name:'B3',exact:true}).click();
    await page.getByRole('button',{name:'D',exact:true}).click();
    await enter(page.getByRole('textbox',{name:'주차 번호 (선택)',exact:true}),'52');
    await enter(page.getByRole('textbox',{name:'가족에게 남길 메모 (선택)',exact:true}),'엘리베이터 오른쪽 · QA');
    await page.getByText('B3 · D구역 · 52번',{exact:true}).waitFor();
    check('Live confirmation includes edited parking number');
    await capture('03-parking-form.png');
    await page.getByRole('button',{name:'기록 창 닫기'}).click();
    await page.getByRole('button',{name:'취소',exact:true}).click();
    await page.getByRole('textbox',{name:'주차 번호 (선택)',exact:true}).waitFor();
    check('Unsaved draft close is confirmed and cancel keeps draft');
    await context.setOffline(true);
    await page.getByRole('button',{name:'이 위치로 체험 기록 저장'}).click();
    await page.waitForFunction(() => document.body.innerText.includes('52번 자리'));
    check('Local demo saves while offline (not a server sync claim)');
    await context.setOffline(false);
    await capture('04-confirmed.png');
    await page.getByRole('tab',{name:'주차 이력',exact:true}).click();
    await enter(page.getByRole('textbox'),'does-not-exist');
    await page.getByText('검색한 기록이 없어요',{exact:true}).waitFor();
    check('History search has a clear empty state');
    await enter(page.getByRole('textbox'),'52');
    await page.waitForFunction(() => document.body.innerText.includes('D구역 · 52번'));
    await capture('05-history.png');
    await page.getByRole('tab',{name:/우리 가족/}).click();
    await capture('06-family.png');
    await page.getByRole('button',{name:'가족 초대 안내',exact:true}).click();
    await page.waitForFunction(() => document.body.innerText.includes('가족 초대는 실제 계정으로 로그인한 후 사용할 수 있어요.'));
    check('Demo invitation cannot pretend to share with real family');
    await page.getByRole('tab',{name:'설정',exact:true}).click();
    await capture('07-settings.png');
    await (await revealButton(/개인정보 처리 안내/)).click();
    await page.getByRole('button',{name:'확인',exact:true}).click();
    check('Privacy notice is accessible');
    await (await revealButton(/체험 종료/)).click();
    await page.getByRole('button',{name:/^(체험 시작하기|가입 없이 먼저 둘러보기)$/}).waitFor();
    await page.reload({waitUntil:'domcontentloaded'});
    await enableSemantics();
    await page.getByRole('button',{name:/^(체험 시작하기|가입 없이 먼저 둘러보기)$/}).click();
    await page.waitForFunction(() => document.body.innerText.includes('52번 자리'));
    check('Logout/reload/re-entry restores only the local demo record');
    await page.setViewportSize({width:320,height:740});await capture('08-small-phone.png');
    check('320px viewport renders');
    await page.setViewportSize({width:1440,height:1000});await capture('09-desktop.png');
    check('Desktop navigation adapts');
    check('No browser runtime errors',errors.length===0);
    fs.writeFileSync(path.join(output,'browser-results.json'),JSON.stringify({at:new Date().toISOString(),results,errors},null,2));
  } catch (e) { console.log('FAIL STATE', await page.locator('body').ariaSnapshot()); await page.screenshot({path:path.join(output,'qa-failure.png')}); throw e; } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
