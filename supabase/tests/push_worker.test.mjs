import test from 'node:test';
import assert from 'node:assert/strict';
import {authorized, classifyResponse, createPushSender, createWorker, retrySeconds} from '../functions/parking-push/core.mjs';

const jobId = '11111111-1111-4111-8111-111111111111';
const lease = '22222222-2222-4222-8222-222222222222';
const vehicle = '33333333-3333-4333-8333-333333333333';
const clock = 1793600000000;
const delivery = {job_id: jobId, vehicle_id: vehicle, expires_at: Math.floor(clock / 1000) + 3600,
  provider: 'apns', environment: 'production', token: 'a'.repeat(64)};
const secret = 'test-worker-secret-is-at-least-32-characters';
const request = (key = secret, method = 'POST') => new Request('https://example.invalid/parking-push', {
  method, headers: {'x-carcar-worker-secret': key},
});
async function pemFor(algorithm) {
  const pair = await crypto.subtle.generateKey(algorithm, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString('base64')}\n-----END PRIVATE KEY-----`;
}
const ecKey = await pemFor({name: 'ECDSA', namedCurve: 'P-256'});
const rsaKey = await pemFor({name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256'});
const apnsEnv = {APNS_KEY_ID: 'ABCDEFGHIJ', APNS_TEAM_ID: 'KLMNOPQRST', APNS_TOPIC: 'com.kang88.carcar', APNS_PRIVATE_KEY: ecKey};
const fcmEnv = {FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({project_id: 'chagok-test-project', client_email: 'sender@chagok-test-project.iam.gserviceaccount.com', private_key: rsaKey,
  token_uri: 'https://attacker.invalid/do-not-follow'})};

test('worker authentication rejects empty, short and mismatched credentials', async () => {
  assert.equal(await authorized(null, secret), false);
  assert.equal(await authorized('short', 'short'), false);
  assert.equal(await authorized(secret + 'x', secret), false);
  assert.equal(await authorized(secret, secret), true);
});
test('unauthorized and non-POST requests never touch database', async () => {
  const worker = createWorker({secret, rpc: () => {throw new Error('must not call');}, send: () => {throw new Error('must not call');}});
  assert.equal((await worker(request('wrong'))).status, 401);
  assert.equal((await worker(request(secret, 'GET'))).status, 405);
});
test('APNs uses production endpoint, signed auth and generic private payload', async () => {
  let call;
  const sender = createPushSender(apnsEnv, async (url, options) => {call = {url, options}; return new Response(null, {status: 200});}, () => clock);
  assert.equal((await sender(delivery)).result, 'sent');
  assert.equal(call.url, `https://api.push.apple.com/3/device/${delivery.token}`);
  assert.equal(call.options.redirect, 'error');
  assert.equal(call.options.headers['apns-topic'], 'com.kang88.carcar');
  assert.equal(call.options.headers['apns-push-type'], 'alert');
  assert.equal(call.options.headers['apns-collapse-id'], vehicle);
  const jwt = call.options.headers.authorization.slice(7).split('.');
  assert.equal(JSON.parse(Buffer.from(jwt[0], 'base64url')).alg, 'ES256');
  assert.equal(Buffer.from(jwt[2], 'base64url').length, 64);
  const body = JSON.parse(call.options.body);
  assert.equal(body.aps.alert.body, '가족의 주차 위치가 업데이트됐어요.');
  assert.equal(body.aps.category, 'carcar_family');
  assert.equal(body.kind, 'parking_updated');
  assert.deepEqual(Object.keys(body).sort(), ['aps', 'kind', 'vehicle_id']);
});
test('APNs sandbox is explicit and unsupported environment never sends', async () => {
  const urls = [];
  const sender = createPushSender(apnsEnv, async (url) => {urls.push(url); return new Response(null);}, () => clock);
  await sender({...delivery, environment: 'sandbox'});
  assert.match(urls[0], /^https:\/\/api\.sandbox\.push\.apple\.com\//);
  assert.equal((await sender({...delivery, environment: 'other'})).result, 'rejected');
  assert.equal(urls.length, 1);
});
test('FCM uses fixed OAuth endpoint and data-only payload respecting native opt-out', async () => {
  const calls = [];
  const sender = createPushSender(fcmEnv, async (url, options) => {
    calls.push({url, options});
    if (url === 'https://oauth2.googleapis.com/token') return Response.json({access_token: 'synthetic-oauth', expires_in: 3600});
    return Response.json({name: 'projects/test/messages/1'});
  }, () => clock);
  assert.equal((await sender({...delivery, provider: 'fcm', token: 'x'.repeat(80)})).result, 'sent');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://oauth2.googleapis.com/token');
  const assertion = calls[0].options.body.get('assertion').split('.');
  const claims = JSON.parse(Buffer.from(assertion[1], 'base64url'));
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  const body = JSON.parse(calls[1].options.body);
  assert.equal(body.message.notification, undefined);
  assert.equal(body.message.android.notification, undefined);
  assert.equal(body.message.data.kind, 'parking_updated');
  assert.equal(body.message.android.ttl, '3600s');
  assert.equal(calls[1].options.redirect, 'error');
  await sender({...delivery, provider: 'fcm', token: 'x'.repeat(80)});
  assert.equal(calls.length, 3, 'OAuth access token should be reused within expiry');
});
test('FCM unregistered response deletes token, generic INVALID_ARGUMENT does not', () => {
  assert.equal(classifyResponse('fcm', 404, {error: {details: [{'@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED'}]}}), 'invalid_token');
  assert.equal(classifyResponse('fcm', 400, {error: {status: 'INVALID_ARGUMENT'}}), 'rejected');
});
test('provider 429 and 5xx retry; credentials and invalid device distinguishable', () => {
  assert.equal(classifyResponse('apns', 429, {}), 'retry');
  assert.equal(classifyResponse('fcm', 503, {}), 'retry');
  assert.equal(classifyResponse('apns', 403, {}), 'configuration_error');
  assert.equal(classifyResponse('apns', 410, {reason: 'Unregistered'}), 'invalid_token');
  assert.equal(classifyResponse('apns', 400, {reason: 'BadDeviceToken'}), 'invalid_token');
});
test('retry-after seconds/date are honored within 30..3600 second bounds', () => {
  const response = (v) => new Response(null, {headers: {'retry-after': v}});
  assert.equal(retrySeconds(response('120'), clock), 120);
  assert.equal(retrySeconds(response('1'), clock), 30);
  assert.equal(retrySeconds(response('9000'), clock), 3600);
  assert.equal(retrySeconds(response(new Date(clock + 180000).toUTCString()), clock), 180);
  assert.equal(retrySeconds(response('garbage'), clock), 60);
});
test('expired or malformed deliveries do not call provider', async () => {
  let calls = 0;
  const sender = createPushSender(apnsEnv, async () => {calls++;}, () => clock);
  assert.equal((await sender({...delivery, expires_at: 1})).result, 'rejected');
  assert.equal((await sender({...delivery, vehicle_id: '../../secret'})).result, 'rejected');
  assert.equal(calls, 0);
});
test('network error is sanitized and retried without exposing token or key', async () => {
  const sender = createPushSender(apnsEnv, async () => {throw new Error(`secret URL token ${delivery.token}`);}, () => clock);
  const result = await sender(delivery);
  assert.deepEqual(result, {result: 'retry', retrySeconds: 60});
  assert.equal(JSON.stringify(result).includes(delivery.token), false);
});
test('missing provider credentials defer with fixed safe diagnostic', async () => {
  const sender = createPushSender({}, async () => {throw new Error('must not fetch');}, () => clock);
  assert.equal((await sender(delivery)).result, 'configuration_error');
});
test('worker rechecks delivery eligibility before every provider call', async () => {
  const calls = [];
  const worker = createWorker({secret, rpc: async (name) => {
    calls.push(name);
    if (name === 'claim_push_jobs') return [{job_id: jobId, lease_token: lease}];
    if (name === 'prepare_push_delivery') return null;
    throw new Error('must not finish skipped');
  }, send: () => {throw new Error('must not send removed member');}});
  const result = await worker(request());
  assert.equal(result.status, 200);
  assert.equal((await result.json()).skipped, 1);
  assert.deepEqual(calls, ['claim_push_jobs', 'prepare_push_delivery']);
});
test('worker preserves lease identity and acknowledges provider success', async () => {
  let acknowledged;
  const worker = createWorker({secret, rpc: async (name, args) => {
    if (name === 'claim_push_jobs') return [{job_id: jobId, lease_token: lease}];
    if (name === 'prepare_push_delivery') return delivery;
    acknowledged = args; return true;
  }, send: async () => ({result: 'sent', retrySeconds: 60})});
  assert.equal((await (await worker(request())).json()).sent, 1);
  assert.deepEqual(acknowledged, {p_job_id: jobId, p_lease_token: lease, p_result: 'sent', p_retry_seconds: 60});
});
test('provider exception leaves leased job recoverable and does not falsely count sent', async () => {
  const worker = createWorker({secret, rpc: async (name) => name === 'claim_push_jobs'
    ? [{job_id: jobId, lease_token: lease}] : delivery,
  send: async () => {throw new Error('interrupted');}});
  const totals = await (await worker(request())).json();
  assert.equal(totals.sent, 0);
  assert.equal(totals.failed, 1);
  assert.equal(JSON.stringify(totals).includes(delivery.token), false);
});
test('claim failure returns generic 503 without database error disclosure', async () => {
  const worker = createWorker({secret, rpc: async () => {throw new Error('service-key-sensitive');}, send: async () => {}});
  const response = await worker(request());
  assert.equal(response.status, 503);
  assert.equal((await response.text()).includes('service-key-sensitive'), false);
});
