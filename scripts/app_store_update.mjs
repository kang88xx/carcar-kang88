// App Store UPDATE helper for the live carcar app: inspect, prepare, or submit
// exactly one new iOS version. Bounded on purpose. This file contains no code
// for pricing, availability, app information, categories, age rating, privacy
// answers, TestFlight groups or testers, releasing or deleting a version, or
// cancelling a review submission, and every write is tied to an ID that was
// first read through the target app.
import {createPrivateKey, sign, createHash} from 'node:crypto';
import {realpathSync} from 'node:fs';
import {readFile, writeFile, realpath, chmod, mkdir} from 'node:fs/promises';
import {resolve, sep, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {parseReviewContact, uploadParts, jpegSize, RegistrationError} from './app_store_registration.mjs';
import {safeSubmissionDiagnostic, privateSubmissionDiagnostic} from './app_store_submit.mjs';

export const UPDATE_APP_ID = '6829616379';
const APP_ID = UPDATE_APP_ID;
const BUNDLE = 'com.kang88.carcar';
const ORIGIN = 'https://api.appstoreconnect.apple.com';
const LOCALE = 'ko';
// Same device families and pixel sizes as the first submission.
const FAMILIES = {iphone: ['APP_IPHONE_67', 1320, 2868], ipad: ['APP_IPAD_PRO_3GEN_129', 2064, 2752]};
const CONTACT_KEYS = ['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'];
// appVersionState, with the deprecated appStoreState name for the live state.
const LIVE_STATES = ['READY_FOR_DISTRIBUTION', 'READY_FOR_SALE'];
const RETIRED_STATES = ['REPLACED_WITH_NEW_VERSION'];
const IN_REVIEW_STATES = ['WAITING_FOR_REVIEW', 'IN_REVIEW'];
const RELEASE_TYPES = ['MANUAL', 'AFTER_APPROVAL'];
const POLL_MS = 2000;
const SET_LIMIT = 10;
const STATE_GUIDANCE = 'This helper edits a version only in PREPARE_FOR_SUBMISSION, or (everything except screenshots) in READY_FOR_REVIEW'
  + ' while it is the only item of one unsubmitted review submission. Continue in App Store Connect: a rejected version is resubmitted'
  + ' there, and removing the version from its draft submission returns it to PREPARE_FOR_SUBMISSION.';

export class UpdateError extends Error {}
const check = (ok, message) => { if (!ok) throw new UpdateError(message); };
const digest = (data, algorithm = 'sha256') => createHash(algorithm).update(data).digest('hex');
const filled = value => typeof value === 'string' && value.trim().length > 0;
const normalize = text => text.replace(/\r\n?/g, '\n').trim();
const sameText = (a, b) => typeof a === 'string' && typeof b === 'string' && normalize(a) === normalize(b);
const versionState = resource => resource?.attributes?.appVersionState ?? resource?.attributes?.appStoreState ?? null;
const relationTo = (type, id) => ({data: {type, id}});

function item(data, type, id) {
  check(data?.type === type && typeof data.id === 'string' && /^[A-Za-z0-9._~=-]{1,512}$/.test(data.id)
    && !['.', '..'].includes(data.id) && (!id || data.id === id), 'Unexpected Apple resource identity.');
  return data;
}
function relation(data, name, type, id) {
  const value = data.relationships?.[name]?.data;
  check(value?.type === type && value.id === id, 'Apple resource belongs to an unexpected parent.');
}

/** "1.0" and "1.0.0" are the same release for Apple; compare as three numbers. */
export function parseVersion(value) {
  check(typeof value === 'string' && /^[0-9]{1,4}\.[0-9]{1,4}(?:\.[0-9]{1,4})?$/.test(value), 'Version must look like 1.0.1.');
  const parts = value.split('.').map(Number);
  while (parts.length < 3) parts.push(0);
  return parts;
}
export function compareVersions(a, b) {
  const x = parseVersion(a), y = parseVersion(b);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
}
const comparable = value => { try { parseVersion(value); return true; } catch { return false; } };

export function updateConfig(env) {
  const mode = env.APP_STORE_UPDATE_MODE || 'inspect';
  check(['inspect', 'prepare', 'submit'].includes(mode), 'Mode must be inspect, prepare or submit.');
  check(!env.CARCAR_APP_ID || env.CARCAR_APP_ID === APP_ID, 'This helper is restricted to carcar.');
  const version = env.APP_STORE_UPDATE_VERSION, build = env.APP_STORE_UPDATE_BUILD;
  check(filled(version), 'APP_STORE_UPDATE_VERSION is required.');
  parseVersion(version);
  check(typeof build === 'string' && /^[1-9][0-9]{0,8}$/.test(build), 'APP_STORE_UPDATE_BUILD must be a positive integer.');
  const release = env.APP_STORE_RELEASE_TYPE || 'KEEP';
  check(release === 'KEEP' || RELEASE_TYPES.includes(release), 'Release type must be KEEP, MANUAL or AFTER_APPROVAL.');
  if (mode === 'submit') check(env.APP_STORE_SUBMIT === 'true', 'Submission requires APP_STORE_SUBMIT to be exactly true.');
  return {mode, version, build, release, draftPath: env.APP_STORE_UPDATE_DRAFT_PATH || 'docs/app-store/update-' + version + '.json',
    mediaRoot: env.APP_STORE_UPDATE_MEDIA_ROOT || null};
}

export async function loadUpdateDraft(path, version, build) {
  let draft;
  try { draft = JSON.parse(await readFile(resolve(path), 'utf8')); }
  catch { throw new UpdateError('Update draft file is missing or is not valid JSON.'); }
  check(draft && typeof draft === 'object' && !Array.isArray(draft) && draft.version === version, 'Update draft is for a different version.');
  check(draft.whatsNew && typeof draft.whatsNew === 'object' && Object.keys(draft.whatsNew).join() === LOCALE,
    'Update draft must contain exactly the Korean release text.');
  const whatsNew = draft.whatsNew[LOCALE], reviewNotes = draft.reviewNotes;
  check(filled(whatsNew) && whatsNew.length <= 4000, 'Release text must contain 1 to 4000 characters.');
  check(filled(reviewNotes) && reviewNotes.length <= 4000, 'Review notes must contain 1 to 4000 characters.');
  check(reviewNotes.includes('Build: ' + version + ' (' + build + ')'), 'Review notes do not name the target build.');
  return {whatsNew: normalize(whatsNew), reviewNotes: normalize(reviewNotes)};
}

/** manifest.json: {devices: [{deviceFamily: 'iphone'|'ipad', screenshots: [{file, width, height, hasAlpha, sha256}]}]}.
 * Files live in <root>/<family>/<file>; manifest order is the store order. */
export async function loadUpdateMedia(directory) {
  let root, manifest;
  try { root = await realpath(directory); manifest = JSON.parse(await readFile(resolve(root, 'manifest.json'), 'utf8')); }
  catch { throw new UpdateError('Screenshot folder or its manifest.json cannot be read.'); }
  const media = [];
  for (const [family, [display, width, height]] of Object.entries(FAMILIES)) {
    const devices = Array.isArray(manifest?.devices) ? manifest.devices.filter(device => device?.deviceFamily === family) : [];
    check(devices.length === 1 && Array.isArray(devices[0].screenshots)
      && devices[0].screenshots.length >= 1 && devices[0].screenshots.length <= 10, 'Screenshot manifest must list 1 to 10 files per device family.');
    const names = new Set();
    for (const entry of devices[0].screenshots) {
      check(typeof entry?.file === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,60}\.jpe?g$/.test(entry.file) && !names.has(entry.file), 'Invalid or duplicate screenshot file name.');
      names.add(entry.file);
      let file, bytes;
      try { file = await realpath(resolve(root, family, entry.file)); } catch { throw new UpdateError('Listed screenshot file is missing.'); }
      check(file.startsWith(root + sep), 'Screenshot resolves outside the media folder.');
      try { bytes = await readFile(file); } catch { throw new UpdateError('Listed screenshot file cannot be read.'); }
      check(entry.sha256 === digest(bytes) && entry.hasAlpha === false && entry.width === width && entry.height === height, 'Screenshot content integrity mismatch.');
      let size;
      try { size = jpegSize(bytes); } catch { throw new UpdateError('Screenshot is not a readable JPEG.'); }
      check(size[0] === width && size[1] === height, 'Unexpected screenshot dimensions.');
      media.push({family, display, name: entry.file, bytes, md5: digest(bytes, 'md5')});
    }
  }
  return media;
}

export function safeUpdateUrl(path) {
  check(typeof path === 'string' && !/(?:^|\/)(?:\.|%2e){1,2}(?:\/|$|[?#])/i.test(path), 'Invalid Apple API URL.');
  let url;
  try { url = new URL(path, ORIGIN); } catch { throw new UpdateError('Invalid Apple API URL.'); }
  check(url.origin === ORIGIN && !url.username && !url.password && !url.hash
    && /^\/v[12]\/[A-Za-z0-9/._~=-]+$/.test(url.pathname), 'Unexpected Apple API destination.');
  return url;
}

function signer(env) {
  check(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID ?? '')
    && /^[0-9a-f-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID ?? ''), 'Missing or invalid App Store Connect identifiers.');
  let key;
  try { key = createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64 ?? '', 'base64')); }
  catch { throw new UpdateError('Invalid App Store Connect private key.'); }
  check(key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails?.namedCurve === 'prime256v1', 'An ES256 key is required.');
  return () => {
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url'), now = Math.floor(Date.now() / 1000);
    const data = encode({alg: 'ES256', typ: 'JWT', kid: env.APP_STORE_CONNECT_KEY_ID}) + '.'
      + encode({iss: env.APP_STORE_CONNECT_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'});
    return data + '.' + sign('sha256', Buffer.from(data), {key, dsaEncoding: 'ieee-p1363'}).toString('base64url');
  };
}

/** The complete list of writes this helper can make. `bound` holds the IDs that
 * were read through the target app, version and localization; a write to any
 * other ID, attribute or endpoint is refused before it is sent. */
export function permittedUpdateWrite({mode, target, bound}, method, pathname, body) {
  const data = body?.data, keys = Object.keys(data?.attributes ?? {}), links = data?.relationships ?? {};
  const at = (prefix, id, suffix = '') => Boolean(id) && pathname === prefix + id + suffix;
  const shot = /^\/v1\/appScreenshots\/([^/]+)$/.exec(pathname)?.[1];
  if (mode === 'prepare') {
    if (method === 'POST' && pathname === '/v1/appStoreVersions') return data?.attributes?.platform === 'IOS'
      && data.attributes.versionString === target && links.app?.data?.id === APP_ID && Object.keys(links).length === 1;
    if (method === 'PATCH' && at('/v1/appStoreVersions/', bound.version)) return keys.join() === 'releaseType' && !data?.relationships;
    // Attaches the verified target build only; a null body would detach.
    if (method === 'PATCH' && at('/v1/appStoreVersions/', bound.version, '/relationships/build')) return data?.type === 'builds' && Boolean(bound.build) && data.id === bound.build;
    if (method === 'PATCH' && at('/v1/appStoreVersionLocalizations/', bound.localization)) return keys.join() === 'whatsNew';
    if (method === 'POST' && pathname === '/v1/appStoreReviewDetails') return Boolean(bound.version) && links.appStoreVersion?.data?.id === bound.version;
    if (method === 'PATCH' && at('/v1/appStoreReviewDetails/', bound.review)) return keys.join() === 'notes';
    if (method === 'POST' && pathname === '/v1/appScreenshotSets') return Boolean(bound.localization) && links.appStoreVersionLocalization?.data?.id === bound.localization;
    if (method === 'POST' && pathname === '/v1/appScreenshots') return bound.sets.has(links.appScreenshotSet?.data?.id);
    if (method === 'PATCH' && shot) return bound.shots.has(shot) && keys.sort().join() === 'sourceFileChecksum,uploaded';
    if (method === 'DELETE' && shot) return bound.deletable.delete(shot);
  }
  if (mode === 'submit') {
    if (method === 'POST' && pathname === '/v1/reviewSubmissions') return data?.attributes?.platform === 'IOS' && links.app?.data?.id === APP_ID && Object.keys(links).length === 1;
    if (method === 'POST' && pathname === '/v1/reviewSubmissionItems') return Boolean(bound.submission) && Boolean(bound.version)
      && links.reviewSubmission?.data?.id === bound.submission && links.appStoreVersion?.data?.id === bound.version && Object.keys(links).length === 2;
    if (method === 'PATCH' && at('/v1/reviewSubmissions/', bound.submission)) return JSON.stringify(data?.attributes) === '{"submitted":true}' && !data.relationships;
  }
  return false;
}

// Summaries carry these public facts only: never contact values, notes text,
// upload URLs or credentials.
const versionFacts = v => v && {id: v.id, versionString: v.attributes?.versionString ?? null, state: versionState(v),
  releaseType: v.attributes?.releaseType ?? null, createdDate: v.attributes?.createdDate ?? null};
const buildFacts = b => b && {id: b.id, buildNumber: b.attributes?.version ?? null, processingState: b.attributes?.processingState ?? null,
  expired: b.attributes?.expired ?? null, uploadedDate: b.attributes?.uploadedDate ?? null,
  usesNonExemptEncryption: b.attributes?.usesNonExemptEncryption ?? null};
const delivery = image => image.attributes?.assetDeliveryState?.state ?? null;
const setFacts = entry => ({locale: entry.locale, display: entry.set.attributes?.screenshotDisplayType ?? null, setId: entry.set.id,
  count: entry.images.length, complete: entry.images.filter(image => delivery(image) === 'COMPLETE').length});
const sameImage = (image, file) => image.attributes?.fileName === file.name && image.attributes?.fileSize === file.bytes.length
  && image.attributes?.sourceFileChecksum === file.md5 && delivery(image) === 'COMPLETE';
const koreanSets = (sets, display) => (sets ?? []).filter(entry => entry.locale === LOCALE && entry.set.attributes?.screenshotDisplayType === display);

export async function updateAppStore(env, fetchImpl = fetch, options = {}) {
  const config = updateConfig(env), {mode, version: target, build: targetBuildNumber, release} = config;
  const contact = parseReviewContact(env.APP_STORE_REVIEW_CONTACT_JSON);
  const token = signer(env);
  const sleep = options.sleep ?? (ms => new Promise(done => setTimeout(done, ms)));
  const writes = [], privateDiagnostics = [];
  const summary = {tool: 'app_store_update', appId: APP_ID, bundleId: BUNDLE, mode, checkedAt: new Date().toISOString(),
    target: {version: target, build: targetBuildNumber, releaseTypeInput: release}, writes, blockers: [],
    submitted: false, submissionId: null, submissionState: null, versionState: null, appliedReleaseType: null};
  // The screenshot manifest given to this run, once it has been read and verified.
  let expectedMedia = null;
  const secrets = [...Object.entries(env).filter(([name]) => /KEY|SECRET|TOKEN|PASSWORD|ISSUER|CONTACT/i.test(name)).map(([, value]) => value),
    ...Object.values(contact ?? {})];
  // IDs a write may address. Each is set only after the resource was read
  // through the target app, target version or target localization.
  const bound = {version: null, build: null, localization: null, review: null, submission: null,
    sets: new Set(), shots: new Set(), deletable: new Set()};

  async function request(path, method = 'GET', body, optional = false) {
    const url = safeUpdateUrl(path);
    if (method !== 'GET') check(!url.search && permittedUpdateWrite({mode, target, bound}, method, url.pathname, body), 'Write is outside the permitted update operations.');
    let response;
    try { response = await fetchImpl(url, {method, headers: {Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined, redirect: 'error', signal: AbortSignal.timeout(30_000)}); }
    catch {
      // A write that got no answer may still have been applied; record it as unknown.
      if (method !== 'GET') (summary.uncertainWrites ??= []).push({method, path: url.pathname});
      const error = new UpdateError('Apple API request failed or timed out: ' + method + ' ' + url.pathname + '.');
      error.transport = true;
      throw error;
    }
    if (optional && response.status === 404) return {data: null};
    if (!response.ok) {
      let document = null;
      try { document = await response.json(); } catch { /* No raw error text is emitted. */ }
      const diagnostic = safeSubmissionDiagnostic(response.status, document);
      const error = new UpdateError('Apple API HTTP ' + response.status + ' for ' + method + ' ' + url.pathname + '; codes=' + diagnostic.codes.join(',') + '.');
      error.status = response.status; error.diagnostic = {method, path: url.pathname, ...diagnostic};
      // Review detail requests carry contact values; their provider text is never kept.
      if (!/appStoreReviewDetail/.test(url.pathname)) privateDiagnostics.push({method, path: url.pathname,
        ...privateSubmissionDiagnostic(response.status, document, secrets)});
      throw error;
    }
    if (method !== 'GET') writes.push({method, path: url.pathname});
    if (response.status === 204) return {data: null};
    try { return await response.json(); } catch { throw new UpdateError('Unreadable Apple API response.'); }
  }
  async function get(path, type, optional = false) {
    const data = (await request(path, 'GET', undefined, optional)).data;
    return data == null && optional ? null : item(data, type);
  }
  async function list(path, type) {
    const pathname = safeUpdateUrl(path).pathname, seen = new Set(), ids = new Set(), result = [];
    while (path) {
      const url = safeUpdateUrl(path);
      check(url.pathname === pathname && !seen.has(url.href) && seen.size < 20, 'Unexpected pagination.');
      seen.add(url.href);
      const page = await request(url.href);
      check(Array.isArray(page.data), 'Invalid resource list.');
      for (const resource of page.data) {
        item(resource, type); check(!ids.has(resource.id), 'Duplicate resource ID.');
        ids.add(resource.id); result.push(resource);
      }
      path = page.links?.next;
    }
    return result;
  }
  async function persist() {
    if (summary.blockers.some(blocker => /^(?:TARGET_VERSION_STATE_(?:NOT_EDITABLE|UNEXPECTED):|SCREENSHOTS_NOT_EDITABLE_)/.test(blocker))) summary.guidance = STATE_GUIDANCE;
    for (const [path, value] of [[env.APP_STORE_UPDATE_SUMMARY_PATH, summary],
      [env.APP_STORE_UPDATE_DIAGNOSTIC_PATH, {checkedAt: summary.checkedAt, diagnostics: privateDiagnostics.slice(-10)}]]) {
      if (!path) continue;
      const destination = resolve(path);
      await mkdir(dirname(destination), {recursive: true, mode: 0o700});
      await writeFile(destination, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
      await chmod(destination, 0o600);
    }
  }

  async function iosVersions() {
    const versions = (await list('/v1/apps/' + APP_ID + '/appStoreVersions?include=app,build&limit=200', 'appStoreVersions'))
      .filter(v => v.attributes?.platform === 'IOS');
    for (const v of versions) relation(v, 'app', 'apps', APP_ID);
    return versions;
  }
  async function screenshotSets(locales) {
    const result = [];
    for (const locale of locales) {
      const sets = await list('/v1/appStoreVersionLocalizations/' + locale.id + '/appScreenshotSets?limit=200', 'appScreenshotSets');
      for (const set of sets) result.push({locale: locale.attributes?.locale ?? null, localeId: locale.id, set,
        images: await list('/v1/appScreenshotSets/' + set.id + '/appScreenshots?limit=200', 'appScreenshots')});
    }
    return result;
  }
  const localizationsOf = v => list('/v1/appStoreVersions/' + v.id + '/appStoreVersionLocalizations?limit=200', 'appStoreVersionLocalizations');
  const reviewDetailOf = v => get('/v1/appStoreVersions/' + v.id + '/appStoreReviewDetail', 'appStoreReviewDetails', true);
  const attachedBuildOf = v => get('/v1/appStoreVersions/' + v.id + '/build', 'builds', true);

  /** One complete GET-only reading of everything this helper depends on. */
  async function snapshot() {
    const app = await get('/v1/apps/' + APP_ID, 'apps');
    check(app.id === APP_ID && app.attributes?.bundleId === BUNDLE, 'Unexpected app identity.');
    const versions = await iosVersions();
    const live = versions.filter(v => LIVE_STATES.includes(versionState(v)));
    const targets = versions.filter(v => comparable(v.attributes?.versionString) && compareVersions(v.attributes.versionString, target) === 0);
    check(targets.length <= 1, 'More than one App Store version matches the target version.');
    const targetVersion = targets[0] ?? null;
    bound.version = targetVersion?.id ?? null;

    const builds = await list('/v1/builds?filter[app]=' + APP_ID + '&filter[version]=' + targetBuildNumber
      + '&filter[processingState]=PROCESSING,FAILED,INVALID,VALID&limit=200', 'builds');
    check(builds.length <= 10 && builds.every(b => b.attributes?.version === targetBuildNumber), 'Unexpected build list for the target build number.');
    const candidates = [];
    for (const build of builds) candidates.push({build,
      prerelease: await get('/v1/builds/' + build.id + '/preReleaseVersion', 'preReleaseVersions', true)});
    const matching = candidates.filter(c => c.prerelease?.attributes?.platform === 'IOS'
      && comparable(c.prerelease.attributes.version) && compareVersions(c.prerelease.attributes.version, target) === 0);
    check(matching.length <= 1, 'More than one build matches the target version and build number.');
    const targetBuild = matching[0] ?? null;
    if (targetBuild) {
      const buildApp = await get('/v1/builds/' + targetBuild.build.id + '/app', 'apps');
      check(buildApp.id === APP_ID && buildApp.attributes?.bundleId === BUNDLE, 'Build belongs to another app.');
    }
    bound.build = targetBuild?.build.id ?? null;

    let attached = null, locales = [], review = null, sets = [], liveSets = null;
    if (targetVersion) {
      attached = await attachedBuildOf(targetVersion);
      locales = await localizationsOf(targetVersion);
      review = await reviewDetailOf(targetVersion);
      sets = await screenshotSets(locales);
    }
    // What a new version starts from, and what its screenshots must still equal
    // when this run was given no manifest. Read-only.
    if (live.length === 1) liveSets = await screenshotSets(await localizationsOf(live[0]));
    const submissions = [];
    const allSubmissions = await list('/v1/apps/' + APP_ID + '/reviewSubmissions?filter[platform]=IOS&include=app,appStoreVersionForReview&limit=200', 'reviewSubmissions');
    for (const entry of allSubmissions) relation(entry, 'app', 'apps', APP_ID);
    const open = allSubmissions.filter(entry => entry.attributes?.state !== 'COMPLETE');
    check(open.length <= 5, 'Too many open review submissions; inspect them in App Store Connect.');
    for (const entry of open) {
      const items = await list('/v1/reviewSubmissions/' + entry.id + '/items?include=appStoreVersion&limit=200', 'reviewSubmissionItems');
      submissions.push({id: entry.id, state: entry.attributes?.state ?? null, platform: entry.attributes?.platform ?? null,
        submittedDate: entry.attributes?.submittedDate ?? null,
        items: items.map(entryItem => ({id: entryItem.id, state: entryItem.attributes?.state ?? null,
          versionId: entryItem.relationships?.appStoreVersion?.data?.id ?? null,
          otherContent: Object.entries(entryItem.relationships ?? {}).some(([key, value]) => key !== 'appStoreVersion' && value?.data != null)}))});
    }
    return {app, versions, live, targetVersion, candidates, targetBuild, attached, locales, review, sets, liveSets,
      submissions, completedSubmissions: allSubmissions.length - open.length};
  }

  // A submission this helper may use: unsubmitted, iOS, and holding nothing
  // except (at most) the target version.
  const onlyTarget = (entry, s) => entry.items.every(i => !i.otherContent && s.targetVersion && i.versionId === s.targetVersion.id);
  const reusable = (entry, s) => entry.state === 'READY_FOR_REVIEW' && entry.platform === 'IOS' && entry.items.length <= 1 && onlyTarget(entry, s);
  const carriesTarget = (entry, s) => IN_REVIEW_STATES.includes(entry.state) && entry.items.length === 1 && onlyTarget(entry, s);

  /** Conditions that make any write wrong. Listed in inspect, fatal otherwise. */
  function refusals(s) {
    const found = [];
    if (s.live.length !== 1) found.push(s.live.length ? 'MULTIPLE_LIVE_VERSIONS' : 'LIVE_VERSION_NOT_FOUND');
    else if (!comparable(s.live[0].attributes?.versionString) || compareVersions(target, s.live[0].attributes.versionString) <= 0) {
      found.push('TARGET_VERSION_NOT_HIGHER_THAN_LIVE:' + (s.live[0].attributes?.versionString ?? 'unknown'));
    }
    for (const v of s.versions) {
      if (v === s.targetVersion || s.live.includes(v) || RETIRED_STATES.includes(versionState(v))) continue;
      found.push('OTHER_VERSION_IN_PROGRESS:' + (v.attributes?.versionString ?? 'unknown') + ':' + versionState(v));
    }
    if (!s.targetBuild && s.candidates.length) found.push('TARGET_BUILD_VERSION_MISMATCH');
    if (s.targetBuild) {
      const attributes = s.targetBuild.build.attributes ?? {};
      if (attributes.expired !== false) found.push('TARGET_BUILD_EXPIRED');
      if (!['VALID', 'PROCESSING'].includes(attributes.processingState)) found.push('TARGET_BUILD_NOT_USABLE:' + attributes.processingState);
    }
    return found;
  }
  /** The store must hold exactly the manifest given to this run or, without one,
   * the same images in the same order as the live version. A set left half
   * replaced by an interrupted run equals neither, so it cannot be submitted. */
  function screenshotsAsExpected(s, family, display, images) {
    if (expectedMedia) {
      const files = expectedMedia.filter(file => file.family === family);
      return images.length === files.length && images.every((image, index) => sameImage(image, files[index]));
    }
    // Compared by content checksum, which is what identifies an image; a checksum Apple does not report proves nothing.
    const reference = koreanSets(s.liveSets, display);
    return reference.length === 1 && reference[0].images.length === images.length && images.every((image, index) =>
      filled(image.attributes?.sourceFileChecksum) && image.attributes.sourceFileChecksum === reference[0].images[index].attributes?.sourceFileChecksum);
  }
  /** The target version is already with App Review (possibly from an earlier
   * run): report what is there and write nothing. Returns false otherwise. */
  function reportInReview(s) {
    const version = s.targetVersion, owner = s.submissions.find(entry => carriesTarget(entry, s));
    if (!version || refusals(s).length || !(owner || IN_REVIEW_STATES.includes(versionState(version)))) return false;
    if (!s.attached || s.attached.id !== s.targetBuild?.build.id) {
      summary.blockers = ['VERSION_IN_REVIEW_WITH_DIFFERENT_BUILD:' + (s.attached?.attributes?.version ?? 'none')];
      return true;
    }
    Object.assign(summary, {submitted: true, alreadySubmitted: true, submissionId: owner?.id ?? null, submissionState: owner?.state ?? null});
    // It can no longer be changed here; a run that asked for another setting must not look clean.
    if (release !== 'KEEP' && version.attributes?.releaseType !== release) summary.blockers = ['RELEASE_TYPE_DIFFERS_FROM_INPUT:' + (version.attributes?.releaseType ?? 'unknown')];
    return true;
  }
  /** Everything still standing between the current state and a submission. */
  function readiness(s, draft) {
    const found = refusals(s), v = s.targetVersion;
    if (!draft) found.push('UPDATE_DRAFT_INVALID');
    if (config.mediaRoot && !expectedMedia) found.push('SCREENSHOT_MANIFEST_INVALID');
    if (!s.targetBuild) { if (!s.candidates.length) found.push('TARGET_BUILD_NOT_FOUND'); }
    else {
      if (s.targetBuild.build.attributes?.processingState === 'PROCESSING') found.push('TARGET_BUILD_PROCESSING');
      if (s.targetBuild.build.attributes?.usesNonExemptEncryption !== false) found.push('BUILD_ENCRYPTION_DECLARATION_NOT_CONFIRMED');
    }
    if (!v) found.push('TARGET_VERSION_NOT_CREATED');
    else {
      if (!['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW', ...IN_REVIEW_STATES].includes(versionState(v))) found.push('TARGET_VERSION_STATE_UNEXPECTED:' + versionState(v));
      if (!RELEASE_TYPES.includes(v.attributes?.releaseType)) found.push('RELEASE_TYPE_NOT_SET');
      // Only prepare changes the setting; inspect and submit stop when it is not the one asked for.
      else if (release !== 'KEEP' && v.attributes.releaseType !== release) found.push('RELEASE_TYPE_DIFFERS_FROM_INPUT:' + v.attributes.releaseType);
      if (!filled(v.attributes?.copyright)) found.push('COPYRIGHT_MISSING');
      if (!s.attached) found.push('BUILD_NOT_ATTACHED');
      else if (s.attached.id !== s.targetBuild?.build.id) found.push('ATTACHED_BUILD_IS_NOT_TARGET');
      const korean = s.locales.filter(l => l.attributes?.locale === LOCALE);
      if (korean.length !== 1) found.push('KOREAN_LOCALIZATION_MISSING');
      for (const l of s.locales) if (!filled(l.attributes?.whatsNew)) found.push('WHATS_NEW_MISSING:' + l.attributes?.locale);
      if (draft && korean.length === 1 && filled(korean[0].attributes?.whatsNew) && !sameText(korean[0].attributes.whatsNew, draft.whatsNew)) found.push('WHATS_NEW_DIFFERS_FROM_DRAFT');
      if (!s.review) found.push('REVIEW_DETAIL_MISSING');
      else {
        const a = s.review.attributes ?? {};
        if (!CONTACT_KEYS.every(key => filled(a[key]))) found.push('REVIEW_CONTACT_INCOMPLETE');
        if (!filled(a.notes)) found.push('REVIEW_NOTES_MISSING');
        else if (draft && !sameText(a.notes, draft.reviewNotes)) found.push('REVIEW_NOTES_DIFFER_FROM_DRAFT');
        if (a.demoAccountRequired !== false && !(filled(a.demoAccountName) && filled(a.demoAccountPassword))) found.push('REVIEW_DEMO_ACCOUNT_INCOMPLETE');
      }
      for (const [family, [display]] of Object.entries(FAMILIES)) {
        const matches = koreanSets(s.sets, display);
        if (matches.length !== 1 || matches[0].images.length < 1 || matches[0].images.length > SET_LIMIT
          || !matches[0].images.every(image => delivery(image) === 'COMPLETE')) found.push('SCREENSHOTS_NOT_READY:' + display);
        else if ((expectedMedia || !config.mediaRoot) && !screenshotsAsExpected(s, family, display, matches[0].images)) found.push('SCREENSHOTS_DIFFER_FROM_EXPECTED:' + display);
      }
    }
    if (s.submissions.length > 1) found.push('MULTIPLE_OPEN_SUBMISSIONS');
    for (const entry of s.submissions) if (!reusable(entry, s) && !carriesTarget(entry, s)) found.push('OTHER_SUBMISSION_IN_FLIGHT:' + entry.id + ':' + entry.state);
    return found;
  }
  function describe(s, draft) {
    const a = s.review?.attributes ?? {};
    Object.assign(summary, {
      app: {name: s.app.attributes?.name ?? null, bundleId: s.app.attributes?.bundleId ?? null, primaryLocale: s.app.attributes?.primaryLocale ?? null},
      versions: s.versions.map(versionFacts),
      liveVersion: s.live.length === 1 ? versionFacts(s.live[0]) : null,
      targetVersion: {exists: Boolean(s.targetVersion), ...(versionFacts(s.targetVersion) ?? {}),
        copyrightPresent: filled(s.targetVersion?.attributes?.copyright), attachedBuild: buildFacts(s.attached)},
      targetBuild: {found: Boolean(s.targetBuild), buildsWithThisNumber: s.candidates.length, ...(buildFacts(s.targetBuild?.build) ?? {}),
        preReleaseVersion: s.targetBuild?.prerelease.attributes?.version ?? null},
      localizations: s.locales.map(l => ({id: l.id, locale: l.attributes?.locale ?? null, whatsNewPresent: filled(l.attributes?.whatsNew),
        whatsNewMatchesDraft: draft && l.attributes?.locale === LOCALE ? sameText(l.attributes?.whatsNew, draft.whatsNew) : null})),
      reviewDetail: {present: Boolean(s.review), contactComplete: CONTACT_KEYS.every(key => filled(a[key])),
        notesPresent: filled(a.notes), notesMatchDraft: draft ? sameText(a.notes, draft.reviewNotes) : null,
        demoAccountRequired: s.review ? a.demoAccountRequired ?? null : null},
      screenshots: {of: s.targetVersion ? 'target' : s.liveSets ? 'live' : null, expected: expectedMedia ? 'manifest' : config.mediaRoot ? null : 'live',
        sets: (s.targetVersion ? s.sets : s.liveSets ?? []).map(entry => {
          const facts = setFacts(entry), family = Object.keys(FAMILIES).find(name => FAMILIES[name][0] === facts.display);
          const checked = s.targetVersion && entry.locale === LOCALE && family && (expectedMedia || !config.mediaRoot);
          return checked ? {...facts, matchesExpected: screenshotsAsExpected(s, family, facts.display, entry.images)} : facts;
        })},
      reviewSubmissions: {open: s.submissions, completed: s.completedSubmissions},
      versionState: versionState(s.targetVersion),
      // What Apple holds now, which is what applies on approval whatever this run asked for.
      appliedReleaseType: s.targetVersion?.attributes?.releaseType ?? null,
    });
  }

  async function prepare(s, draft) {
    const fatal = refusals(s), state = versionState(s.targetVersion);
    // A submit run that stopped before its last step leaves the version alone in
    // an unsubmitted review submission; Apple still lets it be edited there.
    const draftItem = state === 'READY_FOR_REVIEW' && s.submissions.length === 1 && s.submissions[0].items.length === 1 && reusable(s.submissions[0], s);
    const locked = s.targetVersion && state !== 'PREPARE_FOR_SUBMISSION' && !draftItem;
    if (locked) fatal.push('TARGET_VERSION_STATE_NOT_EDITABLE:' + state);
    if (fatal.length) { summary.blockers = fatal; throw new UpdateError('Prepare refused: ' + fatal.join('; ') + '.' + (locked ? ' ' + STATE_GUIDANCE : '')); }
    // Local inputs (draft and screenshot manifest) were validated before the first request.
    const media = expectedMedia;
    const notes = [];

    let version = s.targetVersion;
    if (!version) {
      const live = s.live[0], releaseType = release === 'KEEP' ? live.attributes?.releaseType : release;
      check(RELEASE_TYPES.includes(releaseType), 'The live release setting cannot be kept; choose MANUAL or AFTER_APPROVAL.');
      const attributes = {platform: 'IOS', versionString: target, releaseType};
      if (filled(live.attributes?.copyright)) attributes.copyright = live.attributes.copyright;
      const created = item((await request('/v1/appStoreVersions', 'POST', {data: {type: 'appStoreVersions', attributes,
        relationships: {app: relationTo('apps', APP_ID)}}})).data, 'appStoreVersions');
      // Use the new ID only after it is seen again through the app itself.
      version = (await iosVersions()).find(v => v.id === created.id);
      check(version && version.attributes?.versionString === target && versionState(version) === 'PREPARE_FOR_SUBMISSION'
        && version.attributes.releaseType === releaseType, 'Created version was not confirmed through the app.');
      summary.createdVersion = true;
    } else if (release !== 'KEEP' && version.attributes?.releaseType !== release) {
      await request('/v1/appStoreVersions/' + version.id, 'PATCH', {data: {type: 'appStoreVersions', id: version.id, attributes: {releaseType: release}}});
      const verified = await get('/v1/appStoreVersions/' + version.id + '?include=app', 'appStoreVersions');
      relation(verified, 'app', 'apps', APP_ID);
      check(verified.attributes?.releaseType === release, 'Release setting readback mismatch.');
    }
    bound.version = version.id;

    const korean = (await localizationsOf(version)).filter(l => l.attributes?.locale === LOCALE);
    check(korean.length === 1, 'Korean localization of the new version is missing; nothing is created implicitly.');
    bound.localization = korean[0].id;
    if (!sameText(korean[0].attributes?.whatsNew, draft.whatsNew)) {
      await request('/v1/appStoreVersionLocalizations/' + korean[0].id, 'PATCH', {data: {type: 'appStoreVersionLocalizations', id: korean[0].id,
        attributes: {whatsNew: draft.whatsNew}}});
      const verified = await get('/v1/appStoreVersionLocalizations/' + korean[0].id, 'appStoreVersionLocalizations');
      check(verified.attributes?.locale === LOCALE && sameText(verified.attributes.whatsNew, draft.whatsNew), 'Release text readback mismatch.');
    }

    let review = await reviewDetailOf(version), createdReview = false;
    if (review) {
      relation(await get('/v1/appStoreReviewDetails/' + review.id + '?include=appStoreVersion', 'appStoreReviewDetails'), 'appStoreVersion', 'appStoreVersions', version.id);
      bound.review = review.id;
      // Notes only: existing contact fields and demo account settings stay as they are.
      if (!sameText(review.attributes?.notes, draft.reviewNotes)) await request('/v1/appStoreReviewDetails/' + review.id, 'PATCH',
        {data: {type: 'appStoreReviewDetails', id: review.id, attributes: {notes: draft.reviewNotes}}});
    } else if (contact) {
      review = item((await request('/v1/appStoreReviewDetails', 'POST', {data: {type: 'appStoreReviewDetails',
        attributes: {...contact, notes: draft.reviewNotes, demoAccountRequired: false},
        relationships: {appStoreVersion: relationTo('appStoreVersions', version.id)}}})).data, 'appStoreReviewDetails');
      createdReview = true;
    } else notes.push('REVIEW_DETAIL_MISSING_AND_NO_CONTACT_SECRET');
    if (review) {
      const verified = await reviewDetailOf(version);
      check(verified?.id === review.id && sameText(verified.attributes?.notes, draft.reviewNotes)
        && (!createdReview || (CONTACT_KEYS.every(key => verified.attributes[key] === contact[key]) && verified.attributes.demoAccountRequired === false)),
      'Review notes or contact readback mismatch.');
      if (createdReview) summary.createdReviewDetail = true;
    }

    const wanted = s.targetBuild?.build;
    if (wanted?.attributes?.processingState === 'VALID') {
      // Recheck immediately before attaching.
      const fresh = await get('/v1/builds/' + wanted.id, 'builds');
      check(fresh.attributes?.version === targetBuildNumber && fresh.attributes.processingState === 'VALID' && fresh.attributes.expired === false,
        'Target build is no longer valid and unexpired.');
      const current = await attachedBuildOf(version);
      if (current?.id !== wanted.id) {
        await request('/v1/appStoreVersions/' + version.id + '/relationships/build', 'PATCH', relationTo('builds', wanted.id));
        let observed;
        for (let attempt = 0; attempt < 3; attempt++) {
          observed = await attachedBuildOf(version);
          if (observed?.id === wanted.id) break;
          if (attempt < 2) await sleep(1000);
        }
        check(observed?.id === wanted.id, 'Build attachment readback mismatch.');
        if (current) summary.replacedBuild = {id: current.id, buildNumber: current.attributes?.version ?? null};
      }
    }

    // Apple does not let images be changed while the version sits in a review
    // submission, so nothing is attempted there; a difference is only reported.
    if (media && !draftItem) await replaceScreenshots(korean[0], media);

    const after = await snapshot();
    describe(after, draft);
    const remaining = readiness(after, draft);
    if (draftItem && remaining.some(blocker => blocker.startsWith('SCREENSHOTS_'))) notes.push('SCREENSHOTS_NOT_EDITABLE_IN_A_REVIEW_SUBMISSION');
    summary.blockers = [...new Set([...remaining, ...notes, ...summary.blockers])];
    summary.prepared = summary.blockers.length === 0;
  }

  /** Makes the Korean iPhone and iPad sets equal to the manifest, in order.
   * Matching complete images at the front are kept, and so are files a stopped
   * earlier run already added at the end. Everything new is uploaded and
   * confirmed complete first; only then are the images it replaces removed, so
   * a run that stops part-way never leaves a set with fewer usable images than
   * before. Other display types and locales are untouched. */
  async function replaceScreenshots(locale, media) {
    const plan = [];
    // Read every target set before changing any of them.
    const sets = await list('/v1/appStoreVersionLocalizations/' + locale.id + '/appScreenshotSets?limit=200', 'appScreenshotSets');
    for (const [family, [display]] of Object.entries(FAMILIES)) {
      const found = sets.filter(set => set.attributes?.screenshotDisplayType === display);
      check(found.length <= 1, 'Duplicate screenshot sets require manual review.');
      const images = found[0] ? await list('/v1/appScreenshotSets/' + found[0].id + '/appScreenshots?limit=200', 'appScreenshots') : [];
      const files = media.filter(file => file.family === family);
      let keep = 0;
      while (keep < images.length && keep < files.length && sameImage(images[keep], files[keep])) keep++;
      let tail = Math.min(images.length, files.length) - keep;
      while (tail > 0 && !images.slice(-tail).every((image, index) => sameImage(image, files[keep + index]))) tail--;
      const remove = images.slice(keep, images.length - tail), upload = files.slice(keep + tail);
      // Old and new images share the set until the new ones are confirmed.
      check(images.length + upload.length <= SET_LIMIT, 'Screenshot set ' + display + ' cannot hold its current and new files together (limit '
        + SET_LIMIT + '); nothing was changed. Remove unused images in App Store Connect or use fewer files.');
      plan.push({family, display, set: found[0] ?? null, files, kept: keep + tail, remove, upload});
    }
    summary.screenshotReplacement = [];
    const queue = [];
    for (const entry of plan) {
      const report = {family: entry.family, display: entry.display, kept: entry.kept, removed: 0, uploaded: 0, verified: false};
      summary.screenshotReplacement.push(report);
      let set = entry.set;
      if (!set) set = item((await request('/v1/appScreenshotSets', 'POST', {data: {type: 'appScreenshotSets', attributes: {screenshotDisplayType: entry.display},
        relationships: {appStoreVersionLocalization: relationTo('appStoreVersionLocalizations', locale.id)}}})).data, 'appScreenshotSets');
      relation(await get('/v1/appScreenshotSets/' + set.id + '?include=appStoreVersionLocalization', 'appScreenshotSets'),
        'appStoreVersionLocalization', 'appStoreVersionLocalizations', locale.id);
      bound.sets.add(set.id);
      entry.set = set;
      for (const file of entry.upload) {
        const reserved = item((await request('/v1/appScreenshots', 'POST', {data: {type: 'appScreenshots', attributes: {fileName: file.name, fileSize: file.bytes.length},
          relationships: {appScreenshotSet: relationTo('appScreenshotSets', set.id)}}})).data, 'appScreenshots');
        bound.shots.add(reserved.id);
        // Apple returns the signed upload operations in the reservation response.
        await uploadParts(reserved.attributes?.uploadOperations, file.bytes, fetchImpl);
        await request('/v1/appScreenshots/' + reserved.id, 'PATCH', {data: {type: 'appScreenshots', id: reserved.id,
          attributes: {uploaded: true, sourceFileChecksum: file.md5}}});
        queue.push({id: reserved.id, file});
        report.uploaded++;
        await persist();
      }
    }
    for (const {id, file} of queue) {
      let done = false;
      for (let attempt = 0; attempt < 60 && !done; attempt++) {
        const observed = await get('/v1/appScreenshots/' + id, 'appScreenshots');
        if (delivery(observed) === 'FAILED') break;
        if (delivery(observed) === 'COMPLETE') {
          check(observed.attributes?.sourceFileChecksum === file.md5 && observed.attributes?.fileSize === file.bytes.length, 'Uploaded screenshot integrity readback failed.');
          done = true;
        } else await sleep(POLL_MS);
      }
      if (!done) summary.blockers.push('SCREENSHOT_PROCESSING_INCOMPLETE:' + id);
    }
    // Nothing is removed unless every new image of every set is confirmed.
    const confirmed = !summary.blockers.some(blocker => blocker.startsWith('SCREENSHOT_PROCESSING_INCOMPLETE:'));
    for (const entry of confirmed ? plan : []) {
      const report = summary.screenshotReplacement.find(r => r.family === entry.family);
      for (const image of entry.remove) {
        relation(await get('/v1/appScreenshots/' + image.id + '?include=appScreenshotSet', 'appScreenshots'), 'appScreenshotSet', 'appScreenshotSets', entry.set.id);
        bound.deletable.add(image.id);
        await request('/v1/appScreenshots/' + image.id, 'DELETE');
        report.removed++;
        await persist();
      }
    }
    for (const entry of plan) {
      const images = await list('/v1/appScreenshotSets/' + entry.set.id + '/appScreenshots?limit=200', 'appScreenshots');
      const report = summary.screenshotReplacement.find(r => r.family === entry.family);
      report.verified = images.length === entry.files.length && images.every((image, index) => sameImage(image, entry.files[index]));
      if (!report.verified) summary.blockers.push('SCREENSHOT_SET_DIFFERS_FROM_MANIFEST:' + entry.display);
    }
  }

  async function submit(s, draft) {
    const version = s.targetVersion;
    if (reportInReview(s)) return;
    summary.blockers = readiness(s, draft);
    if (summary.blockers.length) return;
    check(['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'].includes(versionState(version)), 'Version is not in a submittable state.');
    let submission = s.submissions.find(entry => reusable(entry, s)), items = submission?.items ?? [];
    if (!submission) {
      const created = item((await request('/v1/reviewSubmissions', 'POST', {data: {type: 'reviewSubmissions', attributes: {platform: 'IOS'},
        relationships: {app: relationTo('apps', APP_ID)}}})).data, 'reviewSubmissions');
      // Use the new ID only after it is seen again through the app itself.
      const reread = (await list('/v1/apps/' + APP_ID + '/reviewSubmissions?filter[platform]=IOS&include=app&limit=200', 'reviewSubmissions'))
        .find(entry => entry.id === created.id);
      check(reread?.attributes?.state === 'READY_FOR_REVIEW', 'Created review submission was not confirmed through the app.');
      relation(reread, 'app', 'apps', APP_ID);
      submission = {id: reread.id};
      summary.createdSubmission = true;
    } else summary.reusedSubmission = true;
    bound.submission = submission.id;
    summary.submissionId = submission.id;
    const readItems = () => list('/v1/reviewSubmissions/' + submission.id + '/items?include=appStoreVersion&limit=200', 'reviewSubmissionItems');
    if (items.length === 0) {
      await request('/v1/reviewSubmissionItems', 'POST', {data: {type: 'reviewSubmissionItems', relationships: {
        reviewSubmission: relationTo('reviewSubmissions', submission.id), appStoreVersion: relationTo('appStoreVersions', version.id)}}});
      items = await readItems();
      check(items.length === 1 && items[0].relationships?.appStoreVersion?.data?.id === version.id, 'Review version association was not confirmed.');
    }
    try {
      await request('/v1/reviewSubmissions/' + submission.id, 'PATCH', {data: {type: 'reviewSubmissions', id: submission.id, attributes: {submitted: true}}});
      summary.submitRequestAccepted = true;
    } catch (error) {
      // No answer is not a refusal: Apple may have taken the request. The state
      // read below decides what is reported; a refusal (HTTP error) still stops here.
      if (!error.transport) throw error;
      summary.submitResponseLost = true;
    }
    for (let attempt = 0; attempt < 5; attempt++) {
      const observed = await get('/v1/reviewSubmissions/' + submission.id + '?include=app', 'reviewSubmissions');
      relation(observed, 'app', 'apps', APP_ID);
      const observedVersion = await get('/v1/appStoreVersions/' + version.id + '?include=app', 'appStoreVersions');
      summary.submissionState = observed.attributes?.state ?? null;
      summary.versionState = versionState(observedVersion);
      summary.submitted = IN_REVIEW_STATES.includes(summary.submissionState) || IN_REVIEW_STATES.includes(summary.versionState);
      if (summary.submitted) break;
      if (attempt < 4) await sleep(POLL_MS);
    }
    if (!summary.submitted) summary.blockers.push(summary.submitResponseLost ? 'SUBMIT_REQUEST_OUTCOME_UNKNOWN' : 'SUBMISSION_ACCEPTANCE_NOT_YET_CONFIRMED');
  }

  try {
    // In inspect a broken draft is reported; before any write it is fatal.
    let draft = null;
    try { draft = await loadUpdateDraft(config.draftPath, target, targetBuildNumber); }
    catch (error) { if (mode !== 'inspect') throw error; summary.draftError = error instanceof UpdateError ? error.message : 'Update draft could not be read.'; }
    summary.draft = draft ? {ok: true, whatsNewLength: draft.whatsNew.length, reviewNotesLength: draft.reviewNotes.length} : {ok: false};
    // A screenshot folder is read in every mode: prepare replaces the store
    // screenshots with it, inspect and submit only compare the store against it.
    if (config.mediaRoot) {
      try { expectedMedia = await loadUpdateMedia(config.mediaRoot); }
      catch (error) { if (mode !== 'inspect') throw error; summary.mediaError = error instanceof UpdateError ? error.message : 'Screenshot folder could not be read.'; }
    }
    const s = await snapshot();
    describe(s, draft);
    // Test seam, unused by the command line: sends requests through the same gate as every other request.
    if (options.probe) await options.probe(request);
    if (mode === 'inspect' && !reportInReview(s)) summary.blockers = readiness(s, draft);
    if (mode === 'prepare') await prepare(s, draft);
    if (mode === 'submit') await submit(s, draft);
    await persist();
    return summary;
  } catch (error) {
    const safe = error instanceof UpdateError || error instanceof RegistrationError ? error : new UpdateError('Update helper failed; private details withheld.');
    const unknown = (summary.uncertainWrites ?? []).map(write => write.method + ' ' + write.path);
    if (unknown.length) safe.message += ' Outcome unknown for ' + unknown.join(', ') + '; run inspect before trying again.';
    summary.error = safe.message;
    if (safe.diagnostic) summary.diagnostic = safe.diagnostic;
    await persist();
    throw safe;
  }
}

/** inspect: 0 after any successful read. prepare and submit: 2 until the result is
 * confirmed, and for a submission that is with Apple but not as this run asked. */
export const exitCodeFor = summary => (summary.mode === 'prepare' && summary.prepared !== true)
  || (summary.mode === 'submit' && (summary.submitted !== true || summary.blockers?.length > 0)) ? 2 : 0;

// Node loads the main module by its real path (or, with --preserve-symlinks-main,
// by the path as typed), so both are accepted; comparing only the typed path
// made a symlinked checkout exit 0 without running anything.
function invokedDirectly() {
  if (!process.argv[1]) return false;
  const paths = [resolve(process.argv[1])];
  try { paths.push(realpathSync(process.argv[1])); } catch { /* The typed path is still compared. */ }
  return paths.some(path => import.meta.url === pathToFileURL(path).href);
}
if (invokedDirectly()) {
  updateAppStore(process.env).then(summary => {
    console.log(JSON.stringify(summary, null, 2));
    process.exitCode = exitCodeFor(summary);
  }).catch(error => {
    console.error(error instanceof UpdateError || error instanceof RegistrationError ? error.message : 'Update helper failed; details withheld.');
    process.exitCode = 1;
  });
}
