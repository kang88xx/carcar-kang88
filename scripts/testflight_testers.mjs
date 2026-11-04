// Keep the 차자리 internal TestFlight group ready for every upload.
// Read-only by default; ENSURE=true adds the build to the internal group,
// turns on automatic distribution for future builds and resends pending
// invitations for the required testers. Secrets never reach the output.
import {createPrivateKey, sign} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const origin = 'https://api.appstoreconnect.apple.com';
const defaultAppId = '6829616379';
const defaultTesters = ['kslee324@gmail.com'];
class TesterError extends Error {}
const requireValue = (condition, message) => { if (!condition) throw new TesterError(message); };

export function safeApiUrl(path) {
  const url = new URL(path, origin);
  requireValue(url.origin === origin && !url.username && !url.password
    && /^\/v1\/(apps|betaGroups|betaTesters|betaTesterInvitations|builds)(\/|$)/.test(url.pathname), 'Unexpected Apple API destination.');
  return url;
}

export function parseTesters(value) {
  const emails = (value ?? '').split(',').map(item => item.trim().toLowerCase()).filter(Boolean);
  const list = emails.length ? emails : defaultTesters;
  for (const email of list) requireValue(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), 'Invalid tester email.');
  return list;
}

export function pickInternalGroup(groups) {
  const internal = groups.filter(group => group.attributes?.isInternalGroup === true);
  requireValue(internal.length > 0, 'The app has no internal TestFlight group.');
  return internal.sort((a, b) => (b.attributes.hasAccessToAllBuilds ? 1 : 0) - (a.attributes.hasAccessToAllBuilds ? 1 : 0)
    || Date.parse(a.attributes.createdDate ?? 0) - Date.parse(b.attributes.createdDate ?? 0))[0];
}

export async function ensureTesters(env, fetchImpl = fetch) {
  for (const name of ['APP_STORE_CONNECT_API_KEY_P8_BASE64', 'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_KEY_ID']) {
    requireValue(Boolean(env[name]), 'Missing App Store Connect input: ' + name);
  }
  requireValue(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID), 'Invalid App Store Connect key identifier.');
  requireValue(/^[0-9a-f-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID), 'Invalid App Store Connect issuer identifier.');
  const appId = env.CARCAR_APP_ID || defaultAppId;
  requireValue(/^\d+$/.test(appId), 'Invalid app identifier.');
  const buildNumber = env.BUILD_NUMBER ? String(env.BUILD_NUMBER).trim() : '';
  requireValue(!buildNumber || /^[1-9][0-9]*$/.test(buildNumber), 'Invalid build number.');
  const ensure = env.ENSURE === 'true';
  const testers = parseTesters(env.TESTER_EMAILS);
  const apiKey = createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64, 'base64'));
  requireValue(apiKey.asymmetricKeyType === 'ec' && apiKey.asymmetricKeyDetails?.namedCurve === 'prime256v1', 'App Store Connect requires an ES256 API key.');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  function token() {
    const now = Math.floor(Date.now() / 1000);
    const message = encode({alg: 'ES256', kid: env.APP_STORE_CONNECT_KEY_ID, typ: 'JWT'}) + '.' + encode({iss: env.APP_STORE_CONNECT_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1'});
    return message + '.' + sign('sha256', Buffer.from(message), {key: apiKey, dsaEncoding: 'ieee-p1363'}).toString('base64url');
  }
  const writes = [];
  async function request(path, method = 'GET', body) {
    const url = safeApiUrl(path);
    if (method !== 'GET') {
      requireValue(ensure, 'Write requested in read-only mode.');
      const allowed = (method === 'PATCH' && /^\/v1\/betaGroups\/[A-Za-z0-9-]+$/.test(url.pathname))
        || (method === 'POST' && /^\/v1\/betaGroups\/[A-Za-z0-9-]+\/relationships\/(builds|betaTesters)$/.test(url.pathname))
        || (method === 'POST' && url.pathname === '/v1/betaTesterInvitations');
      requireValue(allowed, 'Only group distribution and invitation writes are permitted.');
      writes.push(method + ' ' + url.pathname);
    }
    let response;
    try {
      response = await fetchImpl(url, {method, redirect: 'error', headers: {Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json'}, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20_000)});
    } catch { throw new TesterError('Apple API request failed or timed out.'); }
    if (!response.ok) {
      let detail = '';
      try { detail = (await response.json()).errors?.map(item => [item.code, item.title, item.detail].filter(Boolean).join(': ')).join('; ') ?? ''; } catch {}
      throw new TesterError('Apple API returned HTTP ' + response.status + ' for ' + method + ' ' + url.pathname + (detail ? ' (' + detail + ')' : '') + '.');
    }
    if (response.status === 204) return null;
    try { return await response.json(); }
    catch { throw new TesterError('Apple API returned an unreadable response.'); }
  }
  async function list(path) {
    const result = [], visited = new Set();
    while (path) {
      requireValue(!visited.has(path) && visited.size < 20, 'Apple API pagination did not terminate.');
      visited.add(path);
      const page = await request(path);
      requireValue(Array.isArray(page?.data), 'Apple API returned an invalid list.');
      result.push(...page.data);
      path = page.links?.next;
    }
    return result;
  }

  const group = pickInternalGroup(await list('/v1/apps/' + appId + '/betaGroups?limit=200'));
  let hasAccessToAllBuilds = group.attributes.hasAccessToAllBuilds === true;
  let distributionEnabled = false, distributionError = null;
  if (ensure && !hasAccessToAllBuilds) {
    // Apple refuses this flag on some internal groups; the build is still added explicitly below.
    try {
      await request('/v1/betaGroups/' + group.id, 'PATCH', {data: {type: 'betaGroups', id: group.id, attributes: {hasAccessToAllBuilds: true}}});
      hasAccessToAllBuilds = true;
      distributionEnabled = true;
    } catch (error) {
      if (!(error instanceof TesterError)) throw error;
      distributionError = error.message;
    }
  }

  let build = null;
  const builds = await list('/v1/builds?filter[app]=' + appId + (buildNumber ? '&filter[version]=' + buildNumber : '') + '&sort=-uploadedDate&limit=5');
  build = builds[0] ?? null;
  let groupContainsBuild = false, buildAdded = false;
  if (build) {
    const groupBuilds = await list('/v1/betaGroups/' + group.id + '/relationships/builds?limit=200');
    groupContainsBuild = groupBuilds.some(item => item.id === build.id);
    if (ensure && !groupContainsBuild && build.attributes?.processingState === 'VALID') {
      await request('/v1/betaGroups/' + group.id + '/relationships/builds', 'POST', {data: [{type: 'builds', id: build.id}]});
      groupContainsBuild = true;
      buildAdded = true;
    }
  }

  const members = await list('/v1/betaGroups/' + group.id + '/betaTesters?limit=200');
  const testerReports = [];
  for (const email of testers) {
    const found = (await list('/v1/betaTesters?filter[email]=' + encodeURIComponent(email) + '&fields[betaTesters]=email,state,inviteType&limit=5'))
      .filter(item => (item.attributes?.email ?? '').toLowerCase() === email);
    const tester = found[0] ?? null;
    const report = {email, exists: Boolean(tester), inGroup: false, state: tester?.attributes?.state ?? null, addedToGroup: false, invitationResent: false};
    if (tester) {
      report.inGroup = members.some(item => item.id === tester.id);
      if (ensure && !report.inGroup) {
        await request('/v1/betaGroups/' + group.id + '/relationships/betaTesters', 'POST', {data: [{type: 'betaTesters', id: tester.id}]});
        report.inGroup = true;
        report.addedToGroup = true;
      }
      if (ensure && ['NOT_INVITED', 'INVITED'].includes(report.state ?? '')) {
        await request('/v1/betaTesterInvitations', 'POST', {data: {type: 'betaTesterInvitations', relationships: {app: {data: {type: 'apps', id: appId}}, betaTester: {data: {type: 'betaTesters', id: tester.id}}}}});
        report.invitationResent = true;
      }
    }
    testerReports.push(report);
  }

  const summary = {
    checkedAt: new Date().toISOString(), appId, mode: ensure ? 'ensure' : 'read-only',
    group: {id: group.id, name: group.attributes.name, isInternalGroup: true, hasAccessToAllBuilds, distributionEnabledNow: distributionEnabled, distributionError, memberCount: members.length},
    build: build ? {id: build.id, version: build.attributes?.version, processingState: build.attributes?.processingState, expired: build.attributes?.expired, groupContainsBuild, addedNow: buildAdded} : null,
    testers: testerReports,
    writes,
  };
  const missing = testerReports.filter(item => !item.exists || !item.inGroup).map(item => item.email);
  summary.ready = missing.length === 0 && (build == null || groupContainsBuild);
  summary.missingTesters = missing;
  if (env.TESTFLIGHT_SUMMARY_PATH) await writeFile(env.TESTFLIGHT_SUMMARY_PATH, JSON.stringify(summary, null, 2) + '\n');
  return summary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  ensureTesters(process.env).then(summary => {
    console.log(JSON.stringify(summary, null, 2));
    if (!summary.ready) process.exitCode = 2;
  }).catch(error => {
    console.error(error instanceof TesterError ? error.message : 'TestFlight tester check failed; details were withheld.');
    process.exitCode = 1;
  });
}
