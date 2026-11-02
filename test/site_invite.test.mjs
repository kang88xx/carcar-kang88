import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseInviteCode, appInviteUrl, mountInvite } from '../site/invite/invite.mjs';
const code = '0123456789abcdef'.repeat(3);
function environment(hash, clipboard) {
  const elements = new Map(['open-app', 'copy-code', 'invite-code', 'code-area', 'status'].map(id => [id, {
    disabled: true, hidden: true, textContent: '', value: '', handlers: {},
    addEventListener(type, callback) { this.handlers[type] = callback; },
    focus() { this.focused = true; }, select() { this.selected = true; },
  }]));
  const navigations = [];
  const document = { getElementById: id => elements.get(id) };
  const location = { hash, search: `?invite_code=${code}`, assign: url => navigations.push(url) };
  mountInvite({ document, location, clipboard });
  return { elements, navigations, location };
}
test('canonical fragment maps exactly to the app deep link', () => {
  assert.equal(parseInviteCode(`#invite_code=${code}`), code);
  assert.equal(appInviteUrl(code), `com.kang88.carcar://invite?invite_code=${code}`);
});
test('rejects absent, duplicate, extra, encoded, uppercase, short and injected codes', () => {
  for (const input of [null, undefined, '', code, `?invite_code=${code}`, `#invite_code=${code.toUpperCase()}`, `#invite_code=${code.slice(1)}`, `#invite_code=${code}0`, `#invite_code=${code}&invite_code=${code}`, `#invite_code=${code}&next=evil`, `#invite_code=%30${code.slice(1)}`, '#invite_code=<script>alert(1)</script>', `#invite_code=${code}\n`, '#other=value']) {
    assert.equal(parseInviteCode(input), null, String(input));
  }
  for (const input of ['', 'javascript:alert(1)', '<img>', code.toUpperCase()]) assert.equal(appInviteUrl(input), null);
});
test('never auto-navigates; valid code opens only on explicit click', () => {
  const { elements, navigations } = environment(`#invite_code=${code}`);
  assert.deepEqual(navigations, []);
  assert.equal(elements.get('open-app').disabled, false);
  assert.equal(elements.get('invite-code').value, code);
  elements.get('open-app').handlers.click();
  assert.deepEqual(navigations, [`com.kang88.carcar://invite?invite_code=${code}`]);
});
test('query-only or hostile input leaves both actions disabled and code empty', () => {
  for (const hash of ['', '#invite_code=<img src=x onerror=alert(1)>']) {
    const { elements, navigations } = environment(hash);
    assert.equal(elements.get('open-app').disabled, true);
    assert.equal(elements.get('copy-code').disabled, true);
    assert.equal(elements.get('invite-code').value, '');
    assert.equal(elements.get('code-area').hidden, true);
    assert.deepEqual(navigations, []);
    assert.deepEqual(elements.get('open-app').handlers, {});
    assert.ok(!elements.get('status').textContent.includes('<img'));
  }
});
test('copies only the raw code and does not launch or redeem the invitation', async () => {
  const copied = [];
  const { elements, navigations } = environment(`#invite_code=${code}`, { writeText: async text => copied.push(text) });
  assert.deepEqual(copied, []);
  await elements.get('copy-code').handlers.click();
  assert.deepEqual(copied, [code]);
  assert.deepEqual(navigations, []);
  assert.match(elements.get('status').textContent, /복사했어요/);
});
test('denied or missing Clipboard API exposes manual selection without false success', async () => {
  for (const clipboard of [undefined, { writeText: async () => { throw new Error('denied'); } }]) {
    const { elements } = environment(`#invite_code=${code}`, clipboard);
    await elements.get('copy-code').handlers.click();
    assert.equal(elements.get('invite-code').focused, true);
    assert.equal(elements.get('invite-code').selected, true);
    assert.match(elements.get('status').textContent, /직접 복사/);
    assert.doesNotMatch(elements.get('status').textContent, /복사했어요/);
  }
});
test('invite document blocks connections, disables referrer, and has no external scripts', async () => {
  const html = await readFile(new URL('../site/invite/index.html', import.meta.url), 'utf8');
  const js = await readFile(new URL('../site/invite/invite.mjs', import.meta.url), 'utf8');
  assert.match(html, /connect-src 'none'/);
  assert.match(html, /name="referrer" content="no-referrer"/);
  assert.doesNotMatch(html, /<script[^>]+src="https?:/);
  assert.doesNotMatch(js, /\b(fetch|XMLHttpRequest|sendBeacon|innerHTML|localStorage|sessionStorage)\b/);
});
