// Manage App Store Connect *user* invitations for 차자리 internal testers.
// Internal TestFlight testers must be App Store Connect users, so a family
// tester is first invited as a user (limited role, this app only) and then
// added to the internal group by scripts/testflight_testers.mjs.
//
// Read-only by default: reports existing users and pending invitations for
// INVITE_EMAIL and CANCEL_EMAIL. APPLY=true cancels the pending invitation of
// CANCEL_EMAIL (never an accepted user) and sends one to INVITE_EMAIL when that
// address is neither a user nor already invited (RESEND=true replaces a pending
// invitation). Secrets never reach the output.
import {createPrivateKey, sign} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const origin = 'https://api.appstoreconnect.apple.com';
const defaultAppId = '6829616379';
const allowedRoles = new Set(['MARKETING', 'CUSTOMER_SUPPORT', 'SALES', 'DEVELOPER', 'APP_MANAGER']);
class InvitationError extends Error {}
const requireValue = (condition, message) => { if (!condition) throw new InvitationError(message); };

export function safeApiUrl(path) {
  const url = new URL(path, origin);
  requireValue(url.origin === origin && !url.username && !url.password
    && /^\/v1\/(users|userInvitations)(\/|$)/.test(url.pathname), 'Unexpected Apple API destination.');
  return url;
}

export function parseEmail(value, name) {
  const email = (value ?? '').trim().toLowerCase();
  if (!email) return null;
  requireValue(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), 'Invalid ' + name + ' email.');
  return email;
}

export function parseName(value, name) {
  const text = (value ?? '').trim();
  requireValue(text.length >= 1 && text.length <= 40 && !/[<>"\\]/.test(text), 'Invalid ' + name + '.');
  return text;
}

export async function manageInvitations(env, fetchImpl = fetch) {
  for (const name of ['APP_STORE_CONNECT_API_KEY_P8_BASE64', 'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_KEY_ID']) {
    requireValue(Boolean(env[name]), 'Missing App Store Connect input: ' + name);
  }
  requireValue(/^[A-Z0-9]{10}$/.test(env.APP_STORE_CONNECT_KEY_ID), 'Invalid App Store Connect key identifier.');
  requireValue(/^[0-9a-f-]{36}$/i.test(env.APP_STORE_CONNECT_ISSUER_ID), 'Invalid App Store Connect issuer identifier.');
  const appId = env.CARCAR_APP_ID || defaultAppId;
  requireValue(/^\d+$/.test(appId), 'Invalid app identifier.');
  const apply = env.APPLY === 'true';
  const resend = env.RESEND === 'true';
  const inviteEmail = parseEmail(env.INVITE_EMAIL, 'invite');
  const cancelEmail = parseEmail(env.CANCEL_EMAIL, 'cancel');
  requireValue(inviteEmail || cancelEmail, 'Provide INVITE_EMAIL and/or CANCEL_EMAIL.');
  requireValue(!(inviteEmail && cancelEmail && inviteEmail === cancelEmail), 'Invite and cancel emails must differ.');
  const role = (env.INVITE_ROLE || 'MARKETING').trim().toUpperCase();
  requireValue(allowedRoles.has(role), 'Unsupported role; use a limited App Store Connect role.');
  const firstName = inviteEmail ? parseName(env.INVITE_FIRST_NAME, 'first name') : null;
  const lastName = inviteEmail ? parseName(env.INVITE_LAST_NAME, 'last name') : null;

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
      requireValue(apply, 'Write requested in read-only mode.');
      const allowed = (method === 'DELETE' && /^\/v1\/userInvitations\/[A-Za-z0-9-]+$/.test(url.pathname))
        || (method === 'POST' && url.pathname === '/v1/userInvitations');
      requireValue(allowed, 'Only user invitation writes are permitted.');
      writes.push(method + ' ' + url.pathname);
    }
    let response;
    try {
      response = await fetchImpl(url, {method, redirect: 'error', headers: {Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json'}, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20_000)});
    } catch { throw new InvitationError('Apple API request failed or timed out.'); }
    if (!response.ok) {
      let detail = '';
      try { detail = (await response.json()).errors?.map(item => [item.code, item.title, item.detail].filter(Boolean).join(': ')).join('; ') ?? ''; } catch {}
      throw new InvitationError('Apple API returned HTTP ' + response.status + ' for ' + method + ' ' + url.pathname + (detail ? ' (' + detail + ')' : '') + '.');
    }
    if (response.status === 204) return null;
    try { return await response.json(); }
    catch { throw new InvitationError('Apple API returned an unreadable response.'); }
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
  const byEmail = (items, email, field) => items.filter(item => (item.attributes?.[field] ?? '').toLowerCase() === email);
  async function lookup(email) {
    const users = byEmail(await list('/v1/users?filter[username]=' + encodeURIComponent(email) + '&limit=5'), email, 'username');
    const invitations = byEmail(await list('/v1/userInvitations?filter[email]=' + encodeURIComponent(email) + '&limit=5'), email, 'email');
    return {
      email,
      user: users[0] ? {id: users[0].id, roles: users[0].attributes?.roles ?? []} : null,
      invitations: invitations.map(item => ({id: item.id, roles: item.attributes?.roles ?? [], expirationDate: item.attributes?.expirationDate ?? null})),
    };
  }

  const summary = {checkedAt: new Date().toISOString(), appId, mode: apply ? 'apply' : 'read-only', cancel: null, invite: null, writes};
  if (cancelEmail) {
    const state = await lookup(cancelEmail);
    const cancelled = [];
    if (apply && !state.user) {
      for (const invitation of state.invitations) {
        await request('/v1/userInvitations/' + invitation.id, 'DELETE');
        cancelled.push(invitation.id);
      }
    }
    summary.cancel = {...state, cancelledInvitations: cancelled, skippedActiveUser: Boolean(state.user)};
  }
  if (inviteEmail) {
    const state = await lookup(inviteEmail);
    let sent = false, replaced = [];
    if (apply && !state.user) {
      if (state.invitations.length && resend) {
        for (const invitation of state.invitations) {
          await request('/v1/userInvitations/' + invitation.id, 'DELETE');
          replaced.push(invitation.id);
        }
      }
      if (!state.invitations.length || resend) {
        await request('/v1/userInvitations', 'POST', {data: {
          type: 'userInvitations',
          attributes: {email: inviteEmail, firstName, lastName, roles: [role], allAppsVisible: false, provisioningAllowed: false},
          relationships: {visibleApps: {data: [{type: 'apps', id: appId}]}},
        }});
        sent = true;
      }
    }
    summary.invite = {...state, role, invitationSent: sent, replacedInvitations: replaced, alreadyUser: Boolean(state.user), pendingBefore: state.invitations.length};
  }
  summary.ready = (!summary.cancel || summary.cancel.skippedActiveUser || (summary.cancel.invitations.length === 0) || summary.cancel.cancelledInvitations.length > 0)
    && (!summary.invite || summary.invite.alreadyUser || summary.invite.invitationSent || summary.invite.pendingBefore > 0);
  if (env.USER_INVITATIONS_SUMMARY_PATH) await writeFile(env.USER_INVITATIONS_SUMMARY_PATH, JSON.stringify(summary, null, 2) + '\n');
  return summary;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  manageInvitations(process.env).then(summary => {
    console.log(JSON.stringify(summary, null, 2));
    if (!summary.ready) process.exitCode = 2;
  }).catch(error => {
    console.error(error instanceof InvitationError ? error.message : 'User invitation step failed; details were withheld.');
    process.exitCode = 1;
  });
}
