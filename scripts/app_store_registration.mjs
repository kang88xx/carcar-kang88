// Explicit preparation only: never submits or creates versions. Only verified empty
// AWAITING_UPLOAD reservations may be recreated when Apple omits upload operations.
import {createPrivateKey, sign, createHash} from 'node:crypto';
import {readFile, writeFile, realpath, chmod, mkdir} from 'node:fs/promises';
import {resolve, sep, dirname} from 'node:path';
import {pathToFileURL} from 'node:url';

export const APP_ID = '6829616379';
const BUNDLE = 'com.kang88.carcar';
const ORIGIN = 'https://api.appstoreconnect.apple.com';
// Explicitly approved recovery target from the failed, never-uploaded reservation.
const RECREATABLE_EMPTY_SCREENSHOT_IDS = new Set(['34000019-713a-8cfb-8037-5f8c33da22ed']);
const SOURCE = '069dd4ccb49add356706f909335f938994c2076b';
const SCENES = ['01-home.jpg', '02-parking-entry.jpg', '03-family.jpg', '04-history.jpg'];
const FAMILIES = {iphone: ['APP_IPHONE_67', 1320, 2868], ipad: ['APP_IPAD_PRO_3GEN_129', 2064, 2752]};
export class RegistrationError extends Error {}
const check = (ok, message) => { if (!ok) throw new RegistrationError(message); };
const digest = (data, algorithm = 'sha256') => createHash(algorithm).update(data).digest('hex');
const state = item => item.attributes?.appVersionState ?? item.attributes?.state ?? item.attributes?.appStoreState;
function item(data, type, id) {
  check(data?.type === type && /^[A-Za-z0-9._~=-]{1,512}$/.test(data.id ?? '') && !['.', '..'].includes(data.id) && (!id || data.id === id), 'Unexpected Apple resource identity.');
  return data;
}
function relation(data, name, type, id) {
  const value = data.relationships?.[name]?.data;
  check(value?.type === type && value.id === id, 'Apple resource belongs to an unexpected parent.');
}
export function validateTarget(app, version, build, buildApp, prerelease) {
  item(app, 'apps', APP_ID);
  check(app.attributes?.bundleId === BUNDLE, 'Unexpected app bundle.');
  item(version, 'appStoreVersions'); relation(version, 'app', 'apps', APP_ID);
  check(version.attributes?.platform === 'IOS' && version.attributes.versionString === '1.0'
    && state(version) === 'PREPARE_FOR_SUBMISSION', 'Only existing editable iOS version 1.0 is permitted.');
  item(build, 'builds'); item(buildApp, 'apps', APP_ID);
  check(buildApp.attributes?.bundleId === BUNDLE, 'Build belongs to another app.');
  item(prerelease, 'preReleaseVersions');
  check(build.attributes?.version === '13' && build.attributes.processingState === 'VALID'
    && build.attributes.expired === false && prerelease.attributes?.version === '1.0.0'
    && prerelease.attributes.platform === 'IOS', 'Only valid, unexpired iOS build 1.0.0 (13) is permitted.');
}
export function safeApiUrl(path) {
  let url; try { url = new URL(path, ORIGIN); } catch { throw new RegistrationError('Invalid Apple API URL.'); }
  check(url.origin === ORIGIN && !url.username && !url.password && !url.hash && /^\/v[12]\/[A-Za-z0-9/._~=-]+$/.test(url.pathname), 'Unexpected Apple API destination.');
  return url;
}
// Apple documents blobstore URLs in its reserve-upload-commit examples:
// https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect
// https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets
function uploadHosts(operations) {
  return [...new Set((operations ?? []).map(op => {
    try { const host = new URL(op.url).hostname; return /^[a-z0-9.-]{1,253}$/.test(host) ? host : 'INVALID_HOST'; }
    catch { return 'INVALID_HOST'; }
  }))];
}
function screenshotStatus(image) {
  return {id: image.id, fileName: image.attributes?.fileName, fileSize: image.attributes?.fileSize,
    checksum: image.attributes?.sourceFileChecksum, state: image.attributes?.assetDeliveryState?.state,
    uploadHosts: uploadHosts(image.attributes?.uploadOperations),
    uploadHeaderNames: [...new Set((image.attributes?.uploadOperations ?? []).flatMap(operation =>
      (operation.requestHeaders ?? []).map(header => header.name)
        .filter(name => typeof name === 'string' && /^[A-Za-z0-9-]{1,80}$/.test(name))))]};
}
function resumable(image, file) {
  return image.attributes?.fileName === file.name && image.attributes?.fileSize === file.bytes.length
    && image.attributes?.assetDeliveryState?.state === 'AWAITING_UPLOAD' && image.attributes?.sourceFileChecksum == null;
}
function approvedProcessing(image, file) {
  return image.id === 'fd000019-713a-8cfb-8028-5678fc36717b' && file.family === 'ipad' && file.name === '03-family.jpg'
    && image.attributes?.fileName === file.name && image.attributes?.fileSize === file.bytes.length
    && image.attributes?.assetDeliveryState?.state === 'UPLOAD_COMPLETE'
    && (image.attributes?.sourceFileChecksum == null || image.attributes.sourceFileChecksum === file.md5);
}
export function safeUploadUrl(value) {
  let url; try { url = new URL(value); } catch { throw new RegistrationError('Invalid upload URL.'); }
  check(url.protocol === 'https:' && !url.username && !url.password && !url.hash && !url.port
    && (/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*blobstore\.apple\.com$/.test(url.hostname)
      // Observed in authenticated Apple's reservation response, run 42485688529.
      || url.hostname === 'northamerica-1.object-storage.apple.com'), 'Unverified Apple upload host: ' + uploadHosts([{url: value}])[0] + '; no bytes were sent.');
  return url;
}
export async function uploadParts(operations, bytes, fetchImpl = fetch) {
  check(Array.isArray(operations) && operations.length > 0 && operations.length <= 100, 'Invalid upload operation list.');
  let nextOffset = 0;
  const prepared = operations.map(op => {
    const url = safeUploadUrl(op.url);
    check(op.method === 'PUT' && Number.isSafeInteger(op.offset) && Number.isSafeInteger(op.length)
      && op.offset === nextOffset && op.length > 0 && op.offset + op.length <= bytes.length, 'Invalid or overlapping upload byte range.');
    nextOffset += op.length;
    const headers = {};
    for (const header of op.requestHeaders ?? []) {
      check(typeof header.name === 'string' && typeof header.value === 'string'
        && /^(content-type|content-length|content-md5|x-apple-[a-z0-9-]+|x-amz-[a-z0-9-]+)$/i.test(header.name)
        && !/[\r\n]/.test(header.value) && !Object.keys(headers).some(k => k.toLowerCase() === header.name.toLowerCase()), 'Unexpected upload header.');
      if (header.name.toLowerCase() === 'content-length') check(header.value === String(op.length), 'Upload length header mismatch.');
      headers[header.name] = header.value;
    }
    return {url, headers, offset: op.offset, length: op.length};
  });
  check(nextOffset === bytes.length, 'Upload operations do not cover the exact source file.');
  for (const op of prepared) {
    let response;
    try { response = await fetchImpl(op.url, {method: 'PUT', headers: op.headers,
      body: bytes.subarray(op.offset, op.offset + op.length), redirect: 'error', signal: AbortSignal.timeout(60_000)}); }
    catch { throw new RegistrationError('Screenshot binary upload failed; signed URL withheld.'); }
    check(response.ok, 'Screenshot binary upload failed with HTTP ' + response.status + '.');
  }
}
export function jpegSize(bytes) {
  check(bytes.length > 4 && bytes.readUInt16BE(0) === 0xffd8, 'Screenshot is not JPEG.');
  for (let offset = 2; offset + 4 < bytes.length;) {
    check(bytes[offset] === 0xff, 'Invalid JPEG marker.');
    const marker = bytes[offset + 1];
    const length = bytes.readUInt16BE(offset + 2);
    check(length >= 2 && offset + 2 + length <= bytes.length, 'Invalid JPEG segment.');
    if ([0xc0, 0xc1, 0xc2].includes(marker)) {
      check(length >= 8, 'Invalid JPEG frame.');
      return [bytes.readUInt16BE(offset + 7), bytes.readUInt16BE(offset + 5)];
    }
    offset += 2 + length;
  }
  throw new RegistrationError('JPEG dimensions not found.');
}
export async function loadMedia(directory) {
  const root = await realpath(directory);
  const manifest = JSON.parse(await readFile(resolve(root, 'manifest.json'), 'utf8'));
  check(manifest.sourceCommit === SOURCE && manifest.productSourceMatchesTestFlight13 === true
    && manifest.testFlightBuild === '1.0.0 (13)' && manifest.dataSource === 'built-in local demo', 'Media provenance mismatch.');
  const media = [];
  for (const [family, [display, width, height]] of Object.entries(FAMILIES)) {
    const devices = manifest.devices?.filter(d => d.deviceFamily === family) ?? [];
    check(devices.length === 1, 'Ambiguous screenshot manifest.');
    for (const name of SCENES) {
      const file = await realpath(resolve(root, family, name));
      check(file.startsWith(root + sep), 'Screenshot resolves outside media root.');
      const bytes = await readFile(file);
      const matches = devices[0].screenshots?.filter(s => s.file === name) ?? [];
      check(matches.length === 1 && matches[0].sha256 === digest(bytes) && matches[0].hasAlpha === false
        && matches[0].width === width && matches[0].height === height, 'Screenshot content integrity mismatch.');
      check(JSON.stringify(jpegSize(bytes)) === JSON.stringify([width, height]), 'Unexpected screenshot dimensions.');
      media.push({family, display, name, bytes, md5: digest(bytes, 'md5'), sha256: digest(bytes)});
    }
  }
  return media;
}
export function parseReviewContact(value) {
  if (value === undefined || value === '') return null;
  let contact;
  try { contact = JSON.parse(value); } catch { throw new RegistrationError('Invalid review contact JSON.'); }
  const keys = ['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'];
  check(contact && typeof contact === 'object' && !Array.isArray(contact)
    && Object.keys(contact).length === keys.length && Object.keys(contact).every(k => keys.includes(k)), 'Review contact must contain only the four contact fields.');
  for (const key of keys) check(typeof contact[key] === 'string' && contact[key] === contact[key].trim()
    && contact[key].length > 0 && contact[key].length <= 100 && !/[\x00-\x1f\x7f]/.test(contact[key]), 'Invalid review contact field: ' + key + '.');
  check(/^\+?[0-9 ()-]{6,32}$/.test(contact.contactPhone) && (contact.contactPhone.match(/[0-9]/g) ?? []).length >= 6, 'Invalid review contact phone.');
  check(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact.contactEmail), 'Invalid review contact email.');
  return contact;
}
export async function apiDiagnostics(response) {
  const allowedCodes = new Set(['ENTITY_ERROR', 'ENTITY_ERROR.ATTRIBUTE.INVALID', 'ENTITY_ERROR.ATTRIBUTE.REQUIRED',
    'ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE', 'ENTITY_ERROR.RELATIONSHIP.INVALID', 'ENTITY_ERROR.RELATIONSHIP.REQUIRED',
    'STATE_ERROR', 'FORBIDDEN_ERROR', 'NOT_FOUND', 'UNAUTHORIZED_ACCESS', 'PARAMETER_ERROR.INVALID', 'PARAMETER_ERROR.INVALID.VALUE']);
  const fields = new Set(['name','subtitle','privacyPolicyUrl','description','keywords','marketingUrl','promotionalText','supportUrl',
    'versionString','copyright','releaseType','contentRightsDeclaration','fileName','fileSize','uploaded','sourceFileChecksum',
    'contactFirstName','contactLastName','contactPhone','contactEmail','notes','demoAccountRequired','screenshotDisplayType',
    'available','availableInNewTerritories','preOrderEnabled']);
  let errors = [];
  try { const body = await response.json(); if (Array.isArray(body.errors)) errors = body.errors.slice(0,10); } catch { /* No raw error text is emitted. */ }
  return {status: response.status,
    codes: [...new Set(errors.map(e => e?.code).filter(c => allowedCodes.has(c)))],
    pointers: [...new Set(errors.map(e => e?.source?.pointer).filter(p => typeof p === 'string' && (
      (p.startsWith('/data/attributes/') && fields.has(p.slice('/data/attributes/'.length)))
      || /^\/data\/relationships\/(build|primaryCategory|app|appStoreVersion|appScreenshotSet|appStoreVersionLocalization)\/data(?:\/(id|type))?$/.test(p))))]};
}
export function redactProviderDiagnostic(text, env) {
  let result = typeof text === 'string' ? text.slice(0, 4000) : '';
  const secrets = Object.entries(env).filter(([key]) => /KEY|TOKEN|SECRET|PASSWORD|CONTACT/i.test(key)).map(([,value]) => value);
  try { secrets.push(...Object.values(JSON.parse(env.APP_STORE_REVIEW_CONTACT_JSON ?? '{}'))); } catch { /* Invalid input is handled before transport. */ }
  for (const secret of secrets.filter(v => typeof v === 'string' && v.length >= 3).sort((a,b)=>b.length-a.length)) result = result.split(secret).join('[REDACTED]');
  return result.replace(/https?:\/\/[^\s"<>]+/gi, '[URL]')
    .replace(/Bearer\s+[^\s,;]+/gi, 'Bearer [REDACTED]')
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[JWT]')
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[EMAIL]')
    .replace(/\+?\d[\d ()-]{5,}\d/g, '[NUMBER]').slice(0, 1000);
}
function signer(env) {
  check(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID ?? '')
    && /^[0-9a-f-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID ?? ''), 'Missing or invalid App Store Connect identifiers.');
  let key;
  try { key = createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64 ?? '', 'base64')); }
  catch { throw new RegistrationError('Invalid App Store Connect private key.'); }
  check(key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails?.namedCurve === 'prime256v1', 'An ES256 key is required.');
  return () => {
    const enc = v => Buffer.from(JSON.stringify(v)).toString('base64url'), now = Math.floor(Date.now() / 1000);
    const data = enc({alg: 'ES256', typ: 'JWT', kid: env.APP_STORE_CONNECT_KEY_ID}) + '.'
      + enc({iss: env.APP_STORE_CONNECT_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'});
    return data + '.' + sign('sha256', Buffer.from(data), {key, dsaEncoding: 'ieee-p1363'}).toString('base64url');
  };
}
const attributes = resource => resource?.attributes ?? {};
const publicAttributes = resource => Object.fromEntries(Object.entries(attributes(resource)).filter(([key]) =>
  !/contact|email|phone|password|username|notes|token|upload|asset/i.test(key)));
const contactFields = resource => Object.fromEntries(['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'].filter(k => typeof resource?.attributes?.[k] === 'string').map(k => [k, resource.attributes[k]]));
const contactStatus = resource => ({present: Boolean(resource), fieldsPresent: ['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail']
  .filter(key => Boolean(resource?.attributes?.[key])), demoAccountRequired: resource?.attributes?.demoAccountRequired ?? null});

export async function registerApp(env, fetchImpl = fetch, options = {}) {
  const mode = env.APP_STORE_REGISTRATION_MODE ?? 'inspect';
  check(['inspect', 'prepare'].includes(mode), 'Mode must be inspect or prepare; submission is not supported.');
  check(!env.CARCAR_APP_ID || env.CARCAR_APP_ID === APP_ID, 'This helper is restricted to carcar.');
  const reviewContact = parseReviewContact(env.APP_STORE_REVIEW_CONTACT_JSON);
  const token = signer(env), granted = new Set(), emptyReservationDeletes = new Set(), writes = [];
  const privateDiagnostics = [];
  const summary = {appId: APP_ID, bundleId: BUNDLE, mode, checkedAt: new Date().toISOString(), writes, blockers: [], submitted: false};
  const allow = path => { granted.add(safeApiUrl(path).pathname); return path; };
  async function request(path, method = 'GET', body, optional = false) {
    const url = safeApiUrl(path);
    check(granted.has(url.pathname), 'API resource was not discovered through the target app.');
    check(method === 'GET' || (mode === 'prepare' && !url.search && (['POST', 'PATCH'].includes(method)
      || (method === 'DELETE' && emptyReservationDeletes.delete(url.pathname)))), 'Write blocked or deletion not authorized for a verified empty reservation.');
    let response;
    try { response = await fetchImpl(url, {method, headers: {Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined, redirect: 'error', signal: AbortSignal.timeout(30_000)}); }
    catch { throw new RegistrationError('Apple API request failed or timed out.'); }
    if (optional && response.status === 404) return {data: null};
    if (!response.ok) {
      if (env.APP_STORE_REGISTRATION_PRIVATE_PATH && /^\/v[12]\/(appAvailabilities|appScreenshots)(?:\/[A-Za-z0-9._~=-]+)?$/.test(url.pathname)) {
        try {
          const provider = await response.clone().json();
          privateDiagnostics.push({path: url.pathname, status: response.status,
            errors: (Array.isArray(provider.errors) ? provider.errors.slice(0,5) : []).map(e => ({
              title: redactProviderDiagnostic(e.title, env), detail: redactProviderDiagnostic(e.detail, env)}))});
          const diagnosticPath = env.APP_STORE_REGISTRATION_PRIVATE_PATH + '.diagnostics.json';
          await mkdir(dirname(resolve(diagnosticPath)), {recursive:true, mode:0o700});
          await writeFile(diagnosticPath, JSON.stringify(privateDiagnostics.slice(-10), null, 2) + '\n', {mode:0o600});
          await chmod(diagnosticPath, 0o600);
        } catch { /* Diagnostic capture must not replace the original HTTP failure. */ }
      }
      const diagnostic = await apiDiagnostics(response);
      const error = new RegistrationError('Apple API HTTP ' + response.status + ' for ' + method + ' ' + url.pathname
        + '; codes=' + diagnostic.codes.join(',') + '; fields=' + diagnostic.pointers.join(',') + '.');
      error.status = response.status; error.diagnostic = diagnostic;
      throw error;
    }
    if (method !== 'GET') writes.push({method, path: url.pathname});
    if (response.status === 204) return {data: null};
    try { return await response.json(); } catch { throw new RegistrationError('Unreadable Apple API response.'); }
  }
  async function get(path, type, optional = false) {
    const data = (await request(allow(path), 'GET', undefined, optional)).data;
    return data === null && optional ? null : item(data, type);
  }
  async function list(path, type, optional = false) {
    const pathname = safeApiUrl(path).pathname, seen = new Set(), result = [], ids = new Set();
    allow(path);
    while (path) {
      const url = safeApiUrl(path);
      check(url.pathname === pathname && !seen.has(url.href) && seen.size < 20, 'Unexpected pagination.'); seen.add(url.href);
      const page = await request(url.href, 'GET', undefined, optional);
      if (page.data === null && optional) {
        summary.blockers.push('Related configuration is absent (HTTP 404): ' + pathname);
        return result;
      }
      check(Array.isArray(page.data), 'Invalid resource list.');
      for (const resource of page.data) {
        item(resource, type); check(!ids.has(resource.id), 'Duplicate resource ID.'); ids.add(resource.id); result.push(resource);
      }
      path = page.links?.next;
    }
    return result;
  }
  async function patch(resource, desired, relationships) {
    const path = allow('/v1/' + resource.type + '/' + resource.id);
    const changes = Object.fromEntries(Object.entries(desired).filter(([k, v]) => attributes(resource)[k] !== v));
    const relChanges = Object.fromEntries(Object.entries(relationships ?? {}).filter(([k, v]) =>
      JSON.stringify(resource.relationships?.[k]?.data) !== JSON.stringify(v.data)));
    if (Object.keys(changes).length || Object.keys(relChanges).length) {
      const data = {type: resource.type, id: resource.id};
      if (Object.keys(changes).length) data.attributes = changes;
      if (Object.keys(relChanges).length) data.relationships = relChanges;
      await request(path, 'PATCH', {data});
      let verified, mismatches;
      for (let attempt = 0; attempt < 3; attempt++) {
        verified = await get(resource.type === 'apps'
          ? path + '?fields[apps]=name,bundleId,primaryLocale,contentRightsDeclaration,isOrEverWasMadeForKids' : path, resource.type);
        mismatches = Object.keys(changes).filter(k => attributes(verified)[k] !== changes[k]);
        if (!mismatches.length) break;
        if (attempt < 2) await (options.sleep ?? (ms => new Promise(r => setTimeout(r, ms))))(1000);
      }
      summary.updates ??= [];
      const update = {type: resource.type, id: resource.id, attributes: publicAttributes(verified), verified: mismatches.length === 0};
      summary.updates.push(update);
      if (resource.type === 'apps') summary.app = publicAttributes(verified);
      if (resource.type === 'appStoreVersions') summary.version = {id: verified.id, ...publicAttributes(verified)};
      for (const [type, key] of [['appInfoLocalizations','infoLocalizations'],['appStoreVersionLocalizations','localizations']]) {
        if (resource.type === type) summary[key] = summary[key].map(l => l.id === verified.id ? {id: verified.id, ...publicAttributes(verified)} : l);
      }
      if (mismatches.length) {
        const failure = 'Metadata readback mismatch for ' + resource.type + '/' + resource.id + ': ' + mismatches.join(',');
        if (resource.type === 'apps' && mismatches.length === 1 && mismatches[0] === 'contentRightsDeclaration') {
          summary.blockers.push(failure + '; independent preparation continues, content rights remain unverified.');
        } else throw new RegistrationError(failure + '.');
      }
      update.relationships = {};
      for (const [k, v] of Object.entries(relChanges)) {
        let observed;
        for (let attempt = 0; attempt < 3; attempt++) {
          observed = (await request(allow(path + '/relationships/' + k))).data;
          if (observed?.type === v.data.type && observed.id === v.data.id) break;
          if (attempt < 2) await (options.sleep ?? (ms => new Promise(r => setTimeout(r, ms))))(1000);
        }
        check(observed?.type === v.data.type && observed.id === v.data.id, 'Relationship readback mismatch for ' + resource.type + ': ' + k + '.');
        update.relationships[k] = observed;
      }
    }
  }
  async function saveReport() {
    if (env.APP_STORE_REGISTRATION_SUMMARY_PATH) {
      await mkdir(dirname(resolve(env.APP_STORE_REGISTRATION_SUMMARY_PATH)), {recursive: true, mode: 0o700});
      await writeFile(env.APP_STORE_REGISTRATION_SUMMARY_PATH, JSON.stringify(summary, null, 2) + '\n', {mode: 0o600});
      await chmod(env.APP_STORE_REGISTRATION_SUMMARY_PATH, 0o600);
    }
  }
  try {
    const app = await get('/v1/apps/' + APP_ID, 'apps');
    check(app.id === APP_ID && app.attributes?.bundleId === BUNDLE, 'Unexpected app identity.');
    const infos = await list('/v1/apps/' + APP_ID + '/appInfos?include=app,primaryCategory&limit=200', 'appInfos');
    const versions = await list('/v1/apps/' + APP_ID + '/appStoreVersions?include=app,build&limit=200', 'appStoreVersions');
    const selected = versions.filter(v => v.attributes?.platform === 'IOS' && v.attributes.versionString === '1.0');
    check(selected.length === 1, 'Expected exactly one existing iOS version 1.0.');
    const version = selected[0];
    const editable = infos.filter(v => state(v) === 'PREPARE_FOR_SUBMISSION');
    check(editable.length === 1, 'Expected exactly one editable app information record.');
    const info = editable[0]; relation(info, 'app', 'apps', APP_ID);
    const builds = await list('/v1/builds?filter[app]=' + APP_ID + '&filter[version]=13&limit=200', 'builds');
    check(builds.length === 1, 'Expected exactly one build 13.');
    const build = builds[0];
    const buildApp = await get('/v1/builds/' + build.id + '/app', 'apps');
    const prerelease = await get('/v1/builds/' + build.id + '/preReleaseVersion', 'preReleaseVersions');
    validateTarget(app, version, build, buildApp, prerelease);
    const infoLocales = await list('/v1/appInfos/' + info.id + '/appInfoLocalizations?limit=200', 'appInfoLocalizations');
    const versionLocales = await list('/v1/appStoreVersions/' + version.id + '/appStoreVersionLocalizations?limit=200', 'appStoreVersionLocalizations');
    const age = await get('/v1/appInfos/' + info.id + '/ageRatingDeclaration', 'ageRatingDeclarations', true);
    const review = await get('/v1/appStoreVersions/' + version.id + '/appStoreReviewDetail', 'appStoreReviewDetails', true);
    const betaReview = await get('/v1/apps/' + APP_ID + '/betaAppReviewDetail', 'betaAppReviewDetails', true);
    if (env.APP_STORE_REGISTRATION_PRIVATE_PATH) {
      const privateReport = {appId: APP_ID, reviewContact: contactFields(review), betaReviewContact: contactFields(betaReview)};
      await mkdir(dirname(resolve(env.APP_STORE_REGISTRATION_PRIVATE_PATH)), {recursive: true, mode: 0o700});
      await writeFile(env.APP_STORE_REGISTRATION_PRIVATE_PATH, JSON.stringify(privateReport, null, 2) + '\n', {mode: 0o600});
      await chmod(env.APP_STORE_REGISTRATION_PRIVATE_PATH, 0o600);
    }
    // Persist core facts before optional distribution endpoints: Apple may return
    // a placeholder schedule whose manualPrices relationship returns HTTP 404.
    Object.assign(summary, {app: publicAttributes(app), info: {id: info.id, state: state(info)},
      infoLocalizations: infoLocales.map(l => ({id: l.id, ...publicAttributes(l)})),
      version: {id: version.id, ...publicAttributes(version)}, build: {id: build.id, ...publicAttributes(build)},
      localizations: versionLocales.map(l => ({id: l.id, ...publicAttributes(l)})), age: publicAttributes(age),
      review: contactStatus(review), betaReview: contactStatus(betaReview)});
    const price = await get('/v1/apps/' + APP_ID + '/appPriceSchedule', 'appPriceSchedules', true);
    const availability = await get('/v1/apps/' + APP_ID + '/appAvailabilityV2', 'appAvailabilities', true);
    const prices = price ? await list('/v1/appPriceSchedules/' + price.id + '/manualPrices?include=appPricePoint,territory&limit=200', 'appPrices', true) : [];
    const territories = availability ? await list('/v2/appAvailabilities/' + availability.id + '/territoryAvailabilities?include=territory&limit=200', 'territoryAvailabilities', true) : [];
    Object.assign(summary, {
      price: {present: Boolean(price), manualPrices: prices.map(p => ({id: p.id, attributes: publicAttributes(p), relationships: p.relationships}))},
      availability: {present: Boolean(availability), attributes: publicAttributes(availability), territories: territories.map(t => ({id: t.id, attributes: publicAttributes(t), territory: t.relationships?.territory?.data}))}});
    if (!version.attributes?.copyright) summary.blockers.push('Copyright owner/year missing; not invented.');
    if (contactStatus(review).fieldsPresent.length !== 4) summary.blockers.push('App Review contact incomplete; existing beta contact may be reused only after explicit review.');
    summary.blockers.push('Age declaration requires verified payload; unchanged.', 'Price and Korea availability require separate verified setup; unchanged.', 'App Privacy and reviewer access require independent verification.');
    const screenshots = [];
    for (const locale of versionLocales) {
      const sets = await list('/v1/appStoreVersionLocalizations/' + locale.id + '/appScreenshotSets?limit=200', 'appScreenshotSets');
      for (const set of sets) {
        const images = await list('/v1/appScreenshotSets/' + set.id + '/appScreenshots?limit=200', 'appScreenshots');
        screenshots.push({locale: locale.attributes.locale, localeId: locale.id, set, images});
      }
    }
    summary.screenshots = screenshots.map(s => ({locale: s.locale, setId: s.set.id, display: s.set.attributes?.screenshotDisplayType,
      images: s.images.map(screenshotStatus)}));
    if (mode === 'prepare') {
      const draft = JSON.parse(await readFile(resolve(env.APP_STORE_DRAFT_PATH ?? 'docs/app-store/submission-draft.json'), 'utf8'));
      check(draft.locale === 'ko' && draft.listing?.name === '차자리 - 가족 주차 기록' && draft.listing.proposedPrimaryCategory === 'UTILITIES', 'Unexpected approved listing draft.');
      check(Boolean(env.APP_STORE_MEDIA_ROOT), 'APP_STORE_MEDIA_ROOT is required for prepare.');
      const media = await loadMedia(env.APP_STORE_MEDIA_ROOT);
      const il = infoLocales.filter(l => l.attributes?.locale === draft.locale), vl = versionLocales.filter(l => l.attributes?.locale === draft.locale);
      check(il.length === 1 && vl.length === 1, 'Existing Korean localizations required; no implicit creation.');
      const reviewNotes = reviewContact ? await readFile(resolve('docs/app-store/review-notes.txt'), 'utf8') : null;
      if (reviewContact) check(reviewNotes.trim().length > 0 && reviewNotes.length <= 4000, 'Review notes must contain 1 to 4000 characters.');
      const release = env.APP_STORE_RELEASE_TYPE === 'KEEP' ? undefined : env.APP_STORE_RELEASE_TYPE;
      check(!release || ['MANUAL', 'AFTER_APPROVAL'].includes(release), 'Release type must be explicitly MANUAL or AFTER_APPROVAL.');
      // Preflight every existing screenshot before any writes; unknown media is never removed.
      for (const [family, [display]] of Object.entries(FAMILIES)) {
        const matches = screenshots.filter(s => s.localeId === vl[0].id && s.set.attributes?.screenshotDisplayType === display);
        check(matches.length <= 1, 'Duplicate screenshot sets require manual review.');
        const names = (matches[0]?.images ?? []).map(i => i.attributes?.fileName);
        check(JSON.stringify(names) === JSON.stringify(SCENES.slice(0, names.length)), 'Existing screenshot order or duplicate names require review.');
        for (const image of matches[0]?.images ?? []) {
          const file = media.find(m => m.family === family && m.name === image.attributes?.fileName);
          check(file && (resumable(image, file) || approvedProcessing(image, file) || (image.attributes?.fileSize === file.bytes.length && image.attributes?.sourceFileChecksum === file.md5
            && image.attributes?.assetDeliveryState?.state === 'COMPLETE')), 'Existing unknown, mismatched, or incomplete screenshot requires review; nothing deleted.');
        }
      }
      // Recheck target state immediately before mutations.
      const freshVersion = await get('/v1/appStoreVersions/' + version.id + '?include=app', 'appStoreVersions');
      const freshBuild = await get('/v1/builds/' + build.id, 'builds');
      validateTarget(app, freshVersion, freshBuild, buildApp, prerelease);
      await patch(il[0], {name: draft.listing.name, subtitle: draft.listing.subtitle, privacyPolicyUrl: draft.listing.privacyPolicyUrl});
      await patch(info, {}, {primaryCategory: {data: {type: 'appCategories', id: 'UTILITIES'}}});
      await patch(vl[0], Object.fromEntries(['description', 'keywords', 'marketingUrl', 'promotionalText', 'supportUrl'].map(k => [k, draft.listing[k]])));
      await patch(app, {contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT'});
      const versionChanges = {};
      if (draft.listing.copyright) versionChanges.copyright = draft.listing.copyright;
      // A bare owner is not enough to invent a copyright year. Supply approved
      // complete wording in the draft; COPYRIGHT_OWNER is retained as a blocker.
      if (env.COPYRIGHT_OWNER && !draft.listing.copyright) summary.blockers.push('Copyright owner supplied but complete approved copyright wording is absent from draft.');
      if (release) versionChanges.releaseType = release;
      await patch(version, versionChanges, {build: {data: {type: 'builds', id: build.id}}});
      if (reviewContact) {
        const desired = {...reviewContact, notes: reviewNotes, demoAccountRequired: false};
        let detail = review;
        if (detail) {
          const scopedDetail = await get('/v1/appStoreReviewDetails/' + detail.id + '?include=appStoreVersion', 'appStoreReviewDetails');
          relation(scopedDetail, 'appStoreVersion', 'appStoreVersions', version.id);
          await patch(detail, desired);
        } else {
          detail = item((await request(allow('/v1/appStoreReviewDetails'), 'POST', {data: {type: 'appStoreReviewDetails', attributes: desired,
            relationships: {appStoreVersion: {data: {type: 'appStoreVersions', id: version.id}}}}})).data, 'appStoreReviewDetails');
        }
        const verifiedReview = await get('/v1/appStoreVersions/' + version.id + '/appStoreReviewDetail', 'appStoreReviewDetails');
        check(verifiedReview.id === detail.id && Object.entries(desired).every(([k,v]) => verifiedReview.attributes?.[k] === v), 'Review contact or notes readback mismatch.');
        summary.review = {...contactStatus(verifiedReview), notesVerified: true, suppliedContactVerified: true};
        summary.blockers = summary.blockers.filter(message => !message.startsWith('App Review contact incomplete;'));
      }
      const prepareDistribution = options.distribution ?? (await import('./app_store_distribution.mjs')).prepareDistribution;
      try {
        summary.distribution = await prepareDistribution({
        request: (path, method = 'GET', body) => request(allow(path), method, body),
        list: (path, type) => list(path, type), app, appInfoId: info.id, mode,
        });
      } catch (error) {
        const safe = error instanceof RegistrationError ? error : new RegistrationError('Distribution preparation failed; private details withheld.');
        summary.distribution = {ready:false, error:safe.message, diagnostic:safe.diagnostic,
          blockers:['Distribution preparation remains unverified after an error; independent screenshots continue.']};
        await saveReport();
      }
      summary.blockers = summary.blockers.filter(message =>
        message !== 'Age declaration requires verified payload; unchanged.'
        && message !== 'Price and Korea availability require separate verified setup; unchanged.'
        && !(summary.distribution.pricing?.ready && message.startsWith('Related configuration is absent (HTTP 404): /v1/appPriceSchedules/')));
      summary.blockers.push(...summary.distribution.blockers);
      if (versionChanges.copyright) summary.blockers = summary.blockers.filter(message => message !== 'Copyright owner/year missing; not invented.');
      summary.preparedScreenshots = [];
      const processingQueue = [];
      for (const [family, [display]] of Object.entries(FAMILIES)) {
        const prior = screenshots.find(s => s.localeId === vl[0].id && s.set.attributes?.screenshotDisplayType === display);
        let set = prior?.set;
        if (!set) set = item((await request(allow('/v1/appScreenshotSets'), 'POST', {data: {type: 'appScreenshotSets', attributes: {screenshotDisplayType: display},
          relationships: {appStoreVersionLocalization: {data: {type: 'appStoreVersionLocalizations', id: vl[0].id}}}}})).data, 'appScreenshotSets');
        // Confirm newly-created relationship before reserving bytes.
        const scopedSet = await get('/v1/appScreenshotSets/' + set.id + '?include=appStoreVersionLocalization', 'appScreenshotSets');
        relation(scopedSet, 'appStoreVersionLocalization', 'appStoreVersionLocalizations', vl[0].id);
        for (const file of media.filter(m => m.family === family)) {
          const existing = prior?.images.find(i => i.attributes.fileName === file.name);
          if (existing?.attributes?.assetDeliveryState?.state === 'COMPLETE') { summary.preparedScreenshots.push({family, name: file.name, id: existing.id, reused: true}); continue; }
          async function reserve() {
            const reserved = item((await request(allow('/v1/appScreenshots'), 'POST', {data: {type: 'appScreenshots', attributes: {fileName: file.name, fileSize: file.bytes.length},
              relationships: {appScreenshotSet: {data: {type: 'appScreenshotSets', id: set.id}}}}})).data, 'appScreenshots');
            summary.reservations ??= [];
            summary.reservations.push({family, ...screenshotStatus(reserved)});
            await saveReport();
            return reserved;
          }
          let image = existing ?? await reserve();
          let imagePath = allow('/v1/appScreenshots/' + image.id);
          const readScoped = () => get(imagePath + '?include=appScreenshotSet&fields[appScreenshots]=uploadOperations,fileName,fileSize,sourceFileChecksum,assetDeliveryState,appScreenshotSet', 'appScreenshots');
          let scopedImage = await readScoped();
          relation(scopedImage, 'appScreenshotSet', 'appScreenshotSets', set.id);
          if (existing && approvedProcessing(existing, file)) {
            const progress = {family, ...screenshotStatus(scopedImage), resumed:true};
            summary.pendingScreenshots ??= []; summary.pendingScreenshots.push(progress);
            check(approvedProcessing(scopedImage, file) || (scopedImage.attributes?.assetDeliveryState?.state === 'COMPLETE'
              && scopedImage.attributes?.fileName === file.name && scopedImage.attributes?.fileSize === file.bytes.length
              && scopedImage.attributes?.sourceFileChecksum === file.md5), 'Known processing reservation changed unexpectedly.');
            processingQueue.push({imagePath, image, file, family, progress, resumed:true});
            await saveReport();
            continue; // Already uploaded and committed: never delete, reupload, or recommit.
          }
          check(resumable(scopedImage, file), 'Screenshot reservation changed; refusing to upload.');
          if (existing && !(scopedImage.attributes?.uploadOperations?.length > 0)) {
            // Deletion is authorized only for this freshly read, known empty file
            // in the already verified target locale/set. Complete/failed/unknown
            // assets can never enter this single-use deletion gate.
            check(RECREATABLE_EMPTY_SCREENSHOT_IDS.has(image.id), 'Empty reservation has no upload operations and is not an explicitly approved recreation target.');
            emptyReservationDeletes.add(imagePath);
            await request(imagePath, 'DELETE');
            summary.recreatedEmptyReservations ??= [];
            summary.recreatedEmptyReservations.push({id:image.id, family, name:file.name});
            image = await reserve();
            imagePath = allow('/v1/appScreenshots/' + image.id);
            scopedImage = await readScoped();
            relation(scopedImage, 'appScreenshotSet', 'appScreenshotSets', set.id);
            check(resumable(scopedImage, file), 'Replacement screenshot reservation changed; refusing to upload.');
          }
          // Apple may return signed operations ONLY in the POST reservation response.
          const operations = image !== existing ? image.attributes?.uploadOperations : scopedImage.attributes?.uploadOperations;
          const progress = {family, ...screenshotStatus(scopedImage), uploadHosts:uploadHosts(operations), resumed:Boolean(existing)};
          summary.pendingScreenshots ??= [];
          summary.pendingScreenshots.push(progress);
          await saveReport();
          await uploadParts(operations, file.bytes, fetchImpl);
          await request(imagePath, 'PATCH', {data: {type: 'appScreenshots', id: image.id, attributes: {uploaded: true, sourceFileChecksum: file.md5}}});
          processingQueue.push({imagePath, image, file, family, progress, resumed:Boolean(existing)});
          progress.state = 'UPLOAD_COMPLETE';
          await saveReport();
        }
      }
      // Finish reserving/uploading all remaining files before waiting for Apple.
      for (const {imagePath, image, file, family, progress, resumed} of processingQueue) {
        let complete = false;
        for (let attempt = 0; attempt < 90; attempt++) {
          const observed = await get(imagePath, 'appScreenshots');
          Object.assign(progress, screenshotStatus(observed));
          const delivery = observed.attributes?.assetDeliveryState?.state;
          if (delivery === 'FAILED') {
            summary.blockers.push('Screenshot processing failed: ' + image.id); break;
          }
          if (delivery === 'COMPLETE') {
            check(observed.attributes?.sourceFileChecksum === file.md5 && observed.attributes?.fileSize === file.bytes.length
              && observed.attributes?.fileName === file.name, 'Uploaded screenshot integrity readback failed.');
            complete = true; break;
          }
          if (attempt % 10 === 0) await saveReport();
          await (options.sleep ?? (ms => new Promise(r => setTimeout(r, ms))))(2000);
        }
        if (complete) summary.preparedScreenshots.push({family, name:file.name, id:image.id, reused:false, resumed, md5:file.md5});
        else summary.blockers.push('Screenshot processing remains incomplete after bounded polling: ' + image.id);
        await saveReport();
      }
      summary.screenshotsPrepared = summary.preparedScreenshots.length === media.length;
      summary.prepared = summary.distribution.ready === true && summary.screenshotsPrepared;
    }
    await saveReport(); return summary;
  } catch (error) {
    const safe = error instanceof RegistrationError ? error : new RegistrationError('Registration preparation failed; private details withheld.');
    summary.error = safe.message; if (safe.diagnostic) summary.diagnostic = safe.diagnostic; await saveReport(); throw safe;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  registerApp(process.env).then(summary => console.log(JSON.stringify(summary, null, 2))).catch(error => {
    console.error(error instanceof RegistrationError ? error.message : 'Registration failed; details withheld.'); process.exitCode = 1;
  });
}
