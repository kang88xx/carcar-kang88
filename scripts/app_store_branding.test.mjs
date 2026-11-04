import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import {safeBrandingUrl, syncAppStoreBranding} from './app_store_branding.mjs';

const key = Buffer.from(generateKeyPairSync('ec', {namedCurve: 'prime256v1'}).privateKey.export({type: 'pkcs8', format: 'pem'})).toString('base64');
const env = {APP_STORE_CONNECT_API_KEY_P8_BASE64: key, APP_STORE_CONNECT_ISSUER_ID: '12345678-1234-1234-1234-123456789abc', APP_STORE_CONNECT_KEY_ID: 'ABCDEFGHIJ'};
const ensureEnv = {...env, ENSURE_BRANDING: 'true'};
const json = data => ({ok: true, status: 200, json: async () => structuredClone(data)});
function state() {
  return {
    app: {type: 'apps', id: '6829616379', attributes: {name: '차곡 - 가족 주차 기록', bundleId: 'com.kang88.carcar', primaryLocale: 'ko'}},
    infos: [{type: 'appInfos', id: 'info1', attributes: {state: 'PREPARE_FOR_SUBMISSION'}}],
    localizations: {info1: [{type: 'appInfoLocalizations', id: 'loc1', attributes: {locale: 'ko', name: '차곡 - 가족 주차 기록', subtitle: 'Keep this subtitle'}}]},
    groups: [{type: 'betaGroups', id: 'group1', attributes: {name: '차곡 내부 테스트', isInternalGroup: true, hasAccessToAllBuilds: false}},
      {type: 'betaGroups', id: 'external', attributes: {name: '차곡 내부 테스트', isInternalGroup: false}}],
  };
}
function fakeApple(data, hook) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    assert.equal(init.redirect, 'error');
    assert.match(init.headers.Authorization, /^Bearer [^.]+\.[^.]+\.[^.]+$/);
    const call = {method: init.method, path: url.pathname, body: init.body ? JSON.parse(init.body) : undefined};
    calls.push(call);
    const intercepted = hook?.(call, url);
    if (intercepted) return intercepted;
    const resources = [data.app, ...data.infos, ...Object.values(data.localizations).flat(), ...data.groups];
    if (init.method === 'PATCH') {
      const item = resources.find(item => url.pathname === '/v1/' + item.type + '/' + item.id);
      assert.ok(item);
      Object.assign(item.attributes, call.body.data.attributes);
      if (item.type === 'appInfoLocalizations' && item.attributes.locale === data.app.attributes.primaryLocale) data.app.attributes.name = item.attributes.name;
      return json({data: item});
    }
    if (url.pathname === '/v1/apps/6829616379/appInfos') return json({data: data.infos});
    if (url.pathname === '/v1/apps/6829616379/betaGroups') return json({data: data.groups});
    const localizations = url.pathname.match(/^\/v1\/appInfos\/([^/]+)\/appInfoLocalizations$/);
    if (localizations) return json({data: data.localizations[localizations[1]] ?? []});
    const item = resources.find(item => url.pathname === '/v1/' + item.type + '/' + item.id);
    return item ? json({data: item}) : {ok: false, status: 404};
  };
  return {fetchImpl, calls};
}

test('read-only reports old app and group names without PATCH', async () => {
  const {fetchImpl, calls} = fakeApple(state());
  const result = await syncAppStoreBranding(env, fetchImpl);
  assert.equal(result.ready, false);
  assert.equal(result.mode, 'read-only');
  assert.equal(result.app.nameBefore, '차곡 - 가족 주차 기록');
  assert.equal(result.appInfos[0].localizations[0].locale, 'ko');
  assert.deepEqual(result.writes, []);
  assert.ok(calls.every(call => call.method === 'GET'));
});

test('known names update with minimal PATCH then independent GET verification', async () => {
  const data = state(), {fetchImpl, calls} = fakeApple(data);
  const result = await syncAppStoreBranding(ensureEnv, fetchImpl);
  assert.equal(result.ready, true);
  assert.equal(result.app.name, '차자리');
  assert.equal(result.app.nameBefore, '차곡 - 가족 주차 기록');
  assert.deepEqual(calls.filter(call => call.method === 'PATCH'), [
    {method: 'PATCH', path: '/v1/appInfoLocalizations/loc1', body: {data: {type: 'appInfoLocalizations', id: 'loc1', attributes: {name: '차자리'}}}},
    {method: 'PATCH', path: '/v1/betaGroups/group1', body: {data: {type: 'betaGroups', id: 'group1', attributes: {name: '차자리 내부 테스트'}}}},
  ]);
  for (const path of ['/v1/appInfoLocalizations/loc1', '/v1/betaGroups/group1']) {
    const index = calls.findIndex(call => call.method === 'PATCH' && call.path === path);
    assert.deepEqual(calls[index + 1], {method: 'GET', path, body: undefined});
  }
  assert.equal(data.localizations.info1[0].attributes.subtitle, 'Keep this subtitle');
  assert.equal(data.groups[0].attributes.hasAccessToAllBuilds, false);
  assert.equal(data.groups[1].attributes.name, '차곡 내부 테스트');
  assert.ok(!calls.some(call => /invitation|betaTester|relationships/i.test(call.path)));
});

test('already-correct brand is idempotent', async () => {
  const data = state(), {fetchImpl, calls} = fakeApple(data);
  await syncAppStoreBranding(ensureEnv, fetchImpl);
  calls.length = 0;
  const result = await syncAppStoreBranding(ensureEnv, fetchImpl);
  assert.equal(result.ready, true);
  assert.deepEqual(result.writes, []);
  assert.ok(calls.every(call => call.method === 'GET'));
});

test('wrong app setting, returned app identity, and bundle are rejected before writes', async () => {
  let fetched = false;
  await assert.rejects(syncAppStoreBranding({...ensureEnv, CARCAR_APP_ID: '999'}, async () => { fetched = true; }), /restricted/);
  assert.equal(fetched, false);
  for (const mutation of [data => {data.app.id = '999';}, data => {data.app.attributes.bundleId = 'com.other.app';}]) {
    const data = state(); mutation(data);
    const {fetchImpl, calls} = fakeApple(data, call => call.path === '/v1/apps/6829616379' ? json({data: data.app}) : null);
    await assert.rejects(syncAppStoreBranding(ensureEnv, fetchImpl), /Unexpected/);
    assert.ok(calls.every(call => call.method === 'GET'));
  }
});

test('unknown app or localization names block all writes', async () => {
  for (const mutation of [data => {data.app.attributes.name = 'Another brand';}, data => {data.localizations.info1[0].attributes.name = 'Another brand';}]) {
    const data = state(); mutation(data);
    const {fetchImpl, calls} = fakeApple(data);
    const result = await syncAppStoreBranding(ensureEnv, fetchImpl);
    assert.equal(result.ready, false);
    assert.ok(result.blockers.some(item => /Unexpected/.test(item)));
    assert.ok(calls.every(call => call.method === 'GET'));
  }
});

test('only PREPARE_FOR_SUBMISSION is editable and deprecated state is supported', async () => {
  for (const stateName of ['IN_REVIEW', 'READY_FOR_SALE', 'UNKNOWN_STATE']) {
    const data = state(); data.infos[0].attributes.state = stateName;
    const {fetchImpl, calls} = fakeApple(data);
    const result = await syncAppStoreBranding(ensureEnv, fetchImpl);
    assert.equal(result.ready, false);
    assert.ok(calls.every(call => call.method === 'GET'));
  }
  const data = state(); data.infos[0].attributes = {appStoreState: 'PREPARE_FOR_SUBMISSION'};
  assert.equal((await syncAppStoreBranding(ensureEnv, fakeApple(data).fetchImpl)).ready, true);
});

test('live and editable information are separated; historical live metadata is untouched', async () => {
  const data = state();
  data.infos.unshift({type: 'appInfos', id: 'live', attributes: {state: 'READY_FOR_SALE'}});
  data.localizations.live = [{type: 'appInfoLocalizations', id: 'oldlive', attributes: {locale: 'ko', name: '차곡'}}];
  const {fetchImpl, calls} = fakeApple(data);
  const result = await syncAppStoreBranding(ensureEnv, fetchImpl);
  assert.equal(result.ready, true);
  assert.equal(data.localizations.live[0].attributes.name, '차곡');
  assert.ok(!calls.some(call => call.method === 'PATCH' && call.path.includes('oldlive')));
});

test('non-Korean primary locale retains its locale while correcting known Korean brand', async () => {
  const data = state(); data.app.attributes.primaryLocale = 'en-US'; data.localizations.info1[0].attributes.locale = 'en-US';
  data.localizations.info1.push({type: 'appInfoLocalizations', id: 'fr', attributes: {locale: 'fr-FR', name: 'Existing French name'}});
  const {fetchImpl, calls} = fakeApple(data);
  assert.equal((await syncAppStoreBranding(ensureEnv, fetchImpl)).ready, true);
  assert.equal(data.localizations.info1[0].attributes.locale, 'en-US');
  assert.equal(data.localizations.info1[1].attributes.name, 'Existing French name');
  assert.ok(!calls.some(call => call.method === 'PATCH' && call.path.endsWith('/fr')));
});

test('old name in unexpected locale blocks mutation', async () => {
  const data = state(); data.localizations.info1.push({type: 'appInfoLocalizations', id: 'fr', attributes: {locale: 'fr-FR', name: '차곡'}});
  const {fetchImpl, calls} = fakeApple(data);
  assert.equal((await syncAppStoreBranding(ensureEnv, fetchImpl)).ready, false);
  assert.ok(calls.every(call => call.method === 'GET'));
});

test('untrusted pagination destinations and changed collection paths cannot receive credentials', async () => {
  for (const next of ['https://evil.example/v1/apps/6829616379/appInfos', '/v1/apps/6829616379/betaGroups']) {
    const {fetchImpl, calls} = fakeApple(state(), call => call.path.endsWith('/appInfos') ? json({data: [], links: {next}}) : null);
    await assert.rejects(syncAppStoreBranding(ensureEnv, fetchImpl), /destination|pagination/);
    assert.equal(calls.length, 2);
  }
  for (const url of ['https://evil.example/v1/apps/6829616379', 'https://user:secret@api.appstoreconnect.apple.com/v1/apps/6829616379', '/v1/apps/999', '/v1/betaTesterInvitations', '/v1/betaGroups/id/relationships/betaTesters', '/v1/appInfoLocalizations/id#fragment']) {
    assert.throws(() => safeBrandingUrl(url), /destination/);
  }
});

test('API errors and transport errors never expose provider bodies or credentials', async () => {
  const secret = 'sensitive-token-from-provider';
  await assert.rejects(syncAppStoreBranding(env, async () => ({ok: false, status: 403, json: async () => ({errors: [{detail: secret}]})})), error => {
    assert.match(error.message, /HTTP 403/);
    assert.ok(!error.message.includes(secret));
    assert.ok(!error.message.includes(key));
    return true;
  });
  await assert.rejects(syncAppStoreBranding(env, async () => { throw new Error(secret); }), error => {
    assert.equal(error.message, 'Apple API request failed or timed out.');
    return true;
  });
});

test('failed readback stops before the next write', async () => {
  const data = state();
  const {fetchImpl, calls} = fakeApple(data, call => call.method === 'GET' && call.path === '/v1/appInfoLocalizations/loc1'
    ? json({data: {type: 'appInfoLocalizations', id: 'loc1', attributes: {locale: 'ko', name: '차곡'}}}) : null);
  await assert.rejects(syncAppStoreBranding(ensureEnv, fetchImpl), /did not confirm/);
  assert.equal(calls.filter(call => call.method === 'PATCH').length, 1);
});

test('missing primary localization and ambiguous editable records block all writes', async () => {
  for (const mutate of [
    data => { data.localizations.info1 = []; },
    data => { data.infos.push({type: 'appInfos', id: 'info2', attributes: {state: 'PREPARE_FOR_SUBMISSION'}}); data.localizations.info2 = []; },
    data => { data.groups = []; },
  ]) {
    const data = state(); mutate(data);
    const {fetchImpl, calls} = fakeApple(data);
    const result = await syncAppStoreBranding(ensureEnv, fetchImpl);
    assert.equal(result.ready, false);
    assert.ok(result.blockers.length > 0);
    assert.ok(calls.every(call => call.method === 'GET'));
  }
});

test('untrusted resource identity and invalid key fail with bounded errors', async () => {
  const data = state(); data.localizations.info1[0].id = '../other';
  const {fetchImpl, calls} = fakeApple(data);
  await assert.rejects(syncAppStoreBranding(ensureEnv, fetchImpl), /resource identity/);
  assert.ok(calls.every(call => call.method === 'GET'));
  await assert.rejects(syncAppStoreBranding({...env, APP_STORE_CONNECT_API_KEY_P8_BASE64: 'not-a-key'}, fetchImpl), /Invalid App Store Connect private key/);
});
