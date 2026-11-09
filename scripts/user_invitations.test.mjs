import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import {manageInvitations, parseEmail, parseName, safeApiUrl} from './user_invitations.mjs';

const key = Buffer.from(generateKeyPairSync('ec', {namedCurve: 'prime256v1'}).privateKey.export({type: 'pkcs8', format: 'pem'})).toString('base64');
const baseEnv = {
  APP_STORE_CONNECT_API_KEY_P8_BASE64: key, APP_STORE_CONNECT_ISSUER_ID: '12345678-1234-1234-1234-123456789abc', APP_STORE_CONNECT_KEY_ID: 'ABCDEFGHIJ',
  INVITE_EMAIL: 'New.Tester@gmail.com', INVITE_FIRST_NAME: '이슬', INVITE_LAST_NAME: '한', CANCEL_EMAIL: 'old@naver.com',
};

function fakeApple(state) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push(init.method + ' ' + url.pathname + url.search);
    const json = data => ({ok: true, status: 200, json: async () => data});
    if (init.method === 'DELETE') { state.invitations = state.invitations.filter(item => item.id !== url.pathname.split('/').pop()); return {ok: true, status: 204}; }
    if (init.method === 'POST') { state.created.push(JSON.parse(init.body).data); return json({data: {type: 'userInvitations', id: 'new'}}); }
    if (url.pathname === '/v1/users') {
      const email = url.searchParams.get('filter[username]');
      return json({data: state.users.filter(user => user.attributes.username === email)});
    }
    if (url.pathname === '/v1/userInvitations') {
      const email = url.searchParams.get('filter[email]');
      return json({data: state.invitations.filter(item => item.attributes.email === email)});
    }
    return {ok: false, status: 404, json: async () => ({})};
  };
  return {fetchImpl, calls};
}

const freshState = () => ({
  users: [], created: [],
  invitations: [{type: 'userInvitations', id: 'inv-old', attributes: {email: 'old@naver.com', roles: ['MARKETING'], expirationDate: '2026-11-11T00:00:00Z'}}],
});

test('read-only mode reports both addresses and never writes', async () => {
  const state = freshState();
  const {fetchImpl, calls} = fakeApple(state);
  const summary = await manageInvitations(baseEnv, fetchImpl);
  assert.equal(summary.mode, 'read-only');
  assert.equal(summary.cancel.invitations.length, 1);
  assert.equal(summary.cancel.cancelledInvitations.length, 0);
  assert.equal(summary.invite.email, 'new.tester@gmail.com');
  assert.equal(summary.invite.invitationSent, false);
  assert.equal(summary.ready, false);
  assert.ok(calls.every(call => call.startsWith('GET ')));
  assert.deepEqual(summary.writes, []);
});

test('apply cancels the stale invitation and invites the replacement for this app only', async () => {
  const state = freshState();
  const {fetchImpl} = fakeApple(state);
  const summary = await manageInvitations({...baseEnv, APPLY: 'true'}, fetchImpl);
  assert.deepEqual(summary.cancel.cancelledInvitations, ['inv-old']);
  assert.equal(summary.invite.invitationSent, true);
  assert.equal(summary.ready, true);
  assert.deepEqual(summary.writes, ['DELETE /v1/userInvitations/inv-old', 'POST /v1/userInvitations']);
  assert.equal(state.invitations.length, 0);
  assert.deepEqual(state.created[0].attributes, {email: 'new.tester@gmail.com', firstName: '이슬', lastName: '한', roles: ['MARKETING'], allAppsVisible: false, provisioningAllowed: false});
  assert.deepEqual(state.created[0].relationships.visibleApps.data, [{type: 'apps', id: '6829616379'}]);
});

test('apply never cancels an accepted user and does not duplicate a pending invitation', async () => {
  const state = freshState();
  state.users.push({type: 'users', id: 'u1', attributes: {username: 'old@naver.com', roles: ['MARKETING']}});
  state.invitations.push({type: 'userInvitations', id: 'inv-new', attributes: {email: 'new.tester@gmail.com', roles: ['MARKETING']}});
  const {fetchImpl} = fakeApple(state);
  const summary = await manageInvitations({...baseEnv, APPLY: 'true'}, fetchImpl);
  assert.equal(summary.cancel.skippedActiveUser, true);
  assert.deepEqual(summary.cancel.cancelledInvitations, []);
  assert.equal(summary.invite.invitationSent, false);
  assert.equal(summary.invite.pendingBefore, 1);
  assert.equal(summary.ready, true);
  assert.deepEqual(summary.writes, []);
});

test('resend replaces a pending invitation', async () => {
  const state = freshState();
  state.invitations.push({type: 'userInvitations', id: 'inv-new', attributes: {email: 'new.tester@gmail.com', roles: ['MARKETING']}});
  const {fetchImpl} = fakeApple(state);
  const summary = await manageInvitations({...baseEnv, APPLY: 'true', RESEND: 'true', CANCEL_EMAIL: ''}, fetchImpl);
  assert.equal(summary.cancel, null);
  assert.deepEqual(summary.invite.replacedInvitations, ['inv-new']);
  assert.equal(summary.invite.invitationSent, true);
  assert.deepEqual(summary.writes, ['DELETE /v1/userInvitations/inv-new', 'POST /v1/userInvitations']);
});

test('resend retries a transient duplicate-email conflict after cancelling', async () => {
  const state = freshState();
  state.invitations.push({type: 'userInvitations', id: 'inv-new', attributes: {email: 'new.tester@gmail.com', roles: ['MARKETING']}});
  const {fetchImpl} = fakeApple(state);
  let conflicts = 2;
  const flaky = async (url, init) => {
    if (init.method === 'POST' && conflicts-- > 0) return {ok: false, status: 409, json: async () => ({errors: [{code: 'ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE', title: 'Duplicate', detail: 'The email is already being used.'}]})};
    return fetchImpl(url, init);
  };
  const waits = [];
  const summary = await manageInvitations({...baseEnv, APPLY: 'true', RESEND: 'true', CANCEL_EMAIL: ''}, flaky, async ms => { waits.push(ms); });
  assert.equal(summary.invite.invitationSent, true);
  assert.deepEqual(waits, [5000, 10000]);
  assert.equal(state.created.length, 1);
});

test('a duplicate conflict without a prior cancellation is not retried', async () => {
  const state = freshState();
  const flaky = async (url, init) => {
    if (init.method === 'POST') return {ok: false, status: 409, json: async () => ({errors: [{code: 'ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE', title: 'Duplicate', detail: 'The email is already being used.'}]})};
    return fakeApple(state).fetchImpl(url, init);
  };
  const waits = [];
  await assert.rejects(manageInvitations({...baseEnv, APPLY: 'true', CANCEL_EMAIL: ''}, flaky, async ms => { waits.push(ms); }), /HTTP 409/);
  assert.deepEqual(waits, []);
});

test('input validation blocks unsafe values and destinations', async () => {
  assert.throws(() => safeApiUrl('/v1/apps/6829616379'), /destination/);
  assert.throws(() => safeApiUrl('https://evil.example/v1/users'), /destination/);
  assert.throws(() => parseEmail('not-an-email', 'invite'), /Invalid invite email/);
  assert.throws(() => parseName('<script>', 'first name'), /Invalid first name/);
  await assert.rejects(manageInvitations({...baseEnv, INVITE_ROLE: 'ADMIN'}), /Unsupported role/);
  await assert.rejects(manageInvitations({...baseEnv, CANCEL_EMAIL: baseEnv.INVITE_EMAIL}), /must differ/);
  await assert.rejects(manageInvitations({...baseEnv, INVITE_EMAIL: '', CANCEL_EMAIL: ''}), /Provide/);
  await assert.rejects(manageInvitations({...baseEnv, INVITE_FIRST_NAME: ''}), /Invalid first name/);
});

test('Apple errors are surfaced without secrets', async () => {
  const fetchImpl = async () => ({ok: false, status: 403, json: async () => ({errors: [{code: 'FORBIDDEN', title: 'Forbidden', detail: 'Key lacks access.'}]})});
  await assert.rejects(manageInvitations(baseEnv, fetchImpl), error => {
    assert.match(error.message, /HTTP 403 for GET \/v1\/users \(FORBIDDEN: Forbidden: Key lacks access\.\)/);
    assert.ok(!error.message.includes(key));
    return true;
  });
});
