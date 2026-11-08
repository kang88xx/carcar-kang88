// Explicit final review submission for one known carcar release. No metadata,
// pricing, availability, authentication, or other app changes are supported.
import {createPrivateKey, sign} from 'node:crypto';
import {mkdir, writeFile, chmod} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {prepareDistribution} from './app_store_distribution.mjs';

export const SUBMISSION_APP = '6829616379';
export const SUBMISSION_VERSION = '9c55f98a-a3ae-4a3c-a5af-7397a4c37387';
export const SUBMISSION_BUILD = '2c30a8e4-1bfc-4cc1-b989-265f236225ae';
const origin = 'https://api.appstoreconnect.apple.com';
const bundle = 'com.kang88.carcar';
const activeReviewStates = ['WAITING_FOR_REVIEW', 'IN_REVIEW'];
const relation = (type, id) => ({data: {type, id}});
export class SubmissionError extends Error {}
const check = (ok, message) => { if (!ok) throw new SubmissionError(message); };
function resource(value, type, id) {
  check(value?.type === type && typeof value.id === 'string'
    && value.id !== '.' && value.id !== '..' && /^[A-Za-z0-9._~=-]{1,512}$/.test(value.id)
    && (!id || value.id === id), 'Unexpected submission resource identity.');
  return value;
}
const state = item => item.attributes?.appVersionState ?? item.attributes?.appStoreState ?? item.attributes?.state;
const linked = (item, key, type, id) => {
  const data = item.relationships?.[key]?.data;
  resource(data, type, id);
  return data.id;
};
const filled = value => typeof value === 'string' && value.trim().length > 0;
export function safeSubmissionUrl(path) {
  check(typeof path === 'string' && !/(?:^|\/)(?:\.|%2e){1,2}(?:\/|$|[?#])/i.test(path), 'Invalid submission URL dot segment.');
  let url; try { url = new URL(path, origin); } catch { throw new SubmissionError('Invalid submission URL.'); }
  check(url.origin === origin && !url.username && !url.password && !url.hash
    && /^\/v[12]\/[A-Za-z0-9._~=/\-]+$/.test(url.pathname), 'Unexpected submission API destination.');
  return url;
}

function submissionErrorTree(document) {
  const seen = new WeakSet();
  let visits = 0, count = 0;
  function walk(value, depth) {
    if (depth > 10 || visits++ >= 500 || count >= 100 || !value || typeof value !== 'object' || seen.has(value)) return [];
    seen.add(value);
    if (Array.isArray(value)) return value.slice(0, 100).flatMap(entry => walk(entry, depth + 1));
    if (['code', 'title', 'detail'].some(key => typeof value[key] === 'string')) {
      count++;
      return [{code: value.code, title: value.title, detail: value.detail, source: value.source,
        associatedErrors: [...walk(value.errors, depth + 1), ...walk(value.meta?.associatedErrors, depth + 1)]}];
    }
    // associatedErrors may be an array, an errors envelope, or an ID-keyed map.
    // Preserve only the error nodes, never arbitrary provider map keys/metadata.
    return Object.values(value).slice(0, 100).flatMap(entry => walk(entry, depth + 1));
  }
  return walk(document?.errors, 0);
}

export function safeSubmissionDiagnostic(status, document) {
  const errors = [];
  function flatten(nodes) { for (const node of nodes) { errors.push(node); flatten(node.associatedErrors); } }
  flatten(submissionErrorTree(document));
  const codes = [...new Set(errors.map(item => item?.code).filter(value => typeof value === 'string'
    && /^(ENTITY_ERROR|STATE_ERROR|PARAMETER_ERROR|FORBIDDEN_ERROR|NOT_FOUND|UNAUTHORIZED_ACCESS|CONFLICT|UNEXPECTED_ERROR)(?:\.[A-Z0-9_]+)*$/.test(value)
    && value.length <= 120))];
  const allowedPointerSegments = new Set(['data', 'attributes', 'relationships', 'included', 'id', 'type',
    'submitted', 'app', 'appStoreVersion', 'reviewSubmission', 'appStoreVersionLocalizations',
    'description', 'keywords', 'supportUrl', 'privacyPolicyUrl', 'copyright', 'contentRightsDeclaration',
    'build', 'appScreenshots', 'appScreenshotSets', 'ageRatingDeclaration', 'contactFirstName',
    'contactLastName', 'contactPhone', 'contactEmail', 'notes', 'demoAccountRequired', 'demoAccountName', 'demoAccountPassword']);
  const pointers = [...new Set(errors.map(item => item?.source?.pointer).filter(value => typeof value === 'string'
    && value.length <= 300 && value.startsWith('/') && value.slice(1).split('/').every(segment => allowedPointerSegments.has(segment) || /^\d{1,3}$/.test(segment))))];
  const details = errors.flatMap(item => [item?.code, item?.title, item?.detail]).filter(value => typeof value === 'string')
    .map(value => value.slice(0, 12000)).join(' ').toLowerCase();
  const categories = [];
  for (const [pattern, category] of [
    [/privacy|data[ _]?collection|data[ _]?usage/, 'APP_PRIVACY_REQUIRED'],
    [/content[ _]?rights|third.party content/, 'CONTENT_RIGHTS_REQUIRED'],
    [/contact|demo account|review information|review notes/, 'REVIEW_ACCESS_OR_CONTACT_REQUIRED'],
    [/screenshot|preview image/, 'SCREENSHOT_REQUIRED'], [/age[ _]?rating|rating declaration/, 'AGE_RATING_REQUIRED'],
    [/price|pricing/, 'PRICE_REQUIRED'], [/availability|territor/, 'AVAILABILITY_REQUIRED'],
    [/agreement|contract|terms/, 'LEGAL_AGREEMENT_REQUIRED'], [/build|binary|encryption/, 'BUILD_OR_ENCRYPTION_REQUIRED'],
    [/copyright|description|keyword|support[ _]?url/, 'METADATA_REQUIRED'],
    [/usesidfa|advertising[ _]?identifier|advertising[ _]?declaration/, 'ADVERTISING_DECLARATION_REQUIRED'],
  ]) if (pattern.test(details)) categories.push(category);
  return {status, codes, pointers, categories: categories.length ? categories : ['API_REJECTED']};
}

export function privateSubmissionDiagnostic(status, document, secretValues = []) {
  let remaining = 32768;
  function redact(value) {
    if (typeof value !== 'string' || remaining <= 0) return undefined;
    let text = value;
    for (const secret of secretValues) if (typeof secret === 'string' && secret.length >= 4) text = text.split(secret).join('[REDACTED]');
    // Bound regex work as well as serialized output on unusually large errors.
    text = text.slice(0, 8192);
    text = text.replace(/-----BEGIN[^\r\n]*PRIVATE KEY-----[\s\S]*?-----END[^\r\n]*PRIVATE KEY-----/g, '[PRIVATE KEY]')
      .replace(/\bBearer\s+[^\s"'<>]+/gi, 'Bearer [REDACTED]')
      .replace(/\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g, '[JWT]')
      .replace(/\b(?:password|secret|token|api[_ -]?key|authorization)\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi, '[CREDENTIAL]')
      .replace(/https?:\/\/[^\s"'<>]+/gi, '[URL]')
      .replace(/[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[EMAIL]')
      .replace(/\+?\d[\d(). -]{6,}\d/g, '[PHONE OR NUMBER]')
      .replace(/[A-Za-z0-9_+/=-]{40,}/g, '[OPAQUE VALUE]')
      .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '');
    text = text.slice(0, Math.min(2048, remaining)); remaining -= text.length;
    return text;
  }
  function clean(nodes) {
    return nodes.map(node => ({code: redact(node.code), title: redact(node.title), detail: redact(node.detail),
      source: {pointer: redact(node.source?.pointer), parameter: redact(node.source?.parameter)},
      associatedErrors: clean(node.associatedErrors)}));
  }
  return {status, ...safeSubmissionDiagnostic(status, document), errors: clean(submissionErrorTree(document))};
}

export async function submitAppStore(env, fetchImpl = fetch) {
  const submit = env.APP_STORE_SUBMIT === 'true';
  check(env.APP_STORE_SUBMIT == null || ['true', 'false'].includes(env.APP_STORE_SUBMIT), 'Invalid submission mode.');
  check(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID ?? '')
    && /^[0-9a-f-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID ?? ''), 'Missing or invalid App Store Connect credentials.');
  let key;
  try { key = createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64 ?? '', 'base64')); }
  catch { throw new SubmissionError('Invalid App Store Connect private key.'); }
  check(key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails?.namedCurve === 'prime256v1', 'Invalid App Store Connect key algorithm.');
  function token() {
    const now = Math.floor(Date.now() / 1000), encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const data = encode({alg: 'ES256', kid: env.APP_STORE_CONNECT_KEY_ID, typ: 'JWT'}) + '.'
      + encode({iss: env.APP_STORE_CONNECT_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'});
    return data + '.' + sign('sha256', Buffer.from(data), {key, dsaEncoding: 'ieee-p1363'}).toString('base64url');
  }
  const summary = {checkedAt: new Date().toISOString(), mode: submit ? 'submit' : 'inspect',
    appId: SUBMISSION_APP, versionId: SUBMISSION_VERSION, buildId: SUBMISSION_BUILD,
    versionState: null, submissionId: null, submissionState: null, submitted: false,
    localPrerequisitesReady: false, writes: [], blockers: []};
  const allowedReads = new Set(), allowedWrites = new Map();
  const privateDiagnostics = [];
  function allow(path) { const url = safeSubmissionUrl(path); allowedReads.add(url.pathname); return path; }
  async function request(path, method = 'GET', body) {
    const url = safeSubmissionUrl(path);
    if (method === 'GET') check(allowedReads.has(url.pathname), 'Uninspected submission read destination.');
    else check(submit && !url.search && allowedWrites.get(method + ' ' + url.pathname) === JSON.stringify(body), 'Unapproved submission mutation.');
    let response;
    try { response = await fetchImpl(url, {method, redirect: 'error', signal: AbortSignal.timeout(20000),
      headers: {Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined}); }
    catch { throw new SubmissionError('Submission API request failed or timed out.'); }
    if (!response.ok) {
      let document; try { document = await response.json(); } catch { document = null; }
      const error = new SubmissionError('Apple rejected a submission API request.');
      error.diagnostic = {method, path: url.pathname, ...safeSubmissionDiagnostic(response.status, document)};
      privateDiagnostics.push({method, path: url.pathname,
        ...privateSubmissionDiagnostic(response.status, document, Object.entries(env)
          .filter(([name]) => /KEY|SECRET|TOKEN|PASSWORD|ISSUER/i.test(name)).map(([, value]) => value))});
      throw error;
    }
    if (method !== 'GET') summary.writes.push({method, path: url.pathname});
    if (response.status === 204) return {data: null};
    try { return await response.json(); } catch { throw new SubmissionError('Unreadable submission API response.'); }
  }
  const get = async (path, type, id) => resource((await request(allow(path))).data, type, id);
  async function list(path, type) {
    const pathname = safeSubmissionUrl(path).pathname, seen = new Set(), ids = new Set(), result = [];
    allow(path);
    while (path) {
      const url = safeSubmissionUrl(path);
      check(url.pathname === pathname && !seen.has(url.href) && seen.size < 20, 'Invalid submission pagination.');
      seen.add(url.href);
      const page = await request(path);
      check(Array.isArray(page.data), 'Invalid submission resource list.');
      for (const item of page.data) {
        resource(item, type); check(!ids.has(item.id), 'Duplicate submission resource.');
        ids.add(item.id); result.push(item);
      }
      path = page.links?.next;
    }
    return result;
  }
  async function mutate(path, method, body) {
    allowedWrites.set(method + ' ' + path, JSON.stringify(body));
    return request(path, method, body);
  }
  async function persist() {
    const artifacts = [[env.APP_STORE_SUBMISSION_SUMMARY_PATH, summary],
      [env.APP_STORE_SUBMISSION_DIAGNOSTIC_PATH, {checkedAt: summary.checkedAt, diagnostics: privateDiagnostics}]];
    for (const [path, value] of artifacts) {
      if (!path) continue;
      const destination = resolve(path);
      await mkdir(dirname(destination), {recursive: true, mode: 0o700});
      await chmod(dirname(destination), 0o700);
      await writeFile(destination, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
      await chmod(destination, 0o600);
    }
  }
  try {
    const app = await get(`/v1/apps/${SUBMISSION_APP}`, 'apps', SUBMISSION_APP);
    check(app.attributes?.bundleId === bundle, 'Unexpected submission app bundle.');
    let version = await get(`/v1/appStoreVersions/${SUBMISSION_VERSION}?include=app`, 'appStoreVersions', SUBMISSION_VERSION);
    linked(version, 'app', 'apps', SUBMISSION_APP);
    check(version.attributes?.platform === 'IOS' && ['1.0', '1.0.0'].includes(version.attributes.versionString), 'Unexpected submission version.');
    summary.versionState = state(version);
    const build = await get(`/v1/appStoreVersions/${SUBMISSION_VERSION}/build`, 'builds', SUBMISSION_BUILD);
    check(build.attributes?.version === '13' && build.attributes.processingState === 'VALID'
      && build.attributes.expired === false, 'Submission requires valid unexpired build 13.');
    const buildApp = await get(`/v1/builds/${SUBMISSION_BUILD}/app`, 'apps', SUBMISSION_APP);
    check(buildApp.attributes?.bundleId === bundle, 'Unexpected submission build app.');
    if (activeReviewStates.includes(summary.versionState)) {
      summary.submitted = true;
      return summary;
    }
    check(['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'].includes(summary.versionState), 'Version is not in an editable submission state.');
    check(version.attributes.releaseType === 'AFTER_APPROVAL', 'Confirmed automatic release setting is missing.');
    check(filled(version.attributes.copyright), 'Copyright is missing.');
    check(['DOES_NOT_USE_THIRD_PARTY_CONTENT', 'USES_THIRD_PARTY_CONTENT'].includes(app.attributes.contentRightsDeclaration), 'Content rights declaration is missing.');
    check(build.attributes.usesNonExemptEncryption === false, 'Build encryption declaration is not confirmed.');
    const infos = await list(`/v1/apps/${SUBMISSION_APP}/appInfos?include=primaryCategory&limit=200`, 'appInfos');
    const editableInfos = infos.filter(item => ['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'].includes(state(item)));
    check(editableInfos.length === 1, 'Expected exactly one editable app information record.');
    const info = editableInfos[0]; linked(info, 'primaryCategory', 'appCategories');
    const infoLocales = await list(`/v1/appInfos/${info.id}/appInfoLocalizations?limit=200`, 'appInfoLocalizations');
    const infoKo = infoLocales.filter(item => item.attributes?.locale === 'ko');
    check(infoKo.length === 1 && filled(infoKo[0].attributes.name)
      && /^https:\/\//.test(infoKo[0].attributes.privacyPolicyUrl ?? ''), 'Korean app information or privacy policy URL is missing.');
    const locales = await list(`/v1/appStoreVersions/${SUBMISSION_VERSION}/appStoreVersionLocalizations?limit=200`, 'appStoreVersionLocalizations');
    const ko = locales.filter(item => item.attributes?.locale === 'ko');
    check(ko.length === 1 && ['description', 'keywords', 'supportUrl'].every(key => filled(ko[0].attributes[key])), 'Korean version metadata is incomplete.');
    const sets = await list(`/v1/appStoreVersionLocalizations/${ko[0].id}/appScreenshotSets?limit=200`, 'appScreenshotSets');
    let completeScreenshots = 0;
    for (const display of ['APP_IPHONE_67', 'APP_IPAD_PRO_3GEN_129']) {
      const target = sets.filter(item => item.attributes?.screenshotDisplayType === display);
      check(target.length === 1, 'Required screenshot family is missing or ambiguous.');
      const shots = await list(`/v1/appScreenshotSets/${target[0].id}/appScreenshots?limit=200`, 'appScreenshots');
      check(shots.length === 4 && shots.every(item => item.attributes?.assetDeliveryState?.state === 'COMPLETE'), 'All eight screenshots must finish processing.');
      completeScreenshots += shots.length;
    }
    const review = await get(`/v1/appStoreVersions/${SUBMISSION_VERSION}/appStoreReviewDetail`, 'appStoreReviewDetails');
    check(['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail', 'notes'].every(key => filled(review.attributes?.[key])), 'Review contact or access notes are incomplete.');
    check(review.attributes.demoAccountRequired === false || (review.attributes.demoAccountRequired === true
      && filled(review.attributes.demoAccountName) && filled(review.attributes.demoAccountPassword)), 'Required review access credentials are missing.');
    summary.completeScreenshots = completeScreenshots;
    summary.distribution = await prepareDistribution({
      request: (path, method = 'GET', body) => request(allow(path), method, body),
      list, app, appInfoId: info.id, mode: 'inspect',
    });
    if (!summary.distribution.ready) {
      summary.blockers.push(...summary.distribution.blockers);
      throw new SubmissionError('Free Korea-only distribution or age rating is not confirmed.');
    }
    summary.localPrerequisitesReady = true;
    const submissions = await list(`/v1/apps/${SUBMISSION_APP}/reviewSubmissions?filter[platform]=IOS&include=app,appStoreVersionForReview&limit=200`, 'reviewSubmissions');
    for (const entry of submissions) linked(entry, 'app', 'apps', SUBMISSION_APP);
    const active = submissions.filter(item => ['READY_FOR_REVIEW', ...activeReviewStates, 'UNRESOLVED_ISSUES', 'CANCELING', 'COMPLETING'].includes(item.attributes?.state));
    check(active.length <= 1, 'Multiple active review submissions need inspection.');
    let submission = active[0];
    let items = [];
    if (submission) {
      check(submission.attributes.platform === 'IOS', 'Unexpected review submission platform.');
      items = await list(`/v1/reviewSubmissions/${submission.id}/items?include=appStoreVersion&limit=200`, 'reviewSubmissionItems');
      check(items.length <= 1 && items.every(item => item.relationships?.appStoreVersion?.data?.id === SUBMISSION_VERSION
        && item.relationships.appStoreVersion.data.type === 'appStoreVersions'
        && Object.entries(item.relationships).every(([key, value]) => key === 'appStoreVersion' || value?.data == null)), 'Review submission contains unrelated items.');
      if (activeReviewStates.includes(submission.attributes.state)) {
        check(items.length === 1, 'Active submission has no target version.');
        summary.submissionId = submission.id; summary.submissionState = submission.attributes.state; summary.submitted = true;
        return summary;
      }
      check(submission.attributes.state === 'READY_FOR_REVIEW', 'Existing review submission is not ready for editing.');
    }
    if (!submit) {
      summary.submissionId = submission?.id ?? null;
      summary.submissionState = submission?.attributes.state ?? null;
      return summary;
    }
    if (!submission) {
      const body = {data: {type: 'reviewSubmissions', attributes: {platform: 'IOS'}, relationships: {app: relation('apps', SUBMISSION_APP)}}};
      submission = resource((await mutate('/v1/reviewSubmissions', 'POST', body)).data, 'reviewSubmissions');
      // Re-read through the app's relationship before using the newly created ID.
      const reread = await list(`/v1/apps/${SUBMISSION_APP}/reviewSubmissions?filter[platform]=IOS&include=app&limit=200`, 'reviewSubmissions');
      submission = reread.find(item => item.id === submission.id);
      check(submission?.attributes?.state === 'READY_FOR_REVIEW', 'Created review submission was not confirmed.');
      linked(submission, 'app', 'apps', SUBMISSION_APP);
    }
    summary.submissionId = submission.id;
    if (items.length === 0) {
      await mutate('/v1/reviewSubmissionItems', 'POST', {data: {type: 'reviewSubmissionItems', relationships: {
        reviewSubmission: relation('reviewSubmissions', submission.id), appStoreVersion: relation('appStoreVersions', SUBMISSION_VERSION),
      }}});
      items = await list(`/v1/reviewSubmissions/${submission.id}/items?include=appStoreVersion&limit=200`, 'reviewSubmissionItems');
      check(items.length === 1 && linked(items[0], 'appStoreVersion', 'appStoreVersions', SUBMISSION_VERSION), 'Review version association was not confirmed.');
    }
    await mutate(`/v1/reviewSubmissions/${submission.id}`, 'PATCH', {data: {
      type: 'reviewSubmissions', id: submission.id, attributes: {submitted: true},
    }});
    submission = await get(`/v1/reviewSubmissions/${submission.id}?include=app`, 'reviewSubmissions', submission.id);
    linked(submission, 'app', 'apps', SUBMISSION_APP);
    version = await get(`/v1/appStoreVersions/${SUBMISSION_VERSION}?include=app`, 'appStoreVersions', SUBMISSION_VERSION);
    summary.submissionState = submission.attributes?.state ?? null;
    summary.versionState = state(version);
    summary.submitted = activeReviewStates.includes(summary.submissionState) || activeReviewStates.includes(summary.versionState);
    if (!summary.submitted) summary.blockers.push('SUBMISSION_ACCEPTANCE_NOT_YET_CONFIRMED');
    return summary;
  } catch (error) {
    summary.error = error instanceof SubmissionError ? {message: error.message, ...error.diagnostic}
      : {message: 'Submission failed; unexpected details withheld.'};
    summary.blockers.push(...(error.diagnostic?.categories ?? ['SUBMISSION_PREREQUISITE_OR_REQUEST_FAILED']));
    return summary;
  } finally { await persist(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  submitAppStore(process.env).then(summary => {
    console.log(JSON.stringify(summary, null, 2));
    if (summary.blockers.length || (summary.mode === 'submit' && !summary.submitted)) process.exitCode = 2;
  }).catch(() => { console.error('Submission helper failed; credential and file details withheld.'); process.exitCode = 1; });
}
