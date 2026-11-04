// Read-only by default. ENSURE_BRANDING=true corrects only the known old brand
// on this app's editable metadata and internal group; it never sends invitations.
import {createPrivateKey, sign} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const origin = 'https://api.appstoreconnect.apple.com';
const appId = '6829616379';
const bundleId = 'com.kang88.carcar';
const appName = '차자리';
const groupName = '차자리 내부 테스트';
const oldNames = new Set(['차곡', '차곡 - 가족 주차 기록']);
const idPattern = /^[A-Za-z0-9-]+$/;
export class BrandingError extends Error {}
const requireValue = (condition, message) => { if (!condition) throw new BrandingError(message); };

export function safeBrandingUrl(path) {
  let url;
  try { url = new URL(path, origin); } catch { throw new BrandingError('Invalid Apple API destination.'); }
  requireValue(url.origin === origin && !url.username && !url.password && !url.hash
    && /^\/v1\/(apps\/6829616379(?:\/(?:appInfos|betaGroups))?|appInfos\/[A-Za-z0-9-]+\/appInfoLocalizations|(?:appInfoLocalizations|betaGroups)\/[A-Za-z0-9-]+)$/.test(url.pathname), 'Unexpected Apple API destination.');
  return url;
}

function resource(data, type, id) {
  requireValue(data?.type === type && typeof data.id === 'string' && idPattern.test(data.id)
    && (!id || data.id === id) && data.attributes && typeof data.attributes === 'object', 'Unexpected Apple resource identity or attributes.');
  return data;
}

export async function syncAppStoreBranding(env, fetchImpl = fetch) {
  requireValue(!env.CARCAR_APP_ID || env.CARCAR_APP_ID === appId, 'This helper is restricted to the configured carcar app.');
  for (const name of ['APP_STORE_CONNECT_API_KEY_P8_BASE64', 'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_KEY_ID']) {
    requireValue(Boolean(env[name]), 'Missing App Store Connect input: ' + name);
  }
  requireValue(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID), 'Invalid App Store Connect key identifier.');
  requireValue(/^[0-9a-f-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID), 'Invalid App Store Connect issuer identifier.');
  let apiKey;
  try { apiKey = createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64, 'base64')); }
  catch { throw new BrandingError('Invalid App Store Connect private key.'); }
  requireValue(apiKey.asymmetricKeyType === 'ec' && apiKey.asymmetricKeyDetails?.namedCurve === 'prime256v1', 'App Store Connect requires an ES256 API key.');
  const ensure = env.ENSURE_BRANDING === 'true';
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  function token() {
    const now = Math.floor(Date.now() / 1000);
    const message = encode({alg: 'ES256', kid: env.APP_STORE_CONNECT_KEY_ID, typ: 'JWT'}) + '.'
      + encode({iss: env.APP_STORE_CONNECT_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'});
    return message + '.' + sign('sha256', Buffer.from(message), {key: apiKey, dsaEncoding: 'ieee-p1363'}).toString('base64url');
  }
  const writes = [], allowedWrites = new Map();
  async function request(path, method = 'GET', body) {
    const url = safeBrandingUrl(path);
    if (method !== 'GET') {
      requireValue(ensure && method === 'PATCH' && !url.search
        && allowedWrites.get(url.pathname) === JSON.stringify(body), 'Only inspected name-only updates are permitted.');
      writes.push(method + ' ' + url.pathname);
    }
    let response;
    try {
      response = await fetchImpl(url, {method, redirect: 'error', headers: {Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json'},
        body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20_000)});
    } catch { throw new BrandingError('Apple API request failed or timed out.'); }
    // Do not echo arbitrary provider error bodies, tokens, or request headers.
    if (!response.ok) throw new BrandingError('Apple API returned HTTP ' + response.status + ' for ' + method + ' ' + url.pathname + '.');
    try { return await response.json(); }
    catch { throw new BrandingError('Apple API returned an unreadable response.'); }
  }
  async function list(path, type) {
    const pathname = safeBrandingUrl(path).pathname, items = [], visited = new Set(), ids = new Set();
    while (path) {
      const url = safeBrandingUrl(path);
      requireValue(url.pathname === pathname && !visited.has(url.href) && visited.size < 20, 'Unexpected Apple API pagination.');
      visited.add(url.href);
      const page = await request(url.href);
      requireValue(Array.isArray(page?.data), 'Apple API returned an invalid list.');
      for (const item of page.data) {
        resource(item, type);
        requireValue(!ids.has(item.id), 'Apple API returned duplicate resources.');
        ids.add(item.id);
        items.push(item);
      }
      path = page.links?.next;
    }
    return items;
  }
  const appPath = '/v1/apps/' + appId + '?fields[apps]=name,bundleId,primaryLocale';
  function checkedApp(data) {
    const app = resource(data, 'apps', appId);
    requireValue(app.attributes.bundleId === bundleId && typeof app.attributes.name === 'string'
      && typeof app.attributes.primaryLocale === 'string' && /^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(app.attributes.primaryLocale), 'Unexpected app bundle or primary locale.');
    return app;
  }
  const app = checkedApp((await request(appPath)).data);
  const infos = await list('/v1/apps/' + appId + '/appInfos?fields[appInfos]=state,appStoreState&limit=200', 'appInfos');
  const reports = [];
  for (const info of infos) {
    const state = info.attributes.state ?? info.attributes.appStoreState ?? null;
    const localizations = await list('/v1/appInfos/' + info.id + '/appInfoLocalizations?fields[appInfoLocalizations]=locale,name&limit=200', 'appInfoLocalizations');
    reports.push({id: info.id, state, localizations: localizations.map(item => {
      requireValue(typeof item.attributes.name === 'string' && typeof item.attributes.locale === 'string', 'Invalid app localization.');
      return {id: item.id, locale: item.attributes.locale, nameBefore: item.attributes.name, name: item.attributes.name};
    })});
  }
  const groups = (await list('/v1/apps/' + appId + '/betaGroups?fields[betaGroups]=name,isInternalGroup&limit=200', 'betaGroups'))
    .filter(item => item.attributes.isInternalGroup === true)
    .map(item => ({id: item.id, nameBefore: item.attributes.name, name: item.attributes.name}));
  const summary = {checkedAt: new Date().toISOString(), appId, bundleId, mode: ensure ? 'ensure' : 'read-only',
    app: {nameBefore: app.attributes.name, name: app.attributes.name, primaryLocale: app.attributes.primaryLocale},
    appInfos: reports, groups, writes, blockers: [], ready: false};
  const block = message => summary.blockers.push(message);
  const editable = reports.filter(info => info.state === 'PREPARE_FOR_SUBMISSION');
  if (editable.length > 1) block('Multiple editable app information records require review.');
  if (!oldNames.has(app.attributes.name) && app.attributes.name !== appName) block('Unexpected current app name; no automatic rename.');
  const selected = editable.length === 1 ? editable[0] : null;
  const candidates = selected?.localizations.filter(item => item.locale === app.attributes.primaryLocale || item.locale === 'ko' || item.locale === 'ko-KR') ?? [];
  if (selected?.localizations.some(item => !candidates.includes(item) && oldNames.has(item.name))) block('Known old name exists in an unexpected locale; review is required.');
  if (selected && !candidates.some(item => item.locale === app.attributes.primaryLocale)) block('Editable primary localization was not found.');
  if (!selected && app.attributes.name !== appName) block('No PREPARE_FOR_SUBMISSION app information is available for renaming.');
  const planned = [];
  for (const item of candidates) {
    if (item.name === appName) continue;
    if (!oldNames.has(item.name)) { block('Unexpected localization name for ' + item.locale + '; no automatic rename.'); continue; }
    planned.push({type: 'appInfoLocalizations', item, name: appName});
  }
  const matchingGroups = groups.filter(item => ['차곡 내부 테스트', groupName].includes(item.name));
  if (matchingGroups.length !== 1) block('Expected exactly one known internal testing group.');
  for (const item of matchingGroups) if (item.name !== groupName) planned.push({type: 'betaGroups', item, name: groupName});
  // All preconditions are evaluated before any mutation.
  if (summary.blockers.length === 0 && ensure) {
    for (const {type, item, name} of planned) {
      const path = '/v1/' + type + '/' + item.id;
      const body = {data: {type, id: item.id, attributes: {name}}};
      allowedWrites.set(path, JSON.stringify(body));
      await request(path, 'PATCH', body);
      const verified = resource((await request(path)).data, type, item.id);
      requireValue(verified.attributes.name === name, 'Apple did not confirm the requested name change.');
      if (type === 'appInfoLocalizations') requireValue(verified.attributes.locale === item.locale, 'Apple localization changed unexpectedly.');
      else requireValue(verified.attributes.isInternalGroup === true, 'Apple group changed unexpectedly.');
      item.name = verified.attributes.name;
    }
    const verifiedApp = checkedApp((await request(appPath)).data);
    requireValue(verifiedApp.attributes.primaryLocale === app.attributes.primaryLocale, 'Apple primary locale changed unexpectedly.');
    summary.app.name = verifiedApp.attributes.name;
  }
  summary.ready = summary.blockers.length === 0 && summary.app.name === appName
    && candidates.every(item => item.name === appName) && matchingGroups.every(item => item.name === groupName);
  if (!summary.ready && summary.blockers.length === 0) block(ensure ? 'App or group name readback is not yet the requested brand.' : 'Known old brand remains; read-only mode made no changes.');
  if (env.APP_STORE_BRANDING_SUMMARY_PATH) await writeFile(env.APP_STORE_BRANDING_SUMMARY_PATH, JSON.stringify(summary, null, 2) + '\n');
  return summary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  syncAppStoreBranding(process.env).then(summary => {
    console.log(JSON.stringify(summary, null, 2));
    if (summary.mode === 'ensure' && !summary.ready) process.exitCode = 2;
  }).catch(error => {
    console.error(error instanceof BrandingError ? error.message : 'App Store branding check failed; details were withheld.');
    process.exitCode = 1;
  });
}
