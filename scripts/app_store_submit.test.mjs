import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, stat, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {SUBMISSION_APP as A, SUBMISSION_VERSION as V, SUBMISSION_BUILD as B,
  safeSubmissionUrl, safeSubmissionDiagnostic, privateSubmissionDiagnostic, submitAppStore} from './app_store_submit.mjs';
import {CARCAR_AGE_ATTRIBUTES} from './app_store_distribution.mjs';

const {privateKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const credentials = {APP_STORE_CONNECT_KEY_ID: 'ABCDE12345', APP_STORE_CONNECT_ISSUER_ID: '12345678-1234-1234-1234-123456789abc',
  APP_STORE_CONNECT_API_KEY_P8_BASE64: Buffer.from(privateKey.export({type: 'pkcs8', format: 'pem'})).toString('base64')};
const rel = (type, id) => ({data: {type, id}});
const item = (type, id, attributes = {}, relationships = {}) => ({type, id, attributes, relationships});
function fixture({existing = false, active = false, failSubmit = false} = {}) {
  const calls = [];
  const app = item('apps', A, {bundleId: 'com.kang88.carcar', contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT'});
  const version = item('appStoreVersions', V, {platform: 'IOS', versionString: '1.0', appVersionState: active ? 'WAITING_FOR_REVIEW' : 'PREPARE_FOR_SUBMISSION',
    releaseType: 'AFTER_APPROVAL', copyright: '2026 Owner'}, {app: rel('apps', A)});
  const build = item('builds', B, {version: '13', processingState: 'VALID', expired: false, usesNonExemptEncryption: false});
  const submission = item('reviewSubmissions', 'sub1', {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)});
  const reviewItem = item('reviewSubmissionItems', 'review1', {state: 'READY_FOR_REVIEW'}, {appStoreVersion: rel('appStoreVersions', V)});
  let submissions = existing ? [submission] : [];
  let items = existing ? [reviewItem] : [];
  const data = new Map([
    [`/v1/apps/${A}`, app], [`/v1/appStoreVersions/${V}`, version], [`/v1/appStoreVersions/${V}/build`, build], [`/v1/builds/${B}/app`, app],
    [`/v1/apps/${A}/appInfos`, [item('appInfos', 'info1', {appStoreState: 'PREPARE_FOR_SUBMISSION'}, {primaryCategory: rel('appCategories', 'UTILITIES')})]],
    ['/v1/appInfos/info1/ageRatingDeclaration', item('ageRatingDeclarations', 'age1', {...CARCAR_AGE_ATTRIBUTES})],
    [`/v1/apps/${A}/appPriceSchedule`, item('appPriceSchedules', 'schedule1', {}, {app: rel('apps', A), baseTerritory: rel('territories', 'KOR')})],
    [`/v1/apps/${A}/appPricePoints`, [item('appPricePoints', 'free1', {customerPrice: '0.00'}, {app: rel('apps', A), territory: rel('territories', 'KOR')})]],
    ['/v1/appPriceSchedules/schedule1/manualPrices', [item('appPrices', 'price1', {startDate: null, endDate: null}, {territory: rel('territories', 'KOR'), appPricePoint: rel('appPricePoints', 'free1')})]],
    [`/v1/apps/${A}/appAvailabilityV2`, item('appAvailabilities', 'availability1', {availableInNewTerritories: false})],
    ['/v2/appAvailabilities/availability1/territoryAvailabilities', [item('territoryAvailabilities', 'kor1', {available: true, preOrderEnabled: false}, {territory: rel('territories', 'KOR')})]],
    ['/v1/appInfos/info1/appInfoLocalizations', [item('appInfoLocalizations', 'info-ko', {locale: 'ko', name: '차자리', privacyPolicyUrl: 'https://example.com/privacy'})]],
    [`/v1/appStoreVersions/${V}/appStoreVersionLocalizations`, [item('appStoreVersionLocalizations', 'ko1', {locale: 'ko', description: 'Parking', keywords: 'parking', supportUrl: 'https://example.com/support'})]],
    ['/v1/appStoreVersionLocalizations/ko1/appScreenshotSets', [item('appScreenshotSets', 'phone1', {screenshotDisplayType: 'APP_IPHONE_67'}), item('appScreenshotSets', 'pad1', {screenshotDisplayType: 'APP_IPAD_PRO_3GEN_129'})]],
    ['/v1/appScreenshotSets/phone1/appScreenshots', Array.from({length: 4}, (_, i) => item('appScreenshots', 'phone-' + i, {assetDeliveryState: {state: 'COMPLETE'}}))],
    ['/v1/appScreenshotSets/pad1/appScreenshots', Array.from({length: 4}, (_, i) => item('appScreenshots', 'pad-' + i, {assetDeliveryState: {state: 'COMPLETE'}}))],
    [`/v1/appStoreVersions/${V}/appStoreReviewDetail`, item('appStoreReviewDetails', 'contact1', {
      contactFirstName: 'PRIVATE-FIRST', contactLastName: 'PRIVATE-LAST', contactPhone: '+821012345678', contactEmail: 'private@example.com',
      notes: 'PRIVATE-REVIEW-NOTES', demoAccountRequired: false,
    })],
  ]);
  async function fetchImpl(url, options) {
    assert.equal(url.origin, 'https://api.appstoreconnect.apple.com');
    assert.equal(options.redirect, 'error');
    assert.match(options.headers.Authorization, /^Bearer [\w.-]+$/);
    const path = url.pathname, method = options.method;
    const body = options.body ? JSON.parse(options.body) : undefined;
    calls.push({path, method, body});
    if (method === 'GET') {
      if (path === `/v1/apps/${A}/reviewSubmissions`) return Response.json({data: submissions});
      if (path === '/v1/reviewSubmissions/sub1/items') return Response.json({data: items});
      if (path === '/v1/reviewSubmissions/sub1') return Response.json({data: submission});
      assert.ok(data.has(path), 'Unexpected GET: ' + path);
      return Response.json({data: data.get(path)});
    }
    if (path === '/v1/reviewSubmissions' && method === 'POST') {
      assert.deepEqual(body.data.relationships.app, rel('apps', A));
      assert.equal(submissions.length, 0);
      submissions = [submission];
      return Response.json({data: submission}, {status: 201});
    }
    if (path === '/v1/reviewSubmissionItems' && method === 'POST') {
      assert.deepEqual(body.data.relationships, {reviewSubmission: rel('reviewSubmissions', 'sub1'), appStoreVersion: rel('appStoreVersions', V)});
      items = [reviewItem];
      return Response.json({data: reviewItem}, {status: 201});
    }
    if (path === '/v1/reviewSubmissions/sub1' && method === 'PATCH') {
      assert.deepEqual(body.data.attributes, {submitted: true});
      if (failSubmit) return Response.json({errors: [{code: 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', source: {pointer: '/data/attributes/submitted'},
        detail: 'Privacy data collection not published. private@example.com SECRET_TOKEN https://secret.invalid/token'}]}, {status: 409});
      submission.attributes.state = 'WAITING_FOR_REVIEW';
      version.attributes.appVersionState = 'WAITING_FOR_REVIEW';
      return Response.json({data: submission});
    }
    throw new Error('Unexpected mutation');
  }
  return {fetchImpl, calls, data, app, version, build, submission};
}

test('inspect validates prerequisites but never writes or exposes private contact', async () => {
  const f = fixture();
  const report = await submitAppStore(credentials, f.fetchImpl);
  assert.equal(report.localPrerequisitesReady, true);
  assert.equal(report.submitted, false);
  assert.ok(f.calls.every(call => call.method === 'GET'));
  assert.doesNotMatch(JSON.stringify(report), /PRIVATE|private@example|821012/);
});

test('explicit submit creates only target review and verifies waiting state', async () => {
  const f = fixture();
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
  assert.equal(report.submitted, true);
  assert.equal(report.submissionState, 'WAITING_FOR_REVIEW');
  assert.deepEqual(f.calls.filter(call => call.method !== 'GET').map(call => [call.method, call.path]),
    [['POST', '/v1/reviewSubmissions'], ['POST', '/v1/reviewSubmissionItems'], ['PATCH', '/v1/reviewSubmissions/sub1']]);
  const again = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
  assert.equal(again.submitted, true);
  assert.deepEqual(again.writes, []);
});

test('reuses existing draft and target item, writing only submitted flag', async () => {
  const f = fixture({existing: true});
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
  assert.equal(report.submitted, true);
  assert.equal(report.writes.length, 1);
  assert.equal(report.writes[0].method, 'PATCH');
});

test('existing draft with an unrelated item is not changed or submitted', async () => {
  const f = fixture({existing: true});
  const wrapped = async (url, options) => url.pathname === '/v1/reviewSubmissions/sub1/items'
    ? Response.json({data: [item('reviewSubmissionItems', 'other-item', {}, {appStoreVersion: rel('appStoreVersions', 'other-version')})]})
    : f.fetchImpl(url, options);
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, wrapped);
  assert.equal(report.submitted, false);
  assert.match(report.error.message, /unrelated/);
  assert.ok(f.calls.every(call => call.method === 'GET'));
});

test('ready-for-review app information supports a safe draft retry', async () => {
  const f = fixture({existing: true});
  f.version.attributes.appVersionState = 'READY_FOR_REVIEW';
  f.data.get(`/v1/apps/${A}/appInfos`)[0].attributes.appStoreState = 'READY_FOR_REVIEW';
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
  assert.equal(report.submitted, true);
  assert.equal(report.writes.length, 1);
  assert.equal(report.writes[0].path, '/v1/reviewSubmissions/sub1');
});

test('wrong app, build, release setting, or processing screenshot blocks all writes', async () => {
  for (const change of [f => { f.app.attributes.bundleId = 'other'; }, f => { f.build.id = 'wrong'; },
    f => { f.version.attributes.releaseType = 'MANUAL'; },
    f => { f.data.get('/v1/appScreenshotSets/phone1/appScreenshots')[0].attributes.assetDeliveryState.state = 'UPLOAD_COMPLETE'; }]) {
    const f = fixture(); change(f);
    const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
    assert.equal(report.submitted, false);
    assert.ok(report.blockers.length > 0);
    assert.ok(f.calls.every(call => call.method === 'GET'));
  }
});

test('already waiting version reports submitted without duplicate writes', async () => {
  const f = fixture({active: true});
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
  assert.equal(report.submitted, true);
  assert.ok(f.calls.every(call => call.method === 'GET'));
});

test('paid price, other territory, and automatic future territories prevent final submission', async () => {
  for (const change of [
    f => { f.data.get('/v1/appPriceSchedules/schedule1/manualPrices')[0].relationships.appPricePoint = rel('appPricePoints', 'paid1'); },
    f => { f.data.get('/v2/appAvailabilities/availability1/territoryAvailabilities').push(item('territoryAvailabilities', 'usa1', {available: true}, {territory: rel('territories', 'USA')})); },
    f => { f.data.get(`/v1/apps/${A}/appAvailabilityV2`).attributes.availableInNewTerritories = true; },
  ]) {
    const f = fixture(); change(f);
    const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
    assert.equal(report.submitted, false);
    assert.equal(report.distribution.ready, false);
    assert.ok(f.calls.every(call => call.method === 'GET'));
  }
});

test('Apple privacy rejection keeps safe codes/pointers/category, strips arbitrary text', async () => {
  const f = fixture({failSubmit: true});
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, f.fetchImpl);
  assert.equal(report.submitted, false);
  assert.deepEqual(report.error.categories, ['APP_PRIVACY_REQUIRED']);
  assert.deepEqual(report.error.codes, ['ENTITY_ERROR.ATTRIBUTE.REQUIRED']);
  assert.deepEqual(report.error.pointers, ['/data/attributes/submitted']);
  assert.doesNotMatch(JSON.stringify(report), /private@example|SECRET_TOKEN|secret.invalid|PRIVATE/);
});

test('diagnostic removes malformed codes and private pointer segments', () => {
  const result = safeSubmissionDiagnostic(409, {errors: [{code: 'private@example.com', source: {pointer: '/data/private@example.com'}, detail: 'Copyright missing'}]});
  assert.deepEqual(result.codes, []);
  assert.deepEqual(result.pointers, []);
  assert.deepEqual(result.categories, ['METADATA_REQUIRED']);
});

test('nested associated error maps classify privacy and other missing field rules', () => {
  const document = {errors: [{code: 'STATE_ERROR.ENTITY_STATE_INVALID', title: 'Cannot submit', meta: {
    associatedErrors: {'private@example.com': [{code: 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', title: 'App dataUsage missing',
      source: {pointer: '/data/attributes/privacyPolicyUrl'}, meta: {associatedErrors: {errors: [
        {code: 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', detail: 'contentRightsDeclaration missing'},
        {code: 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', detail: 'ageRating declaration required'},
        {code: 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', detail: 'usesIdfa declaration required'},
      ]}}}]},
  }}]};
  const result = safeSubmissionDiagnostic(409, document);
  assert.deepEqual(result.codes, ['STATE_ERROR.ENTITY_STATE_INVALID', 'ENTITY_ERROR.ATTRIBUTE.REQUIRED']);
  assert.deepEqual(result.pointers, ['/data/attributes/privacyPolicyUrl']);
  for (const category of ['APP_PRIVACY_REQUIRED', 'CONTENT_RIGHTS_REQUIRED', 'AGE_RATING_REQUIRED', 'ADVERTISING_DECLARATION_REQUIRED']) {
    assert.ok(result.categories.includes(category));
  }
  assert.doesNotMatch(JSON.stringify(result), /private@example/);
});

test('private diagnostics redact secrets, JWTs, email, phone, URLs and untrusted map keys', () => {
  const secret = 'short-key-secret';
  const document = {errors: [{code: 'STATE_ERROR.ENTITY_STATE_INVALID', detail:
    `App Privacy missing. ${secret} Bearer abcdefghijk eyJabcdefghij.eyJabcdefghij.abcdefghijk secret=secret-value private@example.com +82 10-1234-5678 https://example.com/token?key=secret`,
  meta: {associatedErrors: {'private@example.com': [{detail: 'Copyright missing', title: 'Nested error'}]}}}]};
  const result = privateSubmissionDiagnostic(409, document, [secret]);
  const output = JSON.stringify(result);
  assert.doesNotMatch(output, /short-key-secret|abcdefghijk|secret-value|private@example|1234-5678|example.com|\?key/);
  assert.match(output, /App Privacy missing/);
  assert.match(output, /Copyright missing/);
  assert.equal(result.errors[0].associatedErrors.length, 1);
});

test('diagnostic traversal and text size are bounded for cyclic and excessive error trees', () => {
  const error = {code: 'STATE_ERROR.ENTITY_STATE_INVALID', detail: 'x'.repeat(100000)};
  error.meta = {associatedErrors: [error, ...Array.from({length: 2000}, () => ({detail: 'Privacy missing '.repeat(1000)}))]};
  const result = privateSubmissionDiagnostic(409, {errors: [error]});
  assert.ok(JSON.stringify(result).length < 60000);
  assert.ok(result.errors[0].associatedErrors.length < 100);
});

test('item rejection preserves redacted private diagnostics with exact method/path and reuses existing draft', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'carcar-submit-diagnostic-'));
  try {
    const f = fixture({existing: true});
    const wrapped = async (url, options) => {
      if (url.pathname === '/v1/reviewSubmissions/sub1/items') return Response.json({data: []});
      if (url.pathname === '/v1/reviewSubmissionItems' && options.method === 'POST') return Response.json({errors: [
        {code: 'STATE_ERROR.ENTITY_STATE_INVALID', title: 'Entity is not ready', meta: {associatedErrors: {version: [
          {code: 'ENTITY_ERROR.ATTRIBUTE.REQUIRED', detail: 'App Privacy is not published. private@example.com +821012345678 https://secret.invalid/token', source: {pointer: '/data/attributes/submitted'}},
        ]}}},
      ]}, {status: 409});
      return f.fetchImpl(url, options);
    };
    const path = join(directory, 'private', 'diagnostic.json');
    const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true', APP_STORE_SUBMISSION_DIAGNOSTIC_PATH: path}, wrapped);
    assert.equal(report.submitted, false);
    assert.equal(report.error.method, 'POST');
    assert.equal(report.error.path, '/v1/reviewSubmissionItems');
    assert.deepEqual(report.error.categories, ['APP_PRIVACY_REQUIRED']);
    assert.equal(f.calls.filter(call => call.method === 'POST' && call.path === '/v1/reviewSubmissions').length, 0);
    const privateText = await readFile(path, 'utf8');
    assert.match(privateText, /App Privacy is not published/);
    assert.doesNotMatch(privateText, /private@example|821012345678|secret.invalid|PRIVATE-REVIEW/);
    assert.doesNotMatch(JSON.stringify(report), /App Privacy is not published/);
    assert.equal((await stat(path)).mode & 0o777, 0o600);
    assert.equal((await stat(dirname(path))).mode & 0o777, 0o700);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('untrusted host and cross-resource pagination do not receive credentials', async () => {
  assert.throws(() => safeSubmissionUrl('https://evil.example/v1/apps/1'), /destination/);
  const f = fixture();
  const wrapped = async (url, options) => url.pathname === `/v1/apps/${A}/appInfos`
    ? Response.json({data: f.data.get(url.pathname), links: {next: 'https://evil.example/v1/apps/1'}})
    : f.fetchImpl(url, options);
  const report = await submitAppStore({...credentials, APP_STORE_SUBMIT: 'true'}, wrapped);
  assert.equal(report.submitted, false);
  assert.match(report.error.message, /destination/);
  assert.ok(f.calls.every(call => call.method === 'GET'));
});

test('opaque resource IDs are supported without URL dot-segment traversal', () => {
  assert.equal(safeSubmissionUrl('/v1/appPriceSchedules/opaque_id==/manualPrices').pathname,
    '/v1/appPriceSchedules/opaque_id==/manualPrices');
  for (const path of ['/v1/apps/../apps/1', '/v1/apps/./1', '/v1/apps/%2e%2e/1', '/v1/apps/.%2e/1']) {
    assert.throws(() => safeSubmissionUrl(path), /dot segment/);
  }
});

test('report artifact is private and contains no contact information', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'carcar-submit-test-'));
  try {
    const path = join(directory, 'evidence', 'summary.json');
    await submitAppStore({...credentials, APP_STORE_SUBMISSION_SUMMARY_PATH: path}, fixture().fetchImpl);
    assert.equal((await stat(path)).mode & 0o777, 0o600);
    assert.equal((await stat(join(directory, 'evidence'))).mode & 0o777, 0o700);
    assert.doesNotMatch(await readFile(path, 'utf8'), /PRIVATE|private@example|821012/);
  } finally { await rm(directory, {recursive: true, force: true}); }
});
