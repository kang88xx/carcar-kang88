// Capture the same local demo state before and after UI changes.
// Build and serve build/web first. Uses the same browser tooling as browser_qa.cjs.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

(async () => {
  const output = path.resolve(process.env.DESIGN_QA_OUTPUT || 'docs/qa/ui-redesign/after');
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_EXECUTABLE ? { executablePath: process.env.CHROME_EXECUTABLE } : {}),
    args: ['--no-sandbox'],
  });
  const page = await browser.newPage({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, timezoneId: 'Asia/Seoul',
  });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  // Keep the greeting, local demo timestamps and comparison captures reproducible.
  await page.clock.setFixedTime(new Date('2026-11-04T03:00:00Z'));
  page.setDefaultTimeout(15000);
  async function capture(name) {
    await page.mouse.move(0, 0);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(output, `${name}.png`) });
  }
  try {
    await page.goto(process.env.QA_URL || 'http://127.0.0.1:4173', { waitUntil: 'domcontentloaded' });
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor({ state: 'attached' });
    await semantics.evaluate(el => el.click());
    await page.getByRole('button', { name: '체험 시작하기', exact: true }).click();
    const record = page.getByRole('button', { name: '주차 위치 기록하기', exact: true });
    await record.waitFor();
    await capture('home-390');
    const bounds = { record: await record.boundingBox() };
    await record.click();
    await page.getByRole('button', { name: 'B3', exact: true }).click();
    await page.getByRole('button', { name: 'D', exact: true }).click();
    await capture('form-390');
    bounds.save = await page.getByRole('button', { name: '이 위치로 체험 기록 저장', exact: true }).boundingBox();
    await page.getByRole('button', { name: '이 위치로 체험 기록 저장', exact: true }).click();
    await page.getByRole('dialog').waitFor({ state: 'hidden' });
    await page.waitForFunction(() => document.body.innerText.includes('D구역'));
    await page.getByRole('tab', { name: '주차 이력', exact: true }).click();
    await capture('history-390');
    await page.getByRole('tab', { name: '우리 가족', exact: true }).click();
    await capture('family-390');
    await page.getByRole('tab', { name: '설정', exact: true }).click();
    await capture('settings-390');
    await page.getByRole('tab', { name: '주차 위치', exact: true }).click();
    await page.setViewportSize({ width: 320, height: 740 });
    await capture('home-320');
    await page.getByRole('button', { name: '주차 위치 기록하기', exact: true }).click();
    await capture('form-320');
    await page.getByRole('button', { name: '기록 창 닫기', exact: true }).click();
    await page.setViewportSize({ width: 1440, height: 1000 });
    await capture('home-desktop');
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({ errors, bounds }, null, 2));
    console.log(`PASS: home, parking save, history, family, settings, 320px and desktop captures: ${output}`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
