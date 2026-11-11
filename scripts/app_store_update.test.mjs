import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync, createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, readFile, rm, stat, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {UPDATE_APP_ID as A, UpdateError, updateAppStore, updateConfig, loadUpdateDraft, loadUpdateMedia,
  safeUpdateUrl, parseVersion, compareVersions, exitCodeFor, permittedUpdateWrite} from './app_store_update.mjs';

const SCRIPT = fileURLToPath(new URL('./app_store_update.mjs', import.meta.url));
const DRAFT = fileURLToPath(new URL('../docs/app-store/update-1.0.1.json', import.meta.url));
const draftFile = JSON.parse(await readFile(DRAFT, 'utf8'));
const VERSION = draftFile.version;
// The notes name the build under review; fixtures follow whatever the draft says.
const BUILD = /^Build: 1\.0\.1 \((\d+)\)\./m.exec(draftFile.reviewNotes)?.[1];

const {privateKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const P8 = Buffer.from(privateKey.export({type: 'pkcs8', format: 'pem'})).toString('base64');
const base = {APP_STORE_CONNECT_KEY_ID: 'ABCDE12345', APP_STORE_CONNECT_ISSUER_ID: '12345678-1234-1234-1234-123456789abc',
  APP_STORE_CONNECT_API_KEY_P8_BASE64: P8, APP_STORE_UPDATE_VERSION: VERSION, APP_STORE_UPDATE_BUILD: BUILD, APP_STORE_UPDATE_DRAFT_PATH: DRAFT};
const contact = {contactFirstName: 'Reviewfirst', contactLastName: 'Reviewlast', contactPhone: '+82 10 5555 0199', contactEmail: 'review.contact@example.invalid'};
const carried = {contactFirstName: 'PRIVATE-FIRST', contactLastName: 'PRIVATE-LAST', contactPhone: '+82 10 7777 0142', contactEmail: 'private.owner@example.invalid'};
const CONTACT_JSON = JSON.stringify(contact);
const quiet = {sleep: async () => {}};
const secretValues = [...Object.values(contact), ...Object.values(carried), 'OLD-PRIVATE-NOTES', 'DEMO-PASSWORD', P8, base.APP_STORE_CONNECT_ISSUER_ID,
  base.APP_STORE_CONNECT_KEY_ID, '5555 0199', '7777 0142'];
function assertNoSecrets(text, label = 'output') {
  for (const secret of secretValues) assert.ok(!String(text).includes(secret), label + ' must not contain private value ' + secret.slice(0, 6) + '…');
}

const obj = (type, id, attributes = {}, relationships = {}) => ({type, id, attributes, relationships});
const rel = (type, id) => ({data: {type, id}});
const OUT_OF_BOUNDS = /price|availab|territor|appInfo|ageRating|categor|beta|tester|releaseRequest|phasedRelease|customerReview|appStoreVersionSubmission/i;

/** A small in-memory App Store Connect holding the live 1.0 release. */
function world(o = {}) {
  const calls = [], violations = [], uploads = new Map();
  let sequence = 0;
  const next = prefix => prefix + '-' + (++sequence);
  const app = obj('apps', A, {bundleId: o.bundleId ?? 'com.kang88.carcar', name: '차자리 - 가족 주차 기록', primaryLocale: 'ko'});
  const versions = [], locales = [], reviews = [], sets = [], shots = [], items = [];
  const builds = [obj('builds', 'b13', {version: '13', processingState: 'VALID', expired: false, usesNonExemptEncryption: false}),
    obj('builds', 'b-target', {version: BUILD, processingState: o.processingState ?? 'VALID', expired: o.expired ?? false, usesNonExemptEncryption: false})];
  const prerelease = {b13: obj('preReleaseVersions', 'pre-old', {version: '1.0.0', platform: 'IOS'}),
    'b-target': obj('preReleaseVersions', 'pre-new', {version: o.buildTrain ?? '1.0.1', platform: 'IOS'})};
  const submissions = [obj('reviewSubmissions', 'sub-old', {platform: 'IOS', state: 'COMPLETE'}, {app: rel('apps', A)})];
  function addVersion(versionString, state, attributes = {}, {copyFrom, review = true} = {}) {
    const version = obj('appStoreVersions', next('version'), {platform: 'IOS', versionString, appVersionState: state, ...attributes},
      {app: rel('apps', A), build: {data: null}});
    versions.push(version);
    const locale = obj('appStoreVersionLocalizations', next('locale'), {locale: 'ko', description: '설명', whatsNew: null},
      {appStoreVersion: rel('appStoreVersions', version.id)});
    locales.push(locale);
    for (const [display, prefix] of [['APP_IPHONE_67', 'iphone'], ['APP_IPAD_PRO_3GEN_129', 'ipad']]) {
      const set = obj('appScreenshotSets', next('set'), {screenshotDisplayType: display}, {appStoreVersionLocalization: rel('appStoreVersionLocalizations', locale.id)});
      sets.push(set);
      for (let i = 1; i <= 4; i++) shots.push(obj('appScreenshots', next('shot'), {fileName: `0${i}-${prefix}.jpg`, fileSize: 1000 + i,
        sourceFileChecksum: 'old-' + prefix + i, assetDeliveryState: {state: 'COMPLETE'}}, {appScreenshotSet: rel('appScreenshotSets', set.id)}));
    }
    if (review) reviews.push(obj('appStoreReviewDetails', next('review'), copyFrom
      ? structuredClone(reviews.find(r => r.relationships.appStoreVersion.data.id === copyFrom.id).attributes)
      : {...carried, notes: 'OLD-PRIVATE-NOTES', demoAccountRequired: false, demoAccountPassword: 'DEMO-PASSWORD'},
    {appStoreVersion: rel('appStoreVersions', version.id)}));
    return version;
  }
  const live = addVersion('1.0', 'READY_FOR_DISTRIBUTION', {appStoreState: 'READY_FOR_SALE', releaseType: o.liveReleaseType ?? 'AFTER_APPROVAL', copyright: '2026 Owner'});
  live.relationships.build = rel('builds', 'b13');
  const byId = (collection, id) => collection.find(entry => entry.id === id);
  const json = (data, status = 200) => Response.json({data}, {status});
  const missing = () => Response.json({errors: [{code: 'NOT_FOUND', detail: 'missing'}]}, {status: 404});
  const routes = [
    ['GET', /^\/v1\/apps\/([^/]+)$/, m => m[1] === A ? json(app) : missing()],
    ['GET', new RegExp(`^/v1/apps/${A}/appStoreVersions$`), () => json(versions)],
    ['GET', /^\/v1\/builds$/, (m, body, url) => json(builds.filter(b => b.attributes.version === url.searchParams.get('filter[version]')))],
    ['GET', /^\/v1\/builds\/([^/]+)$/, m => json(byId(builds, m[1]))],
    ['GET', /^\/v1\/builds\/([^/]+)\/preReleaseVersion$/, m => json(prerelease[m[1]])],
    ['GET', /^\/v1\/builds\/([^/]+)\/app$/, () => json(o.buildApp ?? app)],
    ['POST', /^\/v1\/appStoreVersions$/, (m, body) => {
      assert.deepEqual(Object.keys(body.data.relationships), ['app']);
      assert.deepEqual(body.data.relationships.app, rel('apps', A));
      assert.ok(!versions.some(v => v.attributes.platform === 'IOS' && v.attributes.versionString === body.data.attributes.versionString), 'duplicate version create');
      return json(addVersion(body.data.attributes.versionString, 'PREPARE_FOR_SUBMISSION',
        {releaseType: body.data.attributes.releaseType, copyright: body.data.attributes.copyright ?? null}, {copyFrom: live, review: o.carryReview !== false}), 201);
    }],
    ['GET', /^\/v1\/appStoreVersions\/([^/]+)$/, m => json(byId(versions, m[1]))],
    ['PATCH', /^\/v1\/appStoreVersions\/([^/]+)$/, (m, body) => { Object.assign(byId(versions, m[1]).attributes, body.data.attributes); return json(byId(versions, m[1])); }],
    ['GET', /^\/v1\/appStoreVersions\/([^/]+)\/build$/, m => {
      const id = byId(versions, m[1]).relationships.build.data?.id;
      return id ? json(byId(builds, id)) : missing();
    }],
    ['PATCH', /^\/v1\/appStoreVersions\/([^/]+)\/relationships\/build$/, (m, body) => {
      assert.ok(body.data && byId(builds, body.data.id), 'build link must name a known build');
      byId(versions, m[1]).relationships.build = body;
      return new Response(null, {status: 204});
    }],
    ['GET', /^\/v1\/appStoreVersions\/([^/]+)\/appStoreVersionLocalizations$/, m => json(locales.filter(l => l.relationships.appStoreVersion.data.id === m[1]))],
    ['GET', /^\/v1\/appStoreVersions\/([^/]+)\/appStoreReviewDetail$/, m => {
      const detail = reviews.find(r => r.relationships.appStoreVersion.data.id === m[1]);
      return detail ? json(detail) : missing();
    }],
    ['GET', /^\/v1\/appStoreVersionLocalizations\/([^/]+)$/, m => json(byId(locales, m[1]))],
    ['PATCH', /^\/v1\/appStoreVersionLocalizations\/([^/]+)$/, (m, body) => { Object.assign(byId(locales, m[1]).attributes, body.data.attributes); return json(byId(locales, m[1])); }],
    ['GET', /^\/v1\/appStoreReviewDetails\/([^/]+)$/, m => json(byId(reviews, m[1]))],
    ['PATCH', /^\/v1\/appStoreReviewDetails\/([^/]+)$/, (m, body) => { Object.assign(byId(reviews, m[1]).attributes, body.data.attributes); return json(byId(reviews, m[1])); }],
    ['POST', /^\/v1\/appStoreReviewDetails$/, (m, body) => {
      const versionId = body.data.relationships.appStoreVersion.data.id;
      assert.ok(!reviews.some(r => r.relationships.appStoreVersion.data.id === versionId), 'duplicate review detail create');
      const detail = obj('appStoreReviewDetails', next('review'), {...body.data.attributes}, body.data.relationships);
      reviews.push(detail);
      return json(detail, 201);
    }],
    ['GET', /^\/v1\/appStoreVersionLocalizations\/([^/]+)\/appScreenshotSets$/, m => json(sets.filter(s => s.relationships.appStoreVersionLocalization.data.id === m[1]))],
    ['GET', /^\/v1\/appScreenshotSets\/([^/]+)$/, m => json(byId(sets, m[1]))],
    ['GET', /^\/v1\/appScreenshotSets\/([^/]+)\/appScreenshots$/, m => json(shots.filter(s => s.relationships.appScreenshotSet.data.id === m[1]))],
    ['POST', /^\/v1\/appScreenshotSets$/, (m, body) => { const set = obj('appScreenshotSets', next('set'), body.data.attributes, body.data.relationships); sets.push(set); return json(set, 201); }],
    ['POST', /^\/v1\/appScreenshots$/, (m, body) => {
      const id = next('shot'), setId = body.data.relationships.appScreenshotSet.data.id;
      // Apple holds at most ten images in a set, reservations included.
      if (shots.filter(s => s.relationships.appScreenshotSet.data.id === setId).length >= 10) violations.push('more than 10 screenshots in ' + setId);
      const shot = obj('appScreenshots', id, {...body.data.attributes, sourceFileChecksum: null, assetDeliveryState: {state: 'AWAITING_UPLOAD'},
        uploadOperations: [{method: 'PUT', url: 'https://' + (o.uploadHost ?? 'store-030.blobstore.apple.com') + '/' + id + '?signature=SIGNED-PRIVATE', offset: 0, length: body.data.attributes.fileSize}]},
      body.data.relationships);
      shots.push(shot);
      return json(shot, 201);
    }],
    ['GET', /^\/v1\/appScreenshots\/([^/]+)$/, m => json(byId(shots, m[1]))],
    ['PATCH', /^\/v1\/appScreenshots\/([^/]+)$/, (m, body) => {
      const shot = byId(shots, m[1]);
      assert.equal(createHash('md5').update(uploads.get(shot.id)).digest('hex'), body.data.attributes.sourceFileChecksum);
      Object.assign(shot.attributes, {sourceFileChecksum: body.data.attributes.sourceFileChecksum, assetDeliveryState: {state: o.deliveryState ?? 'COMPLETE'}});
      return json(shot);
    }],
    ['DELETE', /^\/v1\/appScreenshots\/([^/]+)$/, m => { shots.splice(shots.indexOf(byId(shots, m[1])), 1); return new Response(null, {status: 204}); }],
    ['GET', new RegExp(`^/v1/apps/${A}/reviewSubmissions$`), () => json(submissions)],
    ['GET', /^\/v1\/reviewSubmissions\/([^/]+)$/, m => json(byId(submissions, m[1]))],
    ['GET', /^\/v1\/reviewSubmissions\/([^/]+)\/items$/, m => json(items.filter(i => i.submission === m[1]).map(i => i.resource))],
    ['POST', /^\/v1\/reviewSubmissions$/, (m, body) => {
      assert.deepEqual(body.data, {type: 'reviewSubmissions', attributes: {platform: 'IOS'}, relationships: {app: rel('apps', A)}});
      const submission = obj('reviewSubmissions', next('submission'), {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)});
      submissions.push(submission);
      return json(submission, 201);
    }],
    ['POST', /^\/v1\/reviewSubmissionItems$/, (m, body) => {
      const versionId = body.data.relationships.appStoreVersion.data.id, submissionId = body.data.relationships.reviewSubmission.data.id;
      assert.equal(byId(submissions, submissionId).attributes.state, 'READY_FOR_REVIEW');
      const resource = obj('reviewSubmissionItems', next('item'), {state: 'READY_FOR_REVIEW'}, {appStoreVersion: rel('appStoreVersions', versionId)});
      items.push({submission: submissionId, resource});
      byId(versions, versionId).attributes.appVersionState = 'READY_FOR_REVIEW';
      return json(resource, 201);
    }],
    ['PATCH', /^\/v1\/reviewSubmissions\/([^/]+)$/, (m, body) => {
      assert.deepEqual(body.data.attributes, {submitted: true});
      const submission = byId(submissions, m[1]);
      submission.attributes.state = 'WAITING_FOR_REVIEW';
      for (const entry of items.filter(i => i.submission === submission.id)) byId(versions, entry.resource.relationships.appStoreVersion.data.id).attributes.appVersionState = 'WAITING_FOR_REVIEW';
      return json(submission);
    }],
  ];
  async function fetchImpl(input, options) {
    const url = new URL(input), method = options.method, path = url.pathname;
    if (url.hostname !== 'api.appstoreconnect.apple.com') {
      assert.equal(url.hostname, 'store-030.blobstore.apple.com');
      assert.equal(method, 'PUT');
      assert.ok(!Object.keys(options.headers).some(name => /authorization|cookie/i.test(name)), 'no API credentials on uploads');
      uploads.set(path.slice(1), Buffer.from(options.body));
      calls.push({method, path: 'upload:' + path});
      return new Response('', {status: 200});
    }
    const body = options.body ? JSON.parse(options.body) : undefined;
    calls.push({method, path, body, search: url.search});
    assert.equal(options.redirect, 'error');
    assert.match(options.headers.Authorization, /^Bearer [\w.-]+$/);
    if (OUT_OF_BOUNDS.test(path) || (method === 'DELETE' && !/^\/v1\/appScreenshots\/[^/]+$/.test(path))
      || body?.data?.attributes?.canceled !== undefined || (path.startsWith('/v1/apps/') && !path.startsWith('/v1/apps/' + A))) violations.push(method + ' ' + path);
    const intercepted = await o.intercept?.({method, path, body, url});
    if (intercepted) return intercepted;
    for (const [routeMethod, pattern, handler] of routes) {
      const match = routeMethod === method && pattern.exec(path);
      if (match) return handler(match, body, url);
    }
    violations.push('unrouted ' + method + ' ' + path);
    return missing();
  }
  const written = (from = 0) => calls.slice(from).filter(call => call.method !== 'GET').map(call => call.method + ' ' + call.path);
  // File names of the target version's Korean set for one display type, in store order.
  const targetShots = display => {
    const locale = locales.find(l => l.relationships.appStoreVersion.data.id === versions.find(v => v.attributes.versionString === VERSION)?.id);
    const set = sets.find(s => s.relationships.appStoreVersionLocalization.data.id === locale?.id && s.attributes.screenshotDisplayType === display);
    return shots.filter(s => s.relationships.appScreenshotSet.data.id === set?.id);
  };
  return {fetchImpl, calls, violations, written, app, versions, builds, prerelease, locales, reviews, sets, shots, submissions, items, addVersion, live, targetShots,
    target: () => versions.find(v => v.attributes.versionString === VERSION),
    targetLocale: () => locales.find(l => l.relationships.appStoreVersion.data.id === versions.find(v => v.attributes.versionString === VERSION)?.id),
    targetReview: () => reviews.find(r => r.relationships.appStoreVersion.data.id === versions.find(v => v.attributes.versionString === VERSION)?.id)};
}
// Every run, passing or refused, must stay inside the permitted endpoints.
async function run(w, env = {}, options = quiet) {
  try { return await updateAppStore({...base, ...env}, w.fetchImpl, options); }
  finally { assert.deepEqual(w.violations, [], 'out-of-bounds request'); }
}
const prepareEnv = {APP_STORE_UPDATE_MODE: 'prepare'};
const submitEnv = {APP_STORE_UPDATE_MODE: 'submit', APP_STORE_SUBMIT: 'true'};
async function preparedWorld(o) {
  const w = world(o);
  const summary = await run(w, prepareEnv);
  assert.equal(summary.prepared, true, 'fixture should prepare cleanly: ' + summary.blockers.join(','));
  return w;
}

async function mediaFixture(root, count = 2, changedFrom = Infinity) {
  const tag = 'new';
  const manifest = {devices: []};
  for (const [family, width, height] of [['iphone', 1320, 2868], ['ipad', 2064, 2752]]) {
    await mkdir(join(root, family), {recursive: true});
    const screenshots = [];
    for (let i = 1; i <= count; i++) {
      const file = `0${i}-${tag}.jpg`;
      const bytes = Buffer.concat([Buffer.from([255, 216, 255, 192, 0, 11, 8, height >> 8, height & 255, width >> 8, width & 255, 1, 1, 17, 0, 255, 217]), Buffer.from(family + file + (i >= changedFrom ? 'changed' : ''))]);
      await writeFile(join(root, family, file), bytes);
      screenshots.push({file, width, height, hasAlpha: false, sha256: createHash('sha256').update(bytes).digest('hex')});
    }
    manifest.devices.push({deviceFamily: family, screenshots});
  }
  await writeFile(join(root, 'manifest.json'), JSON.stringify(manifest));
}
async function temp(prefix, body) {
  const directory = await mkdtemp(join(tmpdir(), prefix));
  try { return await body(directory); } finally { await rm(directory, {recursive: true, force: true}); }
}

test('update draft carries the approved release text and current review notes within Apple limits', async () => {
  assert.equal(draftFile.version, '1.0.1');
  assert.ok(BUILD, 'review notes must contain the line "Build: 1.0.1 (<number>)."');
  assert.equal(draftFile.whatsNew.ko, '더 쉽고 가볍게 다듬었어요.\n• 새 자리 핀 아이콘과 블루 톤으로 바뀌었어요.\n• 차량 등록이 간단해졌어요.\n• 초대받은 가족은 버튼 한 번으로 참여해요.\n• 기록 시각을 ‘오늘 16:41’처럼 보여 줘요.\n• 신호가 약한 곳에서도 멈추지 않도록 안정성을 높였어요.\n• iPhone 층수 아이콘은 설정에서 켤 수 있어요.');
  assert.ok(draftFile.reviewNotes.length > 0 && draftFile.reviewNotes.length <= 4000, 'review notes are ' + draftFile.reviewNotes.length + ' characters');
  assert.ok(draftFile.whatsNew.ko.length <= 4000);
  assert.ok(draftFile.reviewNotes.indexOf('[한국어]') > 0 && draftFile.reviewNotes.indexOf('[English]') > draftFile.reviewNotes.indexOf('[한국어]'));
  for (const label of ['Apple로 계속하기', 'Google로 계속하기', '새 차량 등록', '차량 번호', '차량 별명', '내 이름', '차량 등록하기', '주차 기록하기',
    '주차 기록 저장', '가족 초대하기', '초대 링크 공유', '코드 복사', '참여하기', '받은 초대로 참여', '가족 차량에 참여하기', '주차 층수 앱 아이콘',
    '개인정보와 계정', '계정 삭제', '가입 없이 먼저 둘러보기']) assert.ok(draftFile.reviewNotes.includes('‘' + label + '’'), 'notes should quote ' + label);
  for (const retired of ['차량 번호 중복 확인', '가족 초대 코드 만들기', '기존 차량 참여', '아파트 이름', '1.0.0 (13)']) assert.ok(!draftFile.reviewNotes.includes(retired), 'notes still mention ' + retired);
  assert.equal(typeof draftFile.screenshots, 'string');
  const loaded = await loadUpdateDraft(DRAFT, VERSION, BUILD);
  assert.equal(loaded.reviewNotes, draftFile.reviewNotes);
  await assert.rejects(loadUpdateDraft(DRAFT, VERSION, String(Number(BUILD) + 1)), /do not name the target build/);
  await assert.rejects(loadUpdateDraft(DRAFT, '1.0.2', BUILD), /different version/);
});

test('configuration is validated before any network call', async () => {
  const offline = () => assert.fail('network called');
  for (const [env, pattern] of [
    [{APP_STORE_UPDATE_VERSION: undefined}, /VERSION is required/], [{APP_STORE_UPDATE_VERSION: '1.0.1-beta'}, /look like/],
    [{APP_STORE_UPDATE_VERSION: '1'}, /look like/], [{APP_STORE_UPDATE_BUILD: undefined}, /positive integer/],
    [{APP_STORE_UPDATE_BUILD: '0'}, /positive integer/], [{APP_STORE_UPDATE_BUILD: '15a'}, /positive integer/],
    [{APP_STORE_UPDATE_MODE: 'release'}, /Mode must/], [{APP_STORE_RELEASE_TYPE: 'SCHEDULED'}, /Release type/],
    [{CARCAR_APP_ID: '1234567890'}, /restricted to carcar/], [{APP_STORE_REVIEW_CONTACT_JSON: '{bad'}, /contact/],
    [{APP_STORE_CONNECT_KEY_ID: 'short'}, /identifiers/],
  ]) await assert.rejects(updateAppStore({...base, ...env}, offline), pattern);
  assert.equal(updateConfig(base).mode, 'inspect');
  assert.equal(updateConfig(base).release, 'KEEP');
  assert.equal(updateConfig({...base, APP_STORE_UPDATE_MEDIA_ROOT: ''}).mediaRoot, null);
  assert.deepEqual(parseVersion('1.0'), [1, 0, 0]);
  assert.equal(compareVersions('1.0.1', '1.0'), 1);
  assert.equal(compareVersions('1.0', '1.0.0'), 0);
  assert.equal(compareVersions('1.9', '1.10'), -1);
});

test('inspect with only the live 1.0 release reads without writing and lists what is missing', async () => {
  await temp('asc-update-inspect-', async directory => {
    const w = world(), path = join(directory, 'evidence', 'summary.json');
    const summary = await run(w, {APP_STORE_UPDATE_SUMMARY_PATH: path, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON});
    assert.equal(summary.mode, 'inspect');
    assert.ok(w.calls.length > 5 && w.calls.every(call => call.method === 'GET'));
    assert.deepEqual(w.violations, []);
    assert.deepEqual(summary.writes, []);
    assert.deepEqual(summary.liveVersion, {id: w.live.id, versionString: '1.0', state: 'READY_FOR_DISTRIBUTION', releaseType: 'AFTER_APPROVAL', createdDate: null});
    assert.equal(summary.targetVersion.exists, false);
    assert.equal(summary.targetBuild.found, true);
    assert.equal(summary.targetBuild.processingState, 'VALID');
    assert.equal(summary.targetBuild.preReleaseVersion, '1.0.1');
    assert.equal(summary.screenshots.of, 'live');
    assert.deepEqual(summary.screenshots.sets.map(s => [s.display, s.count, s.complete]), [['APP_IPHONE_67', 4, 4], ['APP_IPAD_PRO_3GEN_129', 4, 4]]);
    assert.deepEqual(summary.reviewSubmissions, {open: [], completed: 1});
    assert.deepEqual(summary.blockers, ['TARGET_VERSION_NOT_CREATED']);
    assert.equal(summary.submitted, false);
    assert.equal(exitCodeFor(summary), 0, 'a successful read exits 0 even with blockers');
    assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), summary);
    assert.equal((await stat(path)).mode & 0o777, 0o600);
    assertNoSecrets(JSON.stringify(summary));
    // A missing draft is reported by inspect, and stops prepare before any request.
    const missingDraft = join(directory, 'absent.json');
    const report = await run(world(), {APP_STORE_UPDATE_DRAFT_PATH: missingDraft});
    assert.deepEqual(report.draft, {ok: false});
    assert.ok(report.blockers.includes('UPDATE_DRAFT_INVALID'));
    const offline = world();
    await assert.rejects(run(offline, {...prepareEnv, APP_STORE_UPDATE_DRAFT_PATH: missingDraft}), /draft file is missing/);
    assert.equal(offline.calls.length, 0);
  });
});

test('inspect of an already created target version reports state, build, text and review detail as facts only', async () => {
  const w = await preparedWorld();
  const count = w.calls.length;
  const summary = await run(w);
  assert.ok(w.calls.slice(count).every(call => call.method === 'GET'));
  assert.equal(summary.targetVersion.exists, true);
  assert.equal(summary.targetVersion.state, 'PREPARE_FOR_SUBMISSION');
  assert.equal(summary.targetVersion.releaseType, 'AFTER_APPROVAL');
  assert.equal(summary.targetVersion.attachedBuild.id, 'b-target');
  assert.equal(summary.targetVersion.attachedBuild.buildNumber, BUILD);
  assert.deepEqual(summary.localizations.map(l => [l.locale, l.whatsNewPresent, l.whatsNewMatchesDraft]), [['ko', true, true]]);
  assert.deepEqual(summary.reviewDetail, {present: true, contactComplete: true, notesPresent: true, notesMatchDraft: true, demoAccountRequired: false});
  assert.equal(summary.screenshots.of, 'target');
  assert.deepEqual(summary.blockers, []);
  assertNoSecrets(JSON.stringify(summary));
  // A version created by hand, with nothing filled in yet, is described the same way.
  const bare = world();
  bare.addVersion(VERSION, 'PREPARE_FOR_SUBMISSION', {releaseType: 'MANUAL', copyright: '2026 Owner'}, {review: false});
  const report = await run(bare);
  assert.equal(report.targetVersion.releaseType, 'MANUAL');
  assert.equal(report.targetVersion.attachedBuild, null);
  assert.equal(report.reviewDetail.present, false);
  assert.deepEqual(report.blockers, ['BUILD_NOT_ATTACHED', 'WHATS_NEW_MISSING:ko', 'REVIEW_DETAIL_MISSING']);
});

test('inspect while the build is still processing succeeds and names the blocker', async () => {
  const w = world({processingState: 'PROCESSING'});
  const summary = await run(w);
  assert.equal(summary.targetBuild.processingState, 'PROCESSING');
  assert.ok(summary.blockers.includes('TARGET_BUILD_PROCESSING'));
  assert.ok(w.calls.every(call => call.method === 'GET'));
  const absent = world();
  absent.builds.pop();
  const report = await run(absent);
  assert.equal(report.targetBuild.found, false);
  assert.ok(report.blockers.includes('TARGET_BUILD_NOT_FOUND'));
  // Processing builds must be asked for explicitly or Apple may omit them.
  assert.match(w.calls.find(call => call.path === '/v1/builds').search, /processingState/);
});

test('prepare creates the version, sets text and notes, attaches the build, and a second run writes nothing', async () => {
  const w = world();
  const summary = await run(w, {...prepareEnv, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON});
  const target = w.target(), review = w.targetReview();
  assert.deepEqual(w.written(), ['POST /v1/appStoreVersions', 'PATCH /v1/appStoreVersionLocalizations/' + w.targetLocale().id,
    'PATCH /v1/appStoreReviewDetails/' + review.id, 'PATCH /v1/appStoreVersions/' + target.id + '/relationships/build']);
  assert.deepEqual(summary.writes.map(write => write.method + ' ' + write.path), w.written());
  assert.deepEqual(w.violations, []);
  const create = w.calls.find(call => call.method === 'POST').body.data;
  assert.deepEqual(create.attributes, {platform: 'IOS', versionString: VERSION, releaseType: 'AFTER_APPROVAL', copyright: '2026 Owner'});
  assert.equal(target.attributes.appVersionState, 'PREPARE_FOR_SUBMISSION');
  assert.equal(w.targetLocale().attributes.whatsNew, draftFile.whatsNew.ko);
  assert.equal(w.targetLocale().attributes.description, '설명');
  assert.equal(review.attributes.notes, draftFile.reviewNotes);
  // Existing contact fields and demo settings are never sent or changed.
  assert.deepEqual(w.calls.find(call => call.method === 'PATCH' && call.path.startsWith('/v1/appStoreReviewDetails/')).body.data.attributes, {notes: draftFile.reviewNotes});
  for (const [key, value] of Object.entries(carried)) assert.equal(review.attributes[key], value);
  assert.equal(review.attributes.demoAccountPassword, 'DEMO-PASSWORD');
  assert.deepEqual(target.relationships.build, rel('builds', 'b-target'));
  assert.equal(summary.prepared, true);
  assert.equal(exitCodeFor(summary), 0);
  assert.equal(summary.createdVersion, true);
  assert.deepEqual(summary.blockers, []);
  assert.equal(summary.submitted, false);
  assert.equal(summary.appliedReleaseType, 'AFTER_APPROVAL');
  assert.equal(summary.screenshots.expected, 'live');
  assert.deepEqual(summary.screenshots.sets.map(s => s.matchesExpected), [true, true]);
  assert.equal(w.shots.length, 16, 'inherited screenshots are left alone');
  assert.equal(w.live.attributes.appVersionState, 'READY_FOR_DISTRIBUTION');
  assertNoSecrets(JSON.stringify(summary));
  const count = w.calls.length;
  const again = await run(w, {...prepareEnv, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON});
  assert.deepEqual(w.written(count), []);
  assert.deepEqual(again.writes, []);
  assert.equal(again.prepared, true);
  assert.equal(w.versions.length, 2);
});

test('prepare resumes after a partial failure without creating anything twice', async () => {
  let fail = true;
  const w = world({intercept: ({method, path}) => fail && method === 'PATCH' && path.startsWith('/v1/appStoreVersionLocalizations/')
    ? Response.json({errors: [{code: 'UNEXPECTED_ERROR', detail: 'temporary'}]}, {status: 500}) : null});
  await assert.rejects(run(w, prepareEnv), /Apple API HTTP 500 for PATCH \/v1\/appStoreVersionLocalizations\//);
  assert.equal(w.versions.length, 2);
  assert.equal(w.targetLocale().attributes.whatsNew, null);
  fail = false;
  const summary = await run(w, prepareEnv);
  assert.equal(summary.prepared, true);
  assert.equal(summary.createdVersion, undefined);
  assert.equal(w.calls.filter(call => call.method === 'POST' && call.path === '/v1/appStoreVersions').length, 1);
  assert.equal(w.versions.length, 2);
  assert.deepEqual(w.violations, []);
});

test('a new version without review detail gets one from the contact secret, and only then', async () => {
  const w = world({carryReview: false});
  const without = await run(w, prepareEnv);
  assert.equal(without.prepared, false);
  assert.ok(without.blockers.includes('REVIEW_DETAIL_MISSING_AND_NO_CONTACT_SECRET') && without.blockers.includes('REVIEW_DETAIL_MISSING'));
  assert.equal(w.targetReview(), undefined);
  const count = w.calls.length;
  const summary = await run(w, {...prepareEnv, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON});
  assert.deepEqual(w.written(count), ['POST /v1/appStoreReviewDetails']);
  const payload = w.calls.slice(count).find(call => call.method === 'POST').body.data;
  assert.deepEqual(payload.attributes, {...contact, notes: draftFile.reviewNotes, demoAccountRequired: false});
  assert.deepEqual(payload.relationships, {appStoreVersion: rel('appStoreVersions', w.target().id)});
  assert.equal(summary.prepared, true);
  assert.equal(summary.createdReviewDetail, true);
  assert.deepEqual(summary.reviewDetail, {present: true, contactComplete: true, notesPresent: true, notesMatchDraft: true, demoAccountRequired: false});
  assertNoSecrets(JSON.stringify(summary));
});

test('release setting follows KEEP, an explicit choice, or stops when the live setting cannot be kept', async () => {
  const manual = world();
  await run(manual, {...prepareEnv, APP_STORE_RELEASE_TYPE: 'MANUAL'});
  assert.equal(manual.target().attributes.releaseType, 'MANUAL');
  // KEEP leaves an existing version alone; an explicit choice changes exactly that attribute.
  const count = manual.calls.length;
  await run(manual, {...prepareEnv, APP_STORE_RELEASE_TYPE: 'KEEP'});
  assert.deepEqual(manual.written(count), []);
  await run(manual, {...prepareEnv, APP_STORE_RELEASE_TYPE: 'AFTER_APPROVAL'});
  assert.deepEqual(manual.written(count), ['PATCH /v1/appStoreVersions/' + manual.target().id]);
  assert.deepEqual(manual.calls.findLast(call => call.method === 'PATCH').body.data.attributes, {releaseType: 'AFTER_APPROVAL'});
  assert.equal(manual.target().attributes.releaseType, 'AFTER_APPROVAL');
  const scheduled = world({liveReleaseType: 'SCHEDULED'});
  await assert.rejects(run(scheduled, prepareEnv), /cannot be kept/);
  assert.deepEqual(scheduled.written(), []);
});

test('a processing build is not attached; the rest is prepared and a later run attaches only the build', async () => {
  const w = world({processingState: 'PROCESSING'});
  const summary = await run(w, prepareEnv);
  assert.equal(summary.prepared, false);
  assert.equal(exitCodeFor(summary), 2, 'an unfinished preparation must not look green');
  assert.equal(exitCodeFor({mode: 'prepare', blockers: []}), 2, 'only a confirmed preparation exits 0');
  assert.ok(summary.blockers.includes('TARGET_BUILD_PROCESSING') && summary.blockers.includes('BUILD_NOT_ATTACHED'));
  assert.ok(!w.written().some(write => write.includes('/relationships/build')));
  assert.equal(w.targetLocale().attributes.whatsNew, draftFile.whatsNew.ko);
  w.builds.at(-1).attributes.processingState = 'VALID';
  const count = w.calls.length;
  const later = await run(w, prepareEnv);
  assert.deepEqual(w.written(count), ['PATCH /v1/appStoreVersions/' + w.target().id + '/relationships/build']);
  assert.equal(later.prepared, true);
  assert.equal(exitCodeFor(later), 0);
});

test('wrong app or bundle is refused on the first response', async () => {
  for (const mode of ['inspect', 'prepare', 'submit']) {
    const w = world({bundleId: 'com.example.other'});
    await assert.rejects(run(w, {APP_STORE_UPDATE_MODE: mode, APP_STORE_SUBMIT: 'true'}), /Unexpected app identity/);
    assert.equal(w.calls.length, 1);
    assert.equal(w.calls[0].method, 'GET');
  }
  const foreignBuild = world({buildApp: obj('apps', '1111111111', {bundleId: 'com.kang88.carcar'})});
  await assert.rejects(run(foreignBuild, prepareEnv), /another app/);
  assert.deepEqual(foreignBuild.written(), []);
});

test('a version that is not higher than the live one is refused without writes', async () => {
  for (const version of ['1.0', '1.0.0', '0.9.9']) {
    const w = world({buildTrain: version});
    const draft = join(tmpdir(), 'unused');
    await assert.rejects(run(w, {...prepareEnv, APP_STORE_UPDATE_VERSION: version, APP_STORE_UPDATE_DRAFT_PATH: draft}), /draft/);
    assert.equal(w.calls.length, 0);
  }
  await temp('asc-update-lower-', async directory => {
    for (const version of ['1.0', '1.0.0', '0.9.9']) {
      const path = join(directory, version + '.json');
      await writeFile(path, JSON.stringify({version, whatsNew: {ko: '수정'}, reviewNotes: `Build: ${version} (${BUILD}). notes`}));
      for (const env of [prepareEnv, submitEnv]) {
        const w = world({buildTrain: version});
        const outcome = run(w, {...env, APP_STORE_UPDATE_VERSION: version, APP_STORE_UPDATE_DRAFT_PATH: path});
        if (env === prepareEnv) await assert.rejects(outcome, /TARGET_VERSION_NOT_HIGHER_THAN_LIVE:1\.0/);
        else assert.ok((await outcome).blockers.some(b => b.startsWith('TARGET_VERSION_NOT_HIGHER_THAN_LIVE')));
        assert.deepEqual(w.written(), []);
        assert.equal(w.versions.length, 1);
      }
      const inspected = await run(world({buildTrain: version}), {APP_STORE_UPDATE_VERSION: version, APP_STORE_UPDATE_DRAFT_PATH: path});
      assert.ok(inspected.blockers.some(b => b.startsWith('TARGET_VERSION_NOT_HIGHER_THAN_LIVE')));
    }
  });
});

test('expired, failed, or wrong-train builds are refused without writes', async () => {
  for (const [options, pattern] of [[{expired: true}, /TARGET_BUILD_EXPIRED/], [{processingState: 'INVALID'}, /TARGET_BUILD_NOT_USABLE:INVALID/],
    [{processingState: 'FAILED'}, /TARGET_BUILD_NOT_USABLE:FAILED/], [{buildTrain: '1.0.0'}, /TARGET_BUILD_VERSION_MISMATCH/]]) {
    const w = world(options);
    await assert.rejects(run(w, prepareEnv), pattern);
    assert.deepEqual(w.written(), []);
    assert.equal(w.versions.length, 1);
    const inspected = await run(world(options));
    assert.ok(inspected.blockers.some(b => pattern.test(b)));
  }
  // Only an explicit "not expired" counts; a build without the flag is refused too.
  for (const value of [undefined, null, 'false']) {
    const unknown = world();
    unknown.builds.at(-1).attributes.expired = value;
    await assert.rejects(run(unknown, prepareEnv), /TARGET_BUILD_EXPIRED/);
    assert.deepEqual(unknown.written(), []);
  }
  // A build of the right number and version on another platform is not the target.
  const otherPlatform = world();
  otherPlatform.prerelease['b-target'].attributes.platform = 'MAC_OS';
  await assert.rejects(run(otherPlatform, prepareEnv), /TARGET_BUILD_VERSION_MISMATCH/);
  assert.deepEqual(otherPlatform.written(), []);
  // A build that expires after preparation blocks the submission as well.
  const w = await preparedWorld();
  w.builds.at(-1).attributes.expired = true;
  const count = w.calls.length;
  const summary = await run(w, submitEnv);
  assert.equal(summary.submitted, false);
  assert.ok(summary.blockers.includes('TARGET_BUILD_EXPIRED'));
  assert.deepEqual(w.written(count), []);
});

test('unexpected version states stop preparation instead of guessing', async () => {
  for (const state of ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED', 'PENDING_DEVELOPER_RELEASE', 'READY_FOR_REVIEW']) {
    const w = world();
    w.addVersion(VERSION, state, {releaseType: 'AFTER_APPROVAL', copyright: '2026 Owner'});
    await assert.rejects(run(w, prepareEnv), new RegExp('TARGET_VERSION_STATE_NOT_EDITABLE:' + state));
    assert.deepEqual(w.written(), []);
  }
  const other = world();
  other.addVersion('1.0.2', 'PREPARE_FOR_SUBMISSION', {releaseType: 'AFTER_APPROVAL'});
  await assert.rejects(run(other, prepareEnv), /OTHER_VERSION_IN_PROGRESS:1\.0\.2:PREPARE_FOR_SUBMISSION/);
  assert.deepEqual(other.written(), []);
  const noLive = world();
  noLive.live.attributes.appVersionState = 'PENDING_DEVELOPER_RELEASE';
  await assert.rejects(run(noLive, prepareEnv), /LIVE_VERSION_NOT_FOUND/);
  assert.deepEqual(noLive.written(), []);
  // Retired versions and other platforms do not get in the way.
  const history = world();
  history.addVersion('0.9', 'REPLACED_WITH_NEW_VERSION', {releaseType: 'MANUAL'});
  history.addVersion('1.0.1', 'PREPARE_FOR_SUBMISSION', {platform: 'MAC_OS'});
  assert.equal((await run(history, prepareEnv)).prepared, true);
});

test('screenshots are replaced only when a media folder is given, and exactly to its manifest', async () => {
  await temp('asc-update-media-', async root => {
    await mediaFixture(root);
    assert.equal((await loadUpdateMedia(root)).length, 4);
    const w = world();
    const summary = await run(w, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: root});
    assert.equal(summary.prepared, true);
    assert.deepEqual(summary.screenshotReplacement, [
      {family: 'iphone', display: 'APP_IPHONE_67', kept: 0, removed: 4, uploaded: 2, verified: true},
      {family: 'ipad', display: 'APP_IPAD_PRO_3GEN_129', kept: 0, removed: 4, uploaded: 2, verified: true}]);
    const locale = w.targetLocale();
    const targetSets = w.sets.filter(s => s.relationships.appStoreVersionLocalization.data.id === locale.id);
    for (const set of targetSets) {
      const images = w.shots.filter(s => s.relationships.appScreenshotSet.data.id === set.id);
      assert.deepEqual(images.map(i => [i.attributes.fileName, i.attributes.assetDeliveryState.state]), [['01-new.jpg', 'COMPLETE'], ['02-new.jpg', 'COMPLETE']]);
    }
    // The live version keeps all eight of its screenshots.
    assert.equal(w.shots.length, 8 + 4);
    assert.deepEqual(summary.screenshots.sets.map(s => [s.count, s.complete]), [[2, 2], [2, 2]]);
    assert.deepEqual(w.violations, []);
    assert.ok(!JSON.stringify(summary).includes('SIGNED-PRIVATE'));
    const count = w.calls.length;
    const again = await run(w, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: root});
    assert.deepEqual(w.written(count), []);
    assert.equal(again.screenshotReplacement.every(r => r.kept === 2 && r.removed === 0 && r.uploaded === 0 && r.verified), true);
    // One more image is appended; a changed second image keeps the first and replaces what follows it.
    await temp('asc-update-media-b-', async other => {
      await mediaFixture(other, 3);
      const start = w.calls.length;
      const grown = await run(w, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: other});
      assert.equal(grown.screenshotReplacement.every(r => r.kept === 2 && r.removed === 0 && r.uploaded === 1 && r.verified), true);
      assert.equal(w.written(start).filter(write => write.startsWith('DELETE')).length, 0);
      await mediaFixture(other, 3, 2);
      const changed = await run(w, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: other});
      assert.equal(changed.screenshotReplacement.every(r => r.kept === 1 && r.removed === 2 && r.uploaded === 2 && r.verified), true);
      assert.equal(changed.prepared, true);
      assert.equal(w.shots.length, 8 + 6);
    });
    // A tampered file is rejected before any request is made.
    await writeFile(join(root, 'iphone', '01-new.jpg'), Buffer.from('tampered'));
    const untouched = world();
    await assert.rejects(run(untouched, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: root}), /integrity/);
    assert.deepEqual(untouched.written(), []);
    assert.equal(untouched.versions.length, 1);
  });
});

test('submit is refused without the explicit flag, before any request', async () => {
  for (const value of [undefined, '', 'false', 'TRUE', 'yes', '1', ' true']) {
    const w = await preparedWorld();
    const count = w.calls.length;
    await assert.rejects(run(w, {APP_STORE_UPDATE_MODE: 'submit', APP_STORE_SUBMIT: value}), /APP_STORE_SUBMIT to be exactly true/);
    assert.equal(w.calls.length, count);
    assert.equal(w.target().attributes.appVersionState, 'PREPARE_FOR_SUBMISSION');
  }
  // The flag alone never submits from another mode.
  const w = await preparedWorld();
  const count = w.calls.length;
  for (const mode of ['inspect', 'prepare']) await run(w, {APP_STORE_UPDATE_MODE: mode, APP_STORE_SUBMIT: 'true'});
  assert.deepEqual(w.written(count), []);
  assert.equal(w.submissions.length, 1);
});

test('submit creates one submission with the version as its only item and confirms the waiting state', async () => {
  const w = await preparedWorld();
  const count = w.calls.length;
  const summary = await run(w, submitEnv);
  const submission = w.submissions.at(-1), target = w.target();
  assert.deepEqual(w.written(count), ['POST /v1/reviewSubmissions', 'POST /v1/reviewSubmissionItems', 'PATCH /v1/reviewSubmissions/' + submission.id]);
  assert.deepEqual(w.calls.slice(count).find(call => call.path === '/v1/reviewSubmissionItems').body.data,
    {type: 'reviewSubmissionItems', relationships: {reviewSubmission: rel('reviewSubmissions', submission.id), appStoreVersion: rel('appStoreVersions', target.id)}});
  assert.equal(summary.submitted, true);
  assert.equal(summary.submissionId, submission.id);
  assert.equal(summary.submissionState, 'WAITING_FOR_REVIEW');
  assert.equal(summary.versionState, 'WAITING_FOR_REVIEW');
  assert.equal(summary.createdSubmission, true);
  assert.deepEqual(summary.blockers, []);
  assert.deepEqual(w.violations, []);
  assert.equal(w.items.filter(i => i.submission === submission.id).length, 1);
  assert.equal(w.live.attributes.appVersionState, 'READY_FOR_DISTRIBUTION');
  assertNoSecrets(JSON.stringify(summary));
  assert.equal(exitCodeFor(summary), 0);
  // Running again reports the same submission and writes nothing.
  const after = w.calls.length;
  const again = await run(w, submitEnv);
  assert.deepEqual(w.written(after), []);
  assert.equal(again.submitted, true);
  assert.equal(again.alreadySubmitted, true);
  assert.equal(again.submissionId, submission.id);
  assert.equal(w.submissions.length, 2);
});

test('submit reuses an open unsubmitted submission and resumes after a failed final step', async () => {
  const w = await preparedWorld();
  w.submissions.push(obj('reviewSubmissions', 'sub-open', {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)}));
  const count = w.calls.length;
  const summary = await run(w, submitEnv);
  assert.deepEqual(w.written(count), ['POST /v1/reviewSubmissionItems', 'PATCH /v1/reviewSubmissions/sub-open']);
  assert.equal(summary.submitted, true);
  assert.equal(summary.reusedSubmission, true);
  assert.equal(summary.submissionId, 'sub-open');
  let fail = true;
  const retry = await preparedWorld({intercept: ({method, path}) => fail && method === 'PATCH' && path.startsWith('/v1/reviewSubmissions/')
    ? Response.json({errors: [{code: 'STATE_ERROR.ENTITY_STATE_INVALID', detail: 'App Privacy data collection is not published.'}]}, {status: 409}) : null});
  await assert.rejects(run(retry, submitEnv), /Apple API HTTP 409 for PATCH \/v1\/reviewSubmissions\//);
  assert.equal(retry.target().attributes.appVersionState, 'READY_FOR_REVIEW');
  fail = false;
  const start = retry.calls.length;
  const resumed = await run(retry, submitEnv);
  assert.deepEqual(retry.written(start), ['PATCH /v1/reviewSubmissions/' + retry.submissions.at(-1).id]);
  assert.equal(resumed.submitted, true);
  assert.equal(retry.submissions.length, 2);
});

test('an accepted request that Apple has not yet moved to review is reported as unconfirmed, not as submitted', async () => {
  let polls = 0;
  const w = await preparedWorld({intercept: ({method, path}) => method === 'PATCH' && path.startsWith('/v1/reviewSubmissions/')
    ? Response.json({data: obj('reviewSubmissions', path.split('/').at(-1), {platform: 'IOS', state: 'READY_FOR_REVIEW'})}) : null});
  const summary = await run(w, submitEnv, {sleep: async () => { polls++; }});
  assert.equal(summary.submitted, false);
  assert.equal(summary.submitRequestAccepted, true);
  assert.equal(summary.submissionState, 'READY_FOR_REVIEW');
  assert.deepEqual(summary.blockers, ['SUBMISSION_ACCEPTANCE_NOT_YET_CONFIRMED']);
  assert.equal(polls, 4);
  assert.equal(exitCodeFor(summary), 2);
});

test('submit is refused while another submission is in flight, and never touches it', async () => {
  const cases = [
    w => { const other = w.addVersion('1.0.2', 'WAITING_FOR_REVIEW', {releaseType: 'MANUAL'});
      w.submissions.push(obj('reviewSubmissions', 'sub-other', {platform: 'IOS', state: 'WAITING_FOR_REVIEW'}, {app: rel('apps', A)}));
      w.items.push({submission: 'sub-other', resource: obj('reviewSubmissionItems', 'item-other', {}, {appStoreVersion: rel('appStoreVersions', other.id)})}); },
    w => { w.submissions.push(obj('reviewSubmissions', 'sub-other', {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)}));
      w.items.push({submission: 'sub-other', resource: obj('reviewSubmissionItems', 'item-other', {}, {appStoreVersion: {data: null}, appEvent: rel('appEvents', 'event-1')})}); },
    w => { w.submissions.push(obj('reviewSubmissions', 'sub-other', {platform: 'IOS', state: 'UNRESOLVED_ISSUES'}, {app: rel('apps', A)}));
      w.items.push({submission: 'sub-other', resource: obj('reviewSubmissionItems', 'item-other', {}, {appStoreVersion: rel('appStoreVersions', w.target().id)})}); },
    w => { w.submissions.push(obj('reviewSubmissions', 'sub-other', {platform: 'IOS', state: 'CANCELING'}, {app: rel('apps', A)})); },
    w => { for (const id of ['sub-other', 'sub-third']) w.submissions.push(obj('reviewSubmissions', id, {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)})); },
  ];
  for (const arrange of cases) {
    const w = await preparedWorld();
    arrange(w);
    const count = w.calls.length, before = JSON.stringify([w.submissions, w.items]);
    const summary = await run(w, submitEnv);
    assert.equal(summary.submitted, false);
    assert.equal(summary.submissionId, null);
    assert.ok(summary.blockers.some(b => /^(OTHER_SUBMISSION_IN_FLIGHT:sub-other|MULTIPLE_OPEN_SUBMISSIONS)/.test(b)), summary.blockers.join(','));
    assert.deepEqual(w.written(count), []);
    assert.equal(JSON.stringify([w.submissions, w.items]), before);
    assert.equal(exitCodeFor(summary), 2);
    assert.equal(w.target().attributes.appVersionState, 'PREPARE_FOR_SUBMISSION');
  }
});

test('submit re-verifies build, text, review detail and screenshots, and stops on any gap', async () => {
  const gaps = [
    [w => { w.target().relationships.build = {data: null}; }, 'BUILD_NOT_ATTACHED'],
    [w => { w.target().relationships.build = rel('builds', 'b13'); }, 'ATTACHED_BUILD_IS_NOT_TARGET'],
    [w => { w.builds.at(-1).attributes.processingState = 'INVALID'; }, 'TARGET_BUILD_NOT_USABLE:INVALID'],
    [w => { w.builds.at(-1).attributes.usesNonExemptEncryption = null; }, 'BUILD_ENCRYPTION_DECLARATION_NOT_CONFIRMED'],
    [w => { w.targetLocale().attributes.whatsNew = ' '; }, 'WHATS_NEW_MISSING:ko'],
    [w => { w.targetLocale().attributes.whatsNew = '다른 문구'; }, 'WHATS_NEW_DIFFERS_FROM_DRAFT'],
    [w => { w.reviews.splice(w.reviews.indexOf(w.targetReview()), 1); }, 'REVIEW_DETAIL_MISSING'],
    [w => { w.targetReview().attributes.contactPhone = ''; }, 'REVIEW_CONTACT_INCOMPLETE'],
    [w => { w.targetReview().attributes.notes = 'OLD-PRIVATE-NOTES'; }, 'REVIEW_NOTES_DIFFER_FROM_DRAFT'],
    [w => { const set = w.sets.find(s => s.relationships.appStoreVersionLocalization.data.id === w.targetLocale().id);
      for (const shot of w.shots.filter(s => s.relationships.appScreenshotSet.data.id === set.id)) w.shots.splice(w.shots.indexOf(shot), 1); }, 'SCREENSHOTS_NOT_READY:APP_IPHONE_67'],
    [w => { const set = w.sets.filter(s => s.relationships.appStoreVersionLocalization.data.id === w.targetLocale().id)[1];
      w.shots.find(s => s.relationships.appScreenshotSet.data.id === set.id).attributes.assetDeliveryState.state = 'UPLOAD_COMPLETE'; }, 'SCREENSHOTS_NOT_READY:APP_IPAD_PRO_3GEN_129'],
    [w => { w.target().attributes.releaseType = 'SCHEDULED'; }, 'RELEASE_TYPE_NOT_SET'],
    [w => { w.target().attributes.appVersionState = 'REJECTED'; }, 'TARGET_VERSION_STATE_UNEXPECTED:REJECTED'],
    [w => { w.target().attributes.copyright = ' '; }, 'COPYRIGHT_MISSING'],
    [w => { w.targetLocale().attributes.locale = 'en-US'; }, 'KOREAN_LOCALIZATION_MISSING'],
    [w => { w.targetReview().attributes.notes = ' '; }, 'REVIEW_NOTES_MISSING'],
    [w => { w.targetReview().attributes.demoAccountRequired = true; }, 'REVIEW_DEMO_ACCOUNT_INCOMPLETE'],
    [w => { delete w.targetReview().attributes.demoAccountRequired; }, 'REVIEW_DEMO_ACCOUNT_INCOMPLETE'],
    // Complete images that are not the live version's files in the live order: one missing, reordered, or changed.
    [w => { w.shots.splice(w.shots.indexOf(w.targetShots('APP_IPHONE_67')[0]), 1); }, 'SCREENSHOTS_DIFFER_FROM_EXPECTED:APP_IPHONE_67'],
    [w => { const [first, second] = w.targetShots('APP_IPAD_PRO_3GEN_129');
      [first.attributes, second.attributes] = [second.attributes, first.attributes]; }, 'SCREENSHOTS_DIFFER_FROM_EXPECTED:APP_IPAD_PRO_3GEN_129'],
    [w => { w.targetShots('APP_IPHONE_67')[3].attributes.sourceFileChecksum = 'someone-elses-file'; }, 'SCREENSHOTS_DIFFER_FROM_EXPECTED:APP_IPHONE_67'],
    [w => { for (const shot of w.shots) shot.attributes.sourceFileChecksum = null; }, 'SCREENSHOTS_DIFFER_FROM_EXPECTED:APP_IPHONE_67'],
  ];
  for (const [damage, blocker] of gaps) {
    const w = await preparedWorld();
    damage(w);
    const count = w.calls.length;
    const summary = await run(w, submitEnv);
    assert.equal(summary.submitted, false, blocker);
    assert.ok(summary.blockers.includes(blocker), blocker + ' expected in ' + summary.blockers.join(','));
    assert.deepEqual(w.written(count), [], blocker);
    assertNoSecrets(JSON.stringify(summary), blocker);
  }
  // Nothing prepared at all: no version is created by submit.
  const empty = world();
  const summary = await run(empty, submitEnv);
  assert.ok(summary.blockers.includes('TARGET_VERSION_NOT_CREATED'));
  assert.deepEqual(empty.written(), []);
});

test('no contact value, credential or provider text reaches the summary, the diagnostics or the error', async () => {
  await temp('asc-update-secret-', async directory => {
    const summaryPath = join(directory, 'summary.json'), diagnosticPath = join(directory, 'private', 'diagnostics.json');
    const echo = `Rejected for ${contact.contactFirstName} ${contact.contactEmail} ${contact.contactPhone} ${carried.contactEmail} Bearer abc.def.ghi ${P8} https://secret.invalid/path?token=1`;
    const paths = {APP_STORE_UPDATE_SUMMARY_PATH: summaryPath, APP_STORE_UPDATE_DIAGNOSTIC_PATH: diagnosticPath, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON};
    for (const failing of ['/v1/appStoreReviewDetails', '/v1/appStoreVersionLocalizations/']) {
      const w = world({carryReview: false, intercept: ({method, path}) => method !== 'GET' && path.startsWith(failing)
        ? Response.json({errors: [{code: 'ENTITY_ERROR.ATTRIBUTE.INVALID', title: echo, detail: echo, source: {pointer: '/data/attributes/contactEmail'}}]}, {status: 409}) : null});
      let message = '';
      await assert.rejects(run(w, {...prepareEnv, ...paths}), error => { message = error.message; return error instanceof UpdateError; });
      const summaryText = await readFile(summaryPath, 'utf8'), diagnosticText = await readFile(diagnosticPath, 'utf8');
      for (const [label, text] of [['error', message], ['summary', summaryText], ['diagnostics', diagnosticText]]) {
        assertNoSecrets(text, label);
        assert.ok(!/secret\.invalid|abc\.def\.ghi|Bearer (?!\[REDACTED\])/.test(text), label);
      }
      const saved = JSON.parse(summaryText);
      assert.match(saved.error, /^Apple API HTTP 409 for (POST|PATCH) \/v1\//);
      assert.deepEqual(saved.diagnostic.codes, ['ENTITY_ERROR.ATTRIBUTE.INVALID']);
      // Provider text about review details is dropped entirely; other endpoints keep a redacted copy.
      const diagnostics = JSON.parse(diagnosticText).diagnostics;
      assert.equal(diagnostics.length, failing === '/v1/appStoreReviewDetails' ? 0 : 1);
      assert.equal((await stat(diagnosticPath)).mode & 0o777, 0o600);
    }
    // A successful run with every private input present stays clean as well.
    const w = world({carryReview: false});
    const summary = await run(w, {...prepareEnv, ...paths});
    assert.equal(summary.prepared, true);
    assertNoSecrets(JSON.stringify(summary));
    assertNoSecrets(await readFile(summaryPath, 'utf8'));
    assert.ok(!JSON.stringify(summary).includes(draftFile.reviewNotes.slice(0, 40)), 'notes text is not copied into the summary');
  });
});

test('command line prints only the bounded error and exits non-zero when Apple refuses', async () => {
  const preload = 'data:text/javascript,' + encodeURIComponent(
    'globalThis.fetch = async () => new Response(JSON.stringify({errors: [{code: "FORBIDDEN_ERROR", detail: "Bearer leaked " + process.env.APP_STORE_REVIEW_CONTACT_JSON}]}), {status: 403});');
  const outcome = await new Promise(done => execFile(process.execPath, ['--import', preload, SCRIPT],
    {env: {...base, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON, PATH: process.env.PATH}}, (error, stdout, stderr) => done({code: error?.code ?? 0, stdout, stderr})));
  assert.equal(outcome.code, 1);
  assert.equal(outcome.stdout, '');
  assert.equal(outcome.stderr.trim(), 'Apple API HTTP 403 for GET /v1/apps/' + A + '; codes=FORBIDDEN_ERROR.');
  assertNoSecrets(outcome.stderr);
  const invalid = await new Promise(done => execFile(process.execPath, ['--import', preload, SCRIPT],
    {env: {...base, APP_STORE_UPDATE_BUILD: 'fifteen', PATH: process.env.PATH}}, (error, stdout, stderr) => done({code: error?.code ?? 0, stdout, stderr})));
  assert.equal(invalid.code, 1);
  assert.equal(invalid.stderr.trim(), 'APP_STORE_UPDATE_BUILD must be a positive integer.');
});

test('requests stay on the Apple API host and never follow foreign pagination', async () => {
  for (const url of ['https://evil.invalid/v1/apps/x', 'https://api.appstoreconnect.apple.com.evil.invalid/v1/apps/x',
    'https://user@api.appstoreconnect.apple.com/v1/apps/x', '/v1/apps/../apps/1', '/v1/apps/%2e%2e/1', '/v3/apps/1']) assert.throws(() => safeUpdateUrl(url), UpdateError);
  assert.equal(safeUpdateUrl('/v1/appScreenshotSets/opaque_id==/appScreenshots?limit=200').pathname, '/v1/appScreenshotSets/opaque_id==/appScreenshots');
  const w = world({intercept: ({path}) => path === `/v1/apps/${A}/appStoreVersions`
    ? Response.json({data: [], links: {next: 'https://evil.invalid/v1/apps/1'}}) : null});
  await assert.rejects(run(w, prepareEnv), /destination/);
  assert.ok(w.calls.every(call => call.method === 'GET'));
});

test('the write gate permits only the listed update operations on IDs read through the target app', () => {
  const bound = () => ({version: 'v1', build: 'b1', localization: 'l1', review: 'r1', submission: 's1', sets: new Set(['set1']), shots: new Set(['shot1']), deletable: new Set(['shot2'])});
  const gate = (mode, method, path, body) => permittedUpdateWrite({mode, target: '1.0.1', bound: bound()}, method, path, body);
  const version = {data: {type: 'appStoreVersions', attributes: {platform: 'IOS', versionString: '1.0.1', releaseType: 'MANUAL'}, relationships: {app: rel('apps', A)}}};
  const item = {data: {type: 'reviewSubmissionItems', relationships: {reviewSubmission: rel('reviewSubmissions', 's1'), appStoreVersion: rel('appStoreVersions', 'v1')}}};
  const allowed = [
    ['prepare', 'POST', '/v1/appStoreVersions', version],
    ['prepare', 'PATCH', '/v1/appStoreVersions/v1', {data: {attributes: {releaseType: 'MANUAL'}}}],
    ['prepare', 'PATCH', '/v1/appStoreVersions/v1/relationships/build', rel('builds', 'b1')],
    ['prepare', 'PATCH', '/v1/appStoreVersionLocalizations/l1', {data: {attributes: {whatsNew: 'x'}}}],
    ['prepare', 'PATCH', '/v1/appStoreReviewDetails/r1', {data: {attributes: {notes: 'x'}}}],
    ['prepare', 'POST', '/v1/appStoreReviewDetails', {data: {attributes: {notes: 'x'}, relationships: {appStoreVersion: rel('appStoreVersions', 'v1')}}}],
    ['prepare', 'POST', '/v1/appScreenshotSets', {data: {relationships: {appStoreVersionLocalization: rel('appStoreVersionLocalizations', 'l1')}}}],
    ['prepare', 'POST', '/v1/appScreenshots', {data: {relationships: {appScreenshotSet: rel('appScreenshotSets', 'set1')}}}],
    ['prepare', 'PATCH', '/v1/appScreenshots/shot1', {data: {attributes: {uploaded: true, sourceFileChecksum: 'x'}}}],
    ['prepare', 'DELETE', '/v1/appScreenshots/shot2', undefined],
    ['submit', 'POST', '/v1/reviewSubmissions', {data: {attributes: {platform: 'IOS'}, relationships: {app: rel('apps', A)}}}],
    ['submit', 'POST', '/v1/reviewSubmissionItems', item],
    ['submit', 'PATCH', '/v1/reviewSubmissions/s1', {data: {attributes: {submitted: true}}}],
  ];
  for (const [mode, method, path, body] of allowed) {
    assert.equal(gate(mode, method, path, body), true, mode + ' ' + method + ' ' + path);
    // Nothing is writable in inspect, and each mode keeps to its own list.
    assert.equal(gate('inspect', method, path, body), false);
    assert.equal(gate(mode === 'prepare' ? 'submit' : 'prepare', method, path, body), false);
  }
  const refused = [
    ['prepare', 'POST', '/v1/appStoreVersions', {data: {...version.data, attributes: {...version.data.attributes, versionString: '2.0'}}}],
    ['prepare', 'POST', '/v1/appStoreVersions', {data: {...version.data, attributes: {...version.data.attributes, platform: 'MAC_OS'}}}],
    ['prepare', 'POST', '/v1/appStoreVersions', {data: {...version.data, relationships: {app: rel('apps', '1111111111')}}}],
    ['prepare', 'PATCH', '/v1/appStoreVersions/other', {data: {attributes: {releaseType: 'MANUAL'}}}],
    ['prepare', 'PATCH', '/v1/appStoreVersions/v1', {data: {attributes: {copyright: 'x'}}}],
    ['prepare', 'PATCH', '/v1/appStoreVersions/v1', {data: {attributes: {releaseType: 'MANUAL', earliestReleaseDate: 'x'}}}],
    ['prepare', 'DELETE', '/v1/appStoreVersions/v1', undefined],
    ['prepare', 'PATCH', '/v1/appStoreVersions/v1/relationships/build', {data: null}],
    ['prepare', 'PATCH', '/v1/appStoreVersions/v1/relationships/build', rel('builds', 'other')],
    ['prepare', 'PATCH', '/v1/appStoreVersionLocalizations/l1', {data: {attributes: {description: 'x'}}}],
    ['prepare', 'PATCH', '/v1/appStoreVersionLocalizations/other', {data: {attributes: {whatsNew: 'x'}}}],
    ['prepare', 'PATCH', '/v1/appStoreReviewDetails/r1', {data: {attributes: {notes: 'x', contactEmail: 'x'}}}],
    ['prepare', 'POST', '/v1/appStoreReviewDetails', {data: {relationships: {appStoreVersion: rel('appStoreVersions', 'other')}}}],
    ['prepare', 'POST', '/v1/appScreenshots', {data: {relationships: {appScreenshotSet: rel('appScreenshotSets', 'other')}}}],
    ['prepare', 'DELETE', '/v1/appScreenshots/shot1', undefined],
    ['prepare', 'DELETE', '/v1/appScreenshotSets/set1', undefined],
    ['prepare', 'POST', '/v1/appStoreVersionReleaseRequests', {data: {relationships: {appStoreVersion: rel('appStoreVersions', 'v1')}}}],
    ['prepare', 'POST', '/v1/appPriceSchedules', {data: {}}], ['prepare', 'POST', '/v2/appAvailabilities', {data: {}}],
    ['prepare', 'PATCH', '/v1/territoryAvailabilities/kor', {data: {attributes: {available: false}}}],
    ['prepare', 'PATCH', '/v1/apps/' + A, {data: {attributes: {contentRightsDeclaration: 'x'}}}],
    ['prepare', 'PATCH', '/v1/appInfos/info', {data: {}}], ['prepare', 'PATCH', '/v1/ageRatingDeclarations/age', {data: {}}],
    ['prepare', 'POST', '/v1/betaTesters', {data: {}}], ['prepare', 'POST', '/v1/betaGroups/g/relationships/builds', {data: []}],
    ['submit', 'PATCH', '/v1/reviewSubmissions/s1', {data: {attributes: {canceled: true}}}],
    ['submit', 'PATCH', '/v1/reviewSubmissions/s1', {data: {attributes: {submitted: true, canceled: true}}}],
    ['submit', 'PATCH', '/v1/reviewSubmissions/other', {data: {attributes: {submitted: true}}}],
    ['submit', 'DELETE', '/v1/reviewSubmissionItems/i1', undefined],
    ['submit', 'POST', '/v1/reviewSubmissionItems', {data: {relationships: {...item.data.relationships, appStoreVersion: rel('appStoreVersions', 'other')}}}],
    ['submit', 'POST', '/v1/reviewSubmissionItems', {data: {relationships: {...item.data.relationships, appEvent: rel('appEvents', 'e1')}}}],
    ['submit', 'POST', '/v1/reviewSubmissions', {data: {attributes: {platform: 'IOS'}, relationships: {app: rel('apps', '1111111111')}}}],
    ['submit', 'POST', '/v1/appStoreVersionReleaseRequests', {data: {}}],
  ];
  for (const [mode, method, path, body] of refused) assert.equal(gate(mode, method, path, body), false, mode + ' ' + method + ' ' + path);
  // Nothing is bound before the target has been read; a deletion permit is single-use.
  const empty = {version: null, build: null, localization: null, review: null, submission: null, sets: new Set(), shots: new Set(), deletable: new Set()};
  for (const [mode, method, path, body] of allowed.filter(entry => !['/v1/appStoreVersions', '/v1/reviewSubmissions'].includes(entry[2]))) {
    assert.equal(permittedUpdateWrite({mode, target: '1.0.1', bound: empty}, method, path.replace(/v1$|l1$|r1$|s1$/, 'null'), body), false, 'unbound ' + path);
  }
  const once = bound();
  assert.equal(permittedUpdateWrite({mode: 'prepare', target: '1.0.1', bound: once}, 'DELETE', '/v1/appScreenshots/shot2'), true);
  assert.equal(permittedUpdateWrite({mode: 'prepare', target: '1.0.1', bound: once}, 'DELETE', '/v1/appScreenshots/shot2'), false);
});

const targetNames = (w, display) => w.targetShots(display).map(shot => shot.attributes.fileName);
const DIFFER = ['SCREENSHOTS_DIFFER_FROM_EXPECTED:APP_IPHONE_67', 'SCREENSHOTS_DIFFER_FROM_EXPECTED:APP_IPAD_PRO_3GEN_129'];

test('screenshot replacement uploads and confirms the new files before it removes any old one', async () => {
  await temp('asc-update-media-order-', async root => {
    await mediaFixture(root);
    const media = {APP_STORE_UPDATE_MEDIA_ROOT: root};
    let deletes = 0, failing = true;
    const w = world({intercept: ({method}) => failing && method === 'DELETE' && ++deletes === 3
      ? Response.json({errors: [{code: 'UNEXPECTED_ERROR', detail: 'temporary'}]}, {status: 500}) : null});
    await assert.rejects(run(w, {...prepareEnv, ...media}), /Apple API HTTP 500 for DELETE \/v1\/appScreenshots\//);
    // Every new file of both sets was committed before the first removal.
    const order = w.written().filter(write => /appScreenshots|upload:/.test(write));
    assert.equal(order.findLastIndex(write => !write.startsWith('DELETE')), order.findIndex(write => write.startsWith('DELETE')) - 1);
    assert.equal(order.filter(write => write === 'POST /v1/appScreenshots').length, 4);
    // The stop left more images than before, never fewer, and all of them usable.
    assert.deepEqual(targetNames(w, 'APP_IPHONE_67'), ['03-iphone.jpg', '04-iphone.jpg', '01-new.jpg', '02-new.jpg']);
    assert.deepEqual(targetNames(w, 'APP_IPAD_PRO_3GEN_129'), ['01-ipad.jpg', '02-ipad.jpg', '03-ipad.jpg', '04-ipad.jpg', '01-new.jpg', '02-new.jpg']);
    assert.ok([...w.targetShots('APP_IPHONE_67'), ...w.targetShots('APP_IPAD_PRO_3GEN_129')].every(shot => shot.attributes.assetDeliveryState.state === 'COMPLETE'));
    failing = false;
    // That mixed state is neither the live set nor a manifest: it is never "prepared" and never submitted.
    const count = w.calls.length;
    const plain = await run(w, prepareEnv);
    assert.equal(plain.prepared, false);
    assert.equal(exitCodeFor(plain), 2);
    assert.deepEqual(plain.blockers, DIFFER);
    assert.deepEqual(plain.screenshots.sets.map(s => s.matchesExpected), [false, false]);
    const refused = await run(w, submitEnv);
    assert.equal(refused.submitted, false);
    assert.deepEqual(refused.blockers, DIFFER);
    assert.deepEqual((await run(w)).blockers, DIFFER);
    assert.deepEqual(w.written(count), []);
    assert.equal(w.target().attributes.appVersionState, 'PREPARE_FOR_SUBMISSION');
    // Running the replacement again finishes it without uploading anything twice.
    const resumed = await run(w, {...prepareEnv, ...media});
    assert.deepEqual(resumed.screenshotReplacement.map(r => [r.kept, r.removed, r.uploaded, r.verified]), [[2, 2, 0, true], [2, 4, 0, true]]);
    assert.deepEqual(w.written(count).map(write => write.split(' ')[0]), Array(6).fill('DELETE'));
    assert.equal(resumed.prepared, true);
    assert.equal(resumed.screenshots.expected, 'manifest');
    assert.deepEqual(targetNames(w, 'APP_IPHONE_67'), ['01-new.jpg', '02-new.jpg']);
    assert.equal(w.shots.length, 8 + 4, 'the live version keeps its eight images');
    // An extra image after the manifest's files is a difference too.
    const extra = structuredClone(w.targetShots('APP_IPHONE_67')[0]);
    extra.id = 'shot-extra';
    w.shots.push(extra);
    assert.deepEqual((await run(w, media)).blockers, [DIFFER[0]]);
    w.shots.pop();
    // Replaced screenshots pass only against the same manifest; without it they differ from the live set.
    const before = w.calls.length;
    assert.deepEqual((await run(w, submitEnv)).blockers, DIFFER);
    assert.deepEqual((await run(w, media)).blockers, []);
    assert.deepEqual(w.written(before), []);
    const sent = await run(w, {...submitEnv, ...media});
    assert.equal(sent.submitted, true);
    assert.ok(w.written(before).every(write => /reviewSubmission/.test(write)));
  });
});

test('a failed or unfinished upload removes nothing, blocks the submission, and is cleaned up by the next run', async () => {
  await temp('asc-update-media-host-', async root => {
    await mediaFixture(root);
    const media = {APP_STORE_UPDATE_MEDIA_ROOT: root};
    // Apple names an upload host that is not on the allow-list: no bytes are sent, no image is removed.
    const options = {uploadHost: 'uploads.evil.invalid'};
    const w = world(options);
    await assert.rejects(run(w, {...prepareEnv, ...media}), /Unverified Apple upload host/);
    assert.ok(!w.written().some(write => write.startsWith('DELETE') || write.includes('upload:')));
    assert.deepEqual(targetNames(w, 'APP_IPHONE_67'), ['01-iphone.jpg', '02-iphone.jpg', '03-iphone.jpg', '04-iphone.jpg', '01-new.jpg']);
    assert.equal(w.targetShots('APP_IPHONE_67').at(-1).attributes.assetDeliveryState.state, 'AWAITING_UPLOAD');
    assert.equal(w.targetShots('APP_IPAD_PRO_3GEN_129').length, 4);
    const stuck = await run(w, prepareEnv);
    assert.equal(stuck.prepared, false);
    assert.deepEqual(stuck.blockers, ['SCREENSHOTS_NOT_READY:APP_IPHONE_67']);
    assert.deepEqual((await run(w, submitEnv)).blockers, ['SCREENSHOTS_NOT_READY:APP_IPHONE_67']);
    delete options.uploadHost;
    const fixed = await run(w, {...prepareEnv, ...media});
    assert.deepEqual(fixed.screenshotReplacement.map(r => [r.kept, r.removed, r.uploaded, r.verified]), [[0, 5, 2, true], [0, 4, 2, true]]);
    assert.equal(fixed.prepared, true);
    // Apple never finishes processing the new images: the old ones stay, and the run is not "prepared".
    for (const deliveryState of ['FAILED', 'UPLOAD_COMPLETE']) {
      const slow = world({deliveryState});
      const summary = await run(slow, {...prepareEnv, ...media});
      assert.equal(summary.prepared, false);
      assert.equal(exitCodeFor(summary), 2);
      assert.equal(summary.blockers.filter(b => b.startsWith('SCREENSHOT_PROCESSING_INCOMPLETE:')).length, 4);
      assert.ok(summary.blockers.includes('SCREENSHOT_SET_DIFFERS_FROM_MANIFEST:APP_IPHONE_67') && summary.blockers.includes('SCREENSHOTS_NOT_READY:APP_IPHONE_67'));
      assert.ok(!slow.written().some(write => write.startsWith('DELETE')));
      assert.deepEqual(summary.screenshotReplacement.map(r => [r.removed, r.uploaded, r.verified]), [[0, 2, false], [0, 2, false]]);
      assert.deepEqual(targetNames(slow, 'APP_IPAD_PRO_3GEN_129').slice(0, 4), ['01-ipad.jpg', '02-ipad.jpg', '03-ipad.jpg', '04-ipad.jpg']);
    }
  });
});

test('a replacement that cannot fit beside the current images is refused before any screenshot write', async () => {
  await temp('asc-update-media-fit-', async root => {
    await mediaFixture(root, 7);
    const w = world();
    await assert.rejects(run(w, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: root}), /cannot hold its current and new files together \(limit 10\); nothing was changed/);
    assert.ok(!w.written().some(write => /appScreenshot|upload:/.test(write)));
    assert.equal(w.shots.length, 16);
    // Four current plus six new is exactly the limit.
    await mediaFixture(root, 6);
    const summary = await run(w, {...prepareEnv, APP_STORE_UPDATE_MEDIA_ROOT: root});
    assert.equal(summary.prepared, true);
    assert.deepEqual(summary.screenshotReplacement.map(r => [r.kept, r.removed, r.uploaded, r.verified]), [[0, 4, 6, true], [0, 4, 6, true]]);
    assert.equal(w.targetShots('APP_IPHONE_67').length, 6);
  });
});

test('a screenshot folder is only compared in inspect and submit, and a broken one is never ignored', async () => {
  await temp('asc-update-media-read-', async root => {
    await mediaFixture(root);
    const w = await preparedWorld();
    const count = w.calls.length, missing = join(root, 'absent');
    // The store still shows the live screenshots, which are not this manifest.
    const compared = await run(w, {APP_STORE_UPDATE_MEDIA_ROOT: root});
    assert.deepEqual(compared.blockers, DIFFER);
    assert.equal(compared.screenshots.expected, 'manifest');
    const refused = await run(w, {...submitEnv, APP_STORE_UPDATE_MEDIA_ROOT: root});
    assert.equal(refused.submitted, false);
    assert.deepEqual(refused.blockers, DIFFER);
    assert.equal(refused.screenshotReplacement, undefined);
    const broken = await run(w, {APP_STORE_UPDATE_MEDIA_ROOT: missing});
    assert.match(broken.mediaError, /manifest\.json cannot be read/);
    assert.deepEqual(broken.blockers, ['SCREENSHOT_MANIFEST_INVALID']);
    assert.equal(broken.screenshots.expected, null);
    assert.deepEqual(w.written(count), []);
    const calls = w.calls.length;
    for (const env of [prepareEnv, submitEnv]) await assert.rejects(run(w, {...env, APP_STORE_UPDATE_MEDIA_ROOT: missing}), /manifest\.json cannot be read/);
    assert.equal(w.calls.length, calls, 'a broken folder stops prepare and submit before any request');
    assert.equal(w.shots.length, 16);
  });
});

test('inspect and submit stop when the release setting on Apple is not the one asked for', async () => {
  const w = await preparedWorld();
  const manual = {APP_STORE_RELEASE_TYPE: 'MANUAL'}, count = w.calls.length;
  const inspected = await run(w, manual);
  assert.deepEqual(inspected.blockers, ['RELEASE_TYPE_DIFFERS_FROM_INPUT:AFTER_APPROVAL']);
  assert.equal(inspected.appliedReleaseType, 'AFTER_APPROVAL');
  const refused = await run(w, {...submitEnv, ...manual});
  assert.equal(refused.submitted, false);
  assert.deepEqual(refused.blockers, ['RELEASE_TYPE_DIFFERS_FROM_INPUT:AFTER_APPROVAL']);
  assert.equal(exitCodeFor(refused), 2);
  assert.deepEqual(w.written(count), [], 'submit never changes the release setting and never submits past a mismatch');
  assert.equal(w.target().attributes.appVersionState, 'PREPARE_FOR_SUBMISSION');
  assert.equal(w.submissions.length, 1);
  // Only prepare changes it; after that the same input submits.
  await run(w, {...prepareEnv, ...manual});
  assert.deepEqual(w.written(count), ['PATCH /v1/appStoreVersions/' + w.target().id]);
  const sent = await run(w, {...submitEnv, ...manual});
  assert.equal(sent.submitted, true);
  assert.equal(sent.appliedReleaseType, 'MANUAL');
  assert.deepEqual(sent.blockers, []);
  assert.equal(exitCodeFor(sent), 0);
  // Once it is with Apple the setting cannot be changed here: KEEP and the applied value are clean, another value is not.
  const after = w.calls.length;
  for (const env of [{}, manual]) {
    const again = await run(w, {...submitEnv, ...env});
    assert.equal(again.alreadySubmitted, true);
    assert.deepEqual(again.blockers, []);
    assert.equal(exitCodeFor(again), 0);
  }
  const late = await run(w, {...submitEnv, APP_STORE_RELEASE_TYPE: 'AFTER_APPROVAL'});
  assert.equal(late.submitted, true);
  assert.equal(late.alreadySubmitted, true);
  assert.equal(late.appliedReleaseType, 'MANUAL');
  assert.deepEqual(late.blockers, ['RELEASE_TYPE_DIFFERS_FROM_INPUT:MANUAL']);
  assert.equal(exitCodeFor(late), 2);
  assert.deepEqual(w.written(after), []);
});

test('a version in review with another build is not reported as this build being submitted', async () => {
  const w = await preparedWorld();
  assert.equal((await run(w, submitEnv)).submitted, true);
  const count = w.calls.length;
  // Inspect of the matching build says where it is.
  const matching = await run(w);
  assert.equal(matching.submitted, true);
  assert.equal(matching.alreadySubmitted, true);
  assert.equal(matching.submissionState, 'WAITING_FOR_REVIEW');
  assert.equal(matching.submissionId, w.submissions.at(-1).id);
  assert.deepEqual(matching.blockers, []);
  for (const [link, label] of [[rel('builds', 'b13'), '13'], [{data: null}, 'none']]) {
    w.target().relationships.build = link;
    for (const env of [submitEnv, {}]) {
      const summary = await run(w, env);
      assert.equal(summary.submitted, false);
      assert.equal(summary.alreadySubmitted, undefined);
      assert.deepEqual(summary.blockers, ['VERSION_IN_REVIEW_WITH_DIFFERENT_BUILD:' + label]);
      if (env === submitEnv) assert.equal(exitCodeFor(summary), 2);
    }
  }
  assert.deepEqual(w.written(count), []);
});

test('a submit request whose answer is lost is settled by reading the state, never by guessing', async () => {
  await temp('asc-update-lost-', async directory => {
    const path = join(directory, 'summary.json');
    const lostAt = (current, call, state) => {
      if (call.method === 'GET' && state.down) throw new TypeError('socket closed PRIVATE-FIRST');
      if (call.method !== 'PATCH' || !call.path.startsWith('/v1/reviewSubmissions/') || !state.lose) return null;
      if (state.applied) {
        current().submissions.at(-1).attributes.state = 'WAITING_FOR_REVIEW';
        current().target().attributes.appVersionState = 'WAITING_FOR_REVIEW';
      }
      if (state.thenDown) state.down = true;
      throw new TypeError('socket closed PRIVATE-FIRST');
    };
    // Apple applied the request; the answer never arrived.
    const applied = {lose: false, applied: true};
    const w = await preparedWorld({intercept: call => lostAt(() => w, call, applied)});
    applied.lose = true;
    const count = w.calls.length;
    const summary = await run(w, submitEnv);
    const patch = {method: 'PATCH', path: '/v1/reviewSubmissions/' + w.submissions.at(-1).id};
    assert.equal(summary.submitted, true);
    assert.equal(summary.submitResponseLost, true);
    assert.equal(summary.submitRequestAccepted, undefined);
    assert.equal(summary.submissionState, 'WAITING_FOR_REVIEW');
    assert.equal(summary.versionState, 'WAITING_FOR_REVIEW');
    assert.deepEqual(summary.uncertainWrites, [patch]);
    assert.deepEqual(summary.writes.map(write => write.method), ['POST', 'POST'], 'an unanswered write is not listed as made');
    assert.deepEqual(summary.blockers, []);
    assert.equal(exitCodeFor(summary), 0);
    assert.equal(w.written(count).filter(write => write.startsWith('PATCH')).length, 1, 'the request is not sent twice');
    // Apple did not apply it: reported as unknown, not as submitted and not as a plain delay.
    const dropped = {lose: false, applied: false};
    const d = await preparedWorld({intercept: call => lostAt(() => d, call, dropped)});
    dropped.lose = true;
    const unknown = await run(d, submitEnv);
    assert.equal(unknown.submitted, false);
    assert.deepEqual(unknown.blockers, ['SUBMIT_REQUEST_OUTCOME_UNKNOWN']);
    assert.equal(unknown.uncertainWrites.length, 1);
    assert.equal(exitCodeFor(unknown), 2);
    // The connection stays down: the error names the request, and inspect then tells the truth.
    const gone = {lose: false, applied: true, thenDown: true};
    const g = await preparedWorld({intercept: call => lostAt(() => g, call, gone)});
    gone.lose = true;
    let message = '';
    await assert.rejects(run(g, {...submitEnv, APP_STORE_UPDATE_SUMMARY_PATH: path}), error => { message = error.message; return error instanceof UpdateError; });
    const submissionPath = '/v1/reviewSubmissions/' + g.submissions.at(-1).id;
    assert.equal(message, 'Apple API request failed or timed out: GET ' + submissionPath + '. Outcome unknown for PATCH ' + submissionPath + '; run inspect before trying again.');
    const saved = JSON.parse(await readFile(path, 'utf8'));
    assert.equal(saved.error, message);
    assert.equal(saved.submitted, false);
    assert.deepEqual(saved.uncertainWrites, [{method: 'PATCH', path: submissionPath}]);
    assertNoSecrets(JSON.stringify(saved) + message);
    gone.down = false; gone.lose = false;
    const before = g.calls.length;
    const inspected = await run(g);
    assert.equal(inspected.submitted, true);
    assert.equal(inspected.alreadySubmitted, true);
    assert.equal(inspected.submissionState, 'WAITING_FOR_REVIEW');
    assert.equal(inspected.uncertainWrites, undefined);
    assert.ok(g.calls.slice(before).every(call => call.method === 'GET'));
    // A lost answer during prepare is named the same way; the next run settles it.
    let lose = true;
    const p = world({intercept: ({method, path: requestPath}) => {
      if (!lose || method !== 'PATCH' || !requestPath.startsWith('/v1/appStoreVersionLocalizations/')) return null;
      p.targetLocale().attributes.whatsNew = draftFile.whatsNew.ko;
      throw new TypeError('socket closed');
    }});
    await assert.rejects(run(p, prepareEnv), /^Error: Apple API request failed or timed out: PATCH \/v1\/appStoreVersionLocalizations\/locale-\d+\. Outcome unknown for PATCH \/v1\/appStoreVersionLocalizations\/locale-\d+; run inspect before trying again\.$/);
    lose = false;
    const start = p.calls.length;
    assert.equal((await run(p, prepareEnv)).prepared, true);
    assert.ok(!p.written(start).some(write => write.includes('appStoreVersionLocalizations')));
  });
});

test('a version left in an unsubmitted review submission can still be repaired by prepare', async () => {
  await temp('asc-update-draft-item-', async directory => {
    const path = join(directory, 'summary.json');
    let fail = true;
    const w = await preparedWorld({intercept: ({method, path: requestPath}) => fail && method === 'PATCH' && requestPath.startsWith('/v1/reviewSubmissions/')
      ? Response.json({errors: [{code: 'STATE_ERROR.ENTITY_STATE_INVALID', detail: 'The review notes are incomplete.'}]}, {status: 409}) : null});
    await assert.rejects(run(w, submitEnv), /Apple API HTTP 409 for PATCH \/v1\/reviewSubmissions\//);
    assert.equal(w.target().attributes.appVersionState, 'READY_FOR_REVIEW');
    // The cause has to be fixed on the version: text, notes and build are editable again.
    w.targetLocale().attributes.whatsNew = '다른 문구';
    w.targetReview().attributes.notes = 'OLD-PRIVATE-NOTES';
    w.target().relationships.build = rel('builds', 'b13');
    const blocked = await run(w, submitEnv);
    assert.deepEqual(blocked.blockers, ['ATTACHED_BUILD_IS_NOT_TARGET', 'WHATS_NEW_DIFFERS_FROM_DRAFT', 'REVIEW_NOTES_DIFFER_FROM_DRAFT']);
    const count = w.calls.length, target = w.target();
    const repaired = await run(w, prepareEnv);
    assert.deepEqual(w.written(count), ['PATCH /v1/appStoreVersionLocalizations/' + w.targetLocale().id, 'PATCH /v1/appStoreReviewDetails/' + w.targetReview().id,
      'PATCH /v1/appStoreVersions/' + target.id + '/relationships/build']);
    assert.equal(repaired.prepared, true);
    assert.equal(repaired.versionState, 'READY_FOR_REVIEW');
    assert.deepEqual(repaired.replacedBuild, {id: 'b13', buildNumber: '13'});
    assert.equal(w.versions.length, 2);
    fail = false;
    const start = w.calls.length;
    const sent = await run(w, submitEnv);
    assert.deepEqual(w.written(start), ['PATCH /v1/reviewSubmissions/' + w.submissions.at(-1).id]);
    assert.equal(sent.submitted, true);
    assert.equal(w.submissions.length, 2);
    // Any other READY_FOR_REVIEW arrangement stays closed, and the refusal says where to continue.
    const arrangements = [
      d => { d.items.push({submission: 'sub-x', resource: obj('reviewSubmissionItems', 'item-y', {}, {appStoreVersion: {data: null}, appEvent: rel('appEvents', 'event-1')})}); },
      d => { d.submissions.at(-1).attributes.state = 'UNRESOLVED_ISSUES'; },
      d => { d.submissions.push(obj('reviewSubmissions', 'sub-second', {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)})); },
      d => { d.items.length = 0; },
    ];
    for (const arrange of arrangements) {
      const d = world();
      const version = d.addVersion(VERSION, 'READY_FOR_REVIEW', {releaseType: 'AFTER_APPROVAL', copyright: '2026 Owner'});
      d.submissions.push(obj('reviewSubmissions', 'sub-x', {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', A)}));
      d.items.push({submission: 'sub-x', resource: obj('reviewSubmissionItems', 'item-x', {}, {appStoreVersion: rel('appStoreVersions', version.id)})});
      arrange(d);
      await assert.rejects(run(d, {...prepareEnv, APP_STORE_UPDATE_SUMMARY_PATH: path}),
        /Prepare refused: TARGET_VERSION_STATE_NOT_EDITABLE:READY_FOR_REVIEW\. This helper edits a version only in .* Continue in App Store Connect: a rejected version is resubmitted there/);
      assert.deepEqual(d.written(), []);
      assert.match(JSON.parse(await readFile(path, 'utf8')).guidance, /Continue in App Store Connect/);
    }
    // A rejected version is not resubmitted by this helper; both modes say so instead of only refusing.
    for (const state of ['REJECTED', 'METADATA_REJECTED', 'DEVELOPER_REJECTED']) {
      const r = await preparedWorld();
      r.target().attributes.appVersionState = state;
      const count = r.calls.length;
      await assert.rejects(run(r, prepareEnv), /Continue in App Store Connect/);
      const summary = await run(r, submitEnv);
      assert.ok(summary.blockers.includes('TARGET_VERSION_STATE_UNEXPECTED:' + state));
      assert.match(summary.guidance, /a rejected version is resubmitted there/);
      assert.deepEqual(r.written(count), []);
    }
    assert.equal((await run(await preparedWorld())).guidance, undefined);
  });
});

test('screenshots are not touched while the version sits in a review submission', async () => {
  await temp('asc-update-draft-media-', async root => {
    await mediaFixture(root);
    const media = {APP_STORE_UPDATE_MEDIA_ROOT: root};
    const refuse = ({method, path}) => method === 'PATCH' && path.startsWith('/v1/reviewSubmissions/')
      ? Response.json({errors: [{code: 'STATE_ERROR.ENTITY_STATE_INVALID'}]}, {status: 409}) : null;
    // The store still shows the live images: a folder is compared, reported, and not uploaded.
    const w = await preparedWorld({intercept: refuse});
    await assert.rejects(run(w, submitEnv), /Apple API HTTP 409/);
    assert.equal(w.target().attributes.appVersionState, 'READY_FOR_REVIEW');
    const count = w.calls.length;
    const summary = await run(w, {...prepareEnv, ...media});
    assert.deepEqual(w.written(count), []);
    assert.equal(summary.prepared, false);
    assert.equal(summary.screenshotReplacement, undefined);
    assert.deepEqual(summary.blockers, [...DIFFER, 'SCREENSHOTS_NOT_EDITABLE_IN_A_REVIEW_SUBMISSION']);
    assert.match(summary.guidance, /removing the version from its draft submission returns it to PREPARE_FOR_SUBMISSION/);
    assert.equal(w.shots.length, 16);
    assert.equal((await run(w, prepareEnv)).prepared, true, 'without a folder the live images are still the expected ones');
    // Images replaced before the submit attempt already equal the folder: nothing to do, nothing blocked.
    const replaced = world({intercept: refuse});
    assert.equal((await run(replaced, {...prepareEnv, ...media})).prepared, true);
    await assert.rejects(run(replaced, {...submitEnv, ...media}), /Apple API HTTP 409/);
    const start = replaced.calls.length;
    const again = await run(replaced, {...prepareEnv, ...media});
    assert.equal(again.prepared, true);
    assert.equal(again.guidance, undefined);
    assert.deepEqual(replaced.written(start), []);
  });
});

test('command line runs through a symlinked path instead of exiting 0 without doing anything', async () => {
  const preload = 'data:text/javascript,' + encodeURIComponent(
    'globalThis.fetch = async () => new Response(JSON.stringify({errors: [{code: "FORBIDDEN_ERROR"}]}), {status: 403});');
  const execute = (args, env) => new Promise(done => execFile(process.execPath, args,
    {env: {...base, ...env, PATH: process.env.PATH}}, (error, stdout, stderr) => done({code: error?.code ?? 0, stdout, stderr})));
  await temp('asc-update-link-', async directory => {
    const linkedFolder = join(directory, 'linked-scripts'), linkedFile = join(directory, 'update-link.mjs');
    await symlink(dirname(SCRIPT), linkedFolder, 'dir');
    await symlink(SCRIPT, linkedFile);
    const throughFolder = join(linkedFolder, 'app_store_update.mjs');
    for (const args of [[throughFolder], [linkedFile], ['--preserve-symlinks-main', throughFolder]]) {
      const label = args.join(' ').replace(directory, '');
      const refused = await execute(['--import', preload, ...args], {APP_STORE_UPDATE_MODE: 'submit', APP_STORE_SUBMIT: 'true'});
      assert.equal(refused.code, 1, label);
      assert.equal(refused.stderr.trim(), 'Apple API HTTP 403 for GET /v1/apps/' + A + '; codes=FORBIDDEN_ERROR.', label);
      const invalid = await execute(args, {APP_STORE_UPDATE_MODE: 'nonsense'});
      assert.equal(invalid.code, 1, label);
      assert.equal(invalid.stderr.trim(), 'Mode must be inspect, prepare or submit.', label);
    }
  });
});

test('every request passes the write gate: no mode can send a write outside its list', async () => {
  const done = new UpdateError('probe finished');
  for (const env of [{}, prepareEnv, submitEnv]) {
    const w = await preparedWorld();
    const count = w.calls.length, targetId = w.target().id, release = {data: {type: 'appStoreVersions', id: targetId, attributes: {releaseType: 'MANUAL'}}};
    await assert.rejects(run(w, env, {...quiet, probe: async request => {
      for (const [path, method, body] of [
        ['/v1/appStoreVersions/' + w.live.id, 'PATCH', {data: {type: 'appStoreVersions', id: w.live.id, attributes: {releaseType: 'MANUAL'}}}],
        ['/v1/appStoreVersions/' + targetId, 'DELETE'],
        ['/v1/appStoreVersions/' + targetId + '/relationships/build', 'PATCH', {data: null}],
        ['/v1/apps/' + A, 'PATCH', {data: {type: 'apps', id: A, attributes: {contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT'}}}],
        ['/v1/appStoreVersionReleaseRequests', 'POST', {data: {type: 'appStoreVersionReleaseRequests', relationships: {appStoreVersion: rel('appStoreVersions', targetId)}}}],
        ['/v1/appScreenshots/' + w.targetShots('APP_IPHONE_67')[0].id, 'DELETE'],
        ['/v1/reviewSubmissions/sub-old', 'PATCH', {data: {type: 'reviewSubmissions', id: 'sub-old', attributes: {canceled: true}}}],
        // Permitted in prepare without the query string; never with one.
        ['/v1/appStoreVersions/' + targetId + '?include=app', 'PATCH', release],
        ...(env === prepareEnv ? [] : [['/v1/appStoreVersions/' + targetId, 'PATCH', release]]),
        ...(env === submitEnv ? [] : [['/v1/reviewSubmissions', 'POST', {data: {type: 'reviewSubmissions', attributes: {platform: 'IOS'}, relationships: {app: rel('apps', A)}}}]]),
      ]) await assert.rejects(request(path, method, body), /Write is outside the permitted update operations/, method + ' ' + path);
      assert.deepEqual(w.written(count), [], 'a refused write is never sent');
      // The same gate lets the listed operation of this mode through, so the probe is the real request path.
      if (env === prepareEnv) {
        await request('/v1/appStoreVersions/' + targetId, 'PATCH', release);
        assert.equal(w.target().attributes.releaseType, 'MANUAL');
      }
      throw done;
    }}), error => error === done);
    assert.deepEqual(w.written(count), env === prepareEnv ? ['PATCH /v1/appStoreVersions/' + targetId] : []);
  }
});

test('resources that do not belong to the target app or version, and ambiguous targets, stop every mode without writes', async () => {
  const modes = [{}, prepareEnv, submitEnv];
  const refusedEverywhere = async (arrange, pattern, options) => {
    for (const env of modes) {
      const w = await preparedWorld(options?.());
      await arrange(w);
      const count = w.calls.length;
      await assert.rejects(run(w, env), pattern);
      assert.deepEqual(w.written(count), []);
    }
  };
  await refusedEverywhere(w => { w.live.relationships.app = rel('apps', '1111111111'); }, /belongs to an unexpected parent/);
  await refusedEverywhere(w => { w.target().relationships.app = {data: null}; }, /belongs to an unexpected parent/);
  await refusedEverywhere(w => { w.submissions.push(obj('reviewSubmissions', 'sub-foreign', {platform: 'IOS', state: 'READY_FOR_REVIEW'}, {app: rel('apps', '1111111111')})); },
    /belongs to an unexpected parent/);
  await refusedEverywhere(w => { w.addVersion(VERSION, 'PREPARE_FOR_SUBMISSION', {releaseType: 'MANUAL'}); }, /More than one App Store version matches the target version/);
  await refusedEverywhere(w => {
    w.builds.push(obj('builds', 'b-twin', {version: BUILD, processingState: 'VALID', expired: false, usesNonExemptEncryption: false}));
    w.prerelease['b-twin'] = obj('preReleaseVersions', 'pre-twin', {version: '1.0.1', platform: 'IOS'});
  }, /More than one build matches the target version and build number/);
  // Apple answers the build filter with a build of another number.
  let wrongBuild = false;
  await refusedEverywhere(() => { wrongBuild = true; }, /Unexpected build list for the target build number/, () => {
    wrongBuild = false;
    return {intercept: ({method, path}) => wrongBuild && method === 'GET' && path === '/v1/builds'
      ? Response.json({data: [obj('builds', 'b13', {version: '13', processingState: 'VALID', expired: false})]}) : null};
  });
});

test('pagination never leaves the list it started on', async () => {
  const versionsPath = `/v1/apps/${A}/appStoreVersions`;
  for (const next of [url => 'https://api.appstoreconnect.apple.com/v1/apps/' + A + '/reviewSubmissions?limit=200', url => url.href,
    url => 'https://api.appstoreconnect.apple.com/v1/apps/1111111111/appStoreVersions']) {
    const w = world({intercept: ({path, url}) => path === versionsPath ? Response.json({data: [], links: {next: next(url)}}) : null});
    await assert.rejects(run(w, prepareEnv), /Unexpected pagination/);
    assert.equal(w.calls.filter(call => call.path === versionsPath).length, 1);
    assert.ok(w.calls.every(call => call.method === 'GET'));
  }
  // A second page of the same list is read.
  const paged = world({intercept: ({path, url}) => path === versionsPath && !url.searchParams.has('cursor')
    ? Response.json({data: [], links: {next: url.href + '&cursor=2'}}) : null});
  assert.deepEqual((await run(paged)).versions.map(v => v.versionString), ['1.0']);
});

test('every write is read back, and a mismatch stops the run before the next step', async () => {
  const unchanged = collection => (w, id) => Response.json({data: collection(w).find(entry => entry.id === id)});
  const prepareCases = [
    ['created version missing from the app list', {}, (w, {method, path}) => method === 'GET' && path === `/v1/apps/${A}/appStoreVersions` && w.versions.length > 1
      ? Response.json({data: [w.live]}) : null, /Created version was not confirmed through the app/, ['POST /v1/appStoreVersions']],
    ['created version with another release setting', {}, (w, {method, path}) => { if (method === 'GET' && path === `/v1/apps/${A}/appStoreVersions` && w.target()) w.target().attributes.releaseType = 'MANUAL'; return null; },
      /Created version was not confirmed through the app/, ['POST /v1/appStoreVersions']],
    ['created version in another state', {}, (w, {method, path}) => { if (method === 'GET' && path === `/v1/apps/${A}/appStoreVersions` && w.target()) w.target().attributes.appVersionState = 'DEVELOPER_REJECTED'; return null; },
      /Created version was not confirmed through the app/, ['POST /v1/appStoreVersions']],
    ['release text not applied', {}, (w, {method, path}) => method === 'PATCH' && path.startsWith('/v1/appStoreVersionLocalizations/')
      ? unchanged(x => x.locales)(w, path.split('/').at(-1)) : null, /Release text readback mismatch/, ['POST /v1/appStoreVersions', 'PATCH localization']],
    ['review notes not applied', {}, (w, {method, path}) => method === 'PATCH' && path.startsWith('/v1/appStoreReviewDetails/')
      ? unchanged(x => x.reviews)(w, path.split('/').at(-1)) : null, /Review notes or contact readback mismatch/, ['POST /v1/appStoreVersions', 'PATCH localization', 'PATCH review']],
    ['review detail of another version', {}, (w, {method, path}) => method === 'GET' && /^\/v1\/appStoreReviewDetails\/[^/]+$/.test(path)
      ? Response.json({data: {...w.targetReview(), relationships: {appStoreVersion: rel('appStoreVersions', w.live.id)}}}) : null,
    /belongs to an unexpected parent/, ['POST /v1/appStoreVersions', 'PATCH localization']],
    ['created review detail with other contact values', {carryReview: false, env: {APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON}},
      (w, {method, path}) => { if (method === 'GET' && path.endsWith('/appStoreReviewDetail') && w.targetReview()) w.targetReview().attributes.contactEmail = 'someone.else@example.invalid'; return null; },
      /Review notes or contact readback mismatch/, ['POST /v1/appStoreVersions', 'PATCH localization', 'POST /v1/appStoreReviewDetails']],
    ['build no longer valid just before attaching', {}, (w, {method, path}) => method === 'GET' && path === '/v1/builds/b-target'
      ? Response.json({data: obj('builds', 'b-target', {version: BUILD, processingState: 'VALID', expired: true})}) : null,
    /Target build is no longer valid and unexpired/, ['POST /v1/appStoreVersions', 'PATCH localization', 'PATCH review']],
    ['build of another number just before attaching', {}, (w, {method, path}) => method === 'GET' && path === '/v1/builds/b-target'
      ? Response.json({data: obj('builds', 'b-target', {version: '13', processingState: 'VALID', expired: false})}) : null,
    /Target build is no longer valid and unexpired/, ['POST /v1/appStoreVersions', 'PATCH localization', 'PATCH review']],
    ['build attachment not applied', {}, (w, {method, path}) => method === 'PATCH' && path.endsWith('/relationships/build') ? new Response(null, {status: 204}) : null,
      /Build attachment readback mismatch/, ['POST /v1/appStoreVersions', 'PATCH localization', 'PATCH review', 'PATCH build']],
  ];
  const short = write => write.replace(/^PATCH \/v1\/appStoreVersionLocalizations\/.*/, 'PATCH localization').replace(/^PATCH \/v1\/appStoreReviewDetails\/.*/, 'PATCH review')
    .replace(/^PATCH \/v1\/appStoreVersions\/.*\/relationships\/build$/, 'PATCH build');
  await temp('asc-update-readback-', async directory => {
    const path = join(directory, 'summary.json');
    for (const [label, {env, ...options}, intercept, pattern, writes] of prepareCases) {
      const w = world({...options, intercept: call => intercept(w, call)});
      await assert.rejects(run(w, {...prepareEnv, ...env, APP_STORE_UPDATE_SUMMARY_PATH: path}), pattern, label);
      assert.deepEqual(w.written().map(short), writes, label);
      const saved = JSON.parse(await readFile(path, 'utf8'));
      assert.notEqual(saved.prepared, true, label);
      assertNoSecrets(JSON.stringify(saved), label);
    }
    // An explicit release setting that Apple did not take.
    let ignore = false;
    const kept = await preparedWorld({intercept: ({method, path: requestPath}) => ignore && method === 'PATCH' && /^\/v1\/appStoreVersions\/[^/]+$/.test(requestPath)
      ? Response.json({data: kept.target()}) : null});
    ignore = true;
    await assert.rejects(run(kept, {...prepareEnv, APP_STORE_RELEASE_TYPE: 'MANUAL'}), /Release setting readback mismatch/);
    const submitCases = [
      ['created submission missing from the app list', (w, {method, path: requestPath}) => method === 'GET' && requestPath === `/v1/apps/${A}/reviewSubmissions` && w.submissions.length > 1
        ? Response.json({data: [w.submissions[0]]}) : null, /Created review submission was not confirmed through the app/, ['POST /v1/reviewSubmissions']],
      ['created submission in another state', (w, {method, path: requestPath}) => { if (method === 'GET' && requestPath === `/v1/apps/${A}/reviewSubmissions` && w.submissions.length > 1) w.submissions.at(-1).attributes.state = 'CANCELING'; return null; },
        /Created review submission was not confirmed through the app/, ['POST /v1/reviewSubmissions']],
      ['item linked to another version', (w, {method, path: requestPath}) => method === 'GET' && requestPath.endsWith('/items') && w.items.length
        ? Response.json({data: [obj('reviewSubmissionItems', 'item-other', {}, {appStoreVersion: rel('appStoreVersions', w.live.id)})]}) : null,
      /Review version association was not confirmed/, ['POST /v1/reviewSubmissions', 'POST /v1/reviewSubmissionItems']],
      ['second item in the new submission', (w, {method, path: requestPath}) => method === 'GET' && requestPath.endsWith('/items') && w.items.length
        ? Response.json({data: [w.items[0].resource, obj('reviewSubmissionItems', 'item-extra', {}, {appStoreVersion: rel('appStoreVersions', w.target().id)})]}) : null,
      /Review version association was not confirmed/, ['POST /v1/reviewSubmissions', 'POST /v1/reviewSubmissionItems']],
    ];
    for (const [label, intercept, pattern, writes] of submitCases) {
      let armed = false;
      const w = await preparedWorld({intercept: call => armed ? intercept(w, call) : null});
      armed = true;
      const count = w.calls.length;
      await assert.rejects(run(w, {...submitEnv, APP_STORE_UPDATE_SUMMARY_PATH: path}), pattern, label);
      assert.deepEqual(w.written(count), writes, label + ': the submit request itself is never sent');
      assert.equal(JSON.parse(await readFile(path, 'utf8')).submitted, false, label);
    }
  });
});

test('draft limits and unexpected failures', async () => {
  await temp('asc-update-limits-', async directory => {
    const path = join(directory, 'draft.json'), head = `Build: ${VERSION} (${BUILD}). `;
    const write = (whatsNew, reviewNotes) => writeFile(path, JSON.stringify({version: VERSION, whatsNew: {ko: whatsNew}, reviewNotes}));
    await write('가'.repeat(4000), head + 'n'.repeat(4000 - head.length));
    assert.equal((await loadUpdateDraft(path, VERSION, BUILD)).reviewNotes.length, 4000);
    await write('가'.repeat(4000), head + 'n'.repeat(4001 - head.length));
    await assert.rejects(loadUpdateDraft(path, VERSION, BUILD), /Review notes must contain 1 to 4000 characters/);
    await write('가'.repeat(4001), head);
    await assert.rejects(loadUpdateDraft(path, VERSION, BUILD), /Release text must contain 1 to 4000 characters/);
    await write(' ', head);
    await assert.rejects(loadUpdateDraft(path, VERSION, BUILD), /Release text must contain 1 to 4000 characters/);
    await writeFile(path, JSON.stringify({version: VERSION, whatsNew: {ko: '수정', 'en-US': 'Fixes'}, reviewNotes: head}));
    await assert.rejects(loadUpdateDraft(path, VERSION, BUILD), /exactly the Korean release text/);
    // An error this helper did not foresee is replaced by a fixed sentence, in the result and in the saved summary.
    const summaryPath = join(directory, 'summary.json');
    const w = await preparedWorld({intercept: ({method, path: requestPath}) => method === 'PATCH' && requestPath.startsWith('/v1/reviewSubmissions/')
      ? Response.json({data: obj('reviewSubmissions', requestPath.split('/').at(-1), {platform: 'IOS', state: 'READY_FOR_REVIEW'})}) : null});
    let message = '';
    await assert.rejects(run(w, {...submitEnv, APP_STORE_UPDATE_SUMMARY_PATH: summaryPath, APP_STORE_REVIEW_CONTACT_JSON: CONTACT_JSON},
      {sleep: async () => { throw new Error('boom ' + contact.contactEmail + ' ' + P8); }}), error => { message = error.message; return error instanceof UpdateError; });
    assert.equal(message, 'Update helper failed; private details withheld.');
    const saved = await readFile(summaryPath, 'utf8');
    assert.equal(JSON.parse(saved).error, message);
    assert.equal(JSON.parse(saved).submitted, false);
    assertNoSecrets(saved);
  });
});
