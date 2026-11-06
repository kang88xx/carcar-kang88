import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import {ensureTesters, parseTesters, pickInternalGroup, safeApiUrl} from './testflight_testers.mjs';

const key = Buffer.from(generateKeyPairSync('ec', {namedCurve: 'prime256v1'}).privateKey.export({type: 'pkcs8', format: 'pem'})).toString('base64');
const baseEnv = {APP_STORE_CONNECT_API_KEY_P8_BASE64: key, APP_STORE_CONNECT_ISSUER_ID: '12345678-1234-1234-1234-123456789abc', APP_STORE_CONNECT_KEY_ID: 'ABCDEFGHIJ', BUILD_NUMBER: '7'};

function fakeApple(state) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    const path = url.pathname + url.search;
    calls.push(init.method + ' ' + url.pathname);
    const json = data => ({ok: true, status: 200, json: async () => data});
    if (init.method === 'PATCH') { state.group.attributes.hasAccessToAllBuilds = true; return json({data: state.group}); }
    if (init.method === 'POST' && url.pathname.endsWith('/relationships/builds')) { state.groupBuilds.push({type: 'builds', id: 'b7'}); return {ok: true, status: 204}; }
    if (init.method === 'POST' && url.pathname.endsWith('/relationships/betaTesters')) { state.members.push({type: 'betaTesters', id: 't1'}); return {ok: true, status: 204}; }
    if (init.method === 'POST' && url.pathname === '/v1/betaTesterInvitations') { state.invites++; return json({data: {type: 'betaTesterInvitations', id: 'i1'}}); }
    if (path.startsWith('/v1/apps/6829616379/betaGroups')) return json({data: [state.externalGroup, state.group]});
    if (path.startsWith('/v1/builds')) return json({data: [{type: 'builds', id: 'b7', attributes: {version: '7', processingState: 'VALID', expired: false}}]});
    if (path.startsWith('/v1/betaGroups/g1/relationships/builds')) return json({data: state.groupBuilds});
    if (path.startsWith('/v1/betaGroups/g1/betaTesters')) return json({data: state.members});
    if (path.startsWith('/v1/betaTesters?')) return json({data: state.tester ? [state.tester] : []});
    return {ok: false, status: 404, json: async () => ({})};
  };
  return {fetchImpl, calls};
}

function freshState() {
  return {
    group: {type: 'betaGroups', id: 'g1', attributes: {name: 'Internal', isInternalGroup: true, hasAccessToAllBuilds: false}},
    externalGroup: {type: 'betaGroups', id: 'g2', attributes: {name: 'External', isInternalGroup: false, hasAccessToAllBuilds: false}},
    groupBuilds: [], members: [], invites: 0,
    tester: {type: 'betaTesters', id: 't1', attributes: {email: 'KSLEE324@gmail.com', state: 'INVITED'}},
  };
}

test('read-only mode reports gaps without writing', async () => {
  const state = freshState();
  const {fetchImpl, calls} = fakeApple(state);
  const summary = await ensureTesters(baseEnv, fetchImpl);
  assert.equal(summary.mode, 'read-only');
  assert.equal(summary.ready, false);
  assert.deepEqual(summary.missingTesters, ['kslee324@gmail.com']);
  assert.equal(summary.build.version, '7');
  assert.equal(summary.group.distributionError, null);
  assert.equal(summary.group.hasAccessToAllBuilds, false);
  assert.ok(calls.every(call => call.startsWith('GET ')));
  assert.deepEqual(summary.writes, []);
});

test('ensure mode enables distribution, adds build and tester, resends invitation', async () => {
  const state = freshState();
  const {fetchImpl} = fakeApple(state);
  const summary = await ensureTesters({...baseEnv, ENSURE: 'true'}, fetchImpl);
  assert.equal(summary.ready, true);
  assert.equal(summary.group.hasAccessToAllBuilds, true);
  assert.equal(summary.group.distributionEnabledNow, true);
  assert.equal(summary.build.groupContainsBuild, true);
  assert.equal(summary.build.addedNow, true);
  assert.deepEqual(summary.testers[0], {email: 'kslee324@gmail.com', exists: true, inGroup: true, state: 'INVITED', addedToGroup: true, invitationResent: true});
  assert.equal(state.invites, 1);
  assert.deepEqual(summary.writes, ['PATCH /v1/betaGroups/g1', 'POST /v1/betaGroups/g1/relationships/builds', 'POST /v1/betaGroups/g1/relationships/betaTesters', 'POST /v1/betaTesterInvitations']);
});

for (const testerState of ['NOT_INVITED', 'INVITED']) {
  test(`invitation opt-out preserves group and build association for ${testerState}`, async () => {
    const state = freshState();
    state.tester.attributes.state = testerState;
    const {fetchImpl, calls} = fakeApple(state);
    const summary = await ensureTesters({...baseEnv, ENSURE: 'true', SEND_INVITATIONS: 'false'}, fetchImpl);
    assert.equal(summary.ready, true);
    assert.equal(summary.group.distributionEnabledNow, true);
    assert.equal(summary.build.groupContainsBuild, true);
    assert.equal(summary.build.addedNow, true);
    assert.equal(summary.testers[0].inGroup, true);
    assert.equal(summary.testers[0].addedToGroup, true);
    assert.equal(summary.testers[0].invitationResent, false);
    assert.equal(state.invites, 0);
    assert.ok(!calls.includes('POST /v1/betaTesterInvitations'));
    assert.deepEqual(summary.writes, ['PATCH /v1/betaGroups/g1', 'POST /v1/betaGroups/g1/relationships/builds', 'POST /v1/betaGroups/g1/relationships/betaTesters']);
  });
}

test('a refused distribution flag is reported and the build is still added', async () => {
  const state = freshState();
  state.members.push({type: 'betaTesters', id: 't1'});
  state.tester.attributes.state = 'ACCEPTED';
  const {fetchImpl} = fakeApple(state);
  const refusing = async (url, init) => init.method === 'PATCH'
    ? {ok: false, status: 409, json: async () => ({errors: [{code: 'ENTITY_ERROR', title: 'Conflict', detail: 'cannot change'}]})}
    : fetchImpl(url, init);
  const summary = await ensureTesters({...baseEnv, ENSURE: 'true'}, refusing);
  assert.equal(summary.ready, true);
  assert.equal(summary.group.hasAccessToAllBuilds, false);
  assert.match(summary.group.distributionError, /409.*ENTITY_ERROR/);
  assert.equal(summary.build.addedNow, true);
});

test('accepted tester already in group needs no writes', async () => {
  const state = freshState();
  state.group.attributes.hasAccessToAllBuilds = true;
  state.groupBuilds.push({type: 'builds', id: 'b7'});
  state.members.push({type: 'betaTesters', id: 't1'});
  state.tester.attributes.state = 'ACCEPTED';
  const {fetchImpl} = fakeApple(state);
  const summary = await ensureTesters({...baseEnv, ENSURE: 'true'}, fetchImpl);
  assert.equal(summary.ready, true);
  assert.deepEqual(summary.writes, []);
  assert.equal(summary.testers[0].invitationResent, false);
});

test('missing tester is reported, never created', async () => {
  const state = freshState();
  state.tester = null;
  const {fetchImpl, calls} = fakeApple(state);
  const summary = await ensureTesters({...baseEnv, ENSURE: 'true', TESTER_EMAILS: 'kslee324@gmail.com, other@example.com'}, fetchImpl);
  assert.equal(summary.ready, false);
  assert.deepEqual(summary.missingTesters, ['kslee324@gmail.com', 'other@example.com']);
  assert.ok(!calls.some(call => call === 'POST /v1/betaTesters'));
});

test('inputs and destinations are validated', () => {
  assert.throws(() => safeApiUrl('https://example.com/v1/apps'), /destination/);
  assert.throws(() => safeApiUrl('/v1/certificates'), /destination/);
  assert.deepEqual(parseTesters(''), ['kslee324@gmail.com']);
  assert.throws(() => parseTesters('not-an-email'), /email/);
  assert.throws(() => pickInternalGroup([{attributes: {isInternalGroup: false}}]), /internal/);
  assert.rejects(ensureTesters({...baseEnv, BUILD_NUMBER: 'x'}, async () => ({ok: true})), /build number/);
  assert.rejects(ensureTesters({...baseEnv, APP_STORE_CONNECT_KEY_ID: 'bad'}, async () => ({ok: true})), /key identifier/);
});
