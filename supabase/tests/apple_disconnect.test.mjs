import test from "node:test";
import assert from "node:assert/strict";
import { createAppleDisconnect } from "../functions/apple-disconnect/core.mjs";

const ec = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const rsa = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const jwk = { ...await crypto.subtle.exportKey("jwk", rsa.publicKey), kid: "apple-key", alg: "RS256", use: "sig" };
const pem = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey("pkcs8", ec.privateKey)).toString("base64")}\n-----END PRIVATE KEY-----`;
const now = 1800000000000;
const rawNonce = "a".repeat(64);
const nonce = Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rawNonce))).toString("hex");
const env = { SUPABASE_URL: "https://project.supabase.co", SUPABASE_ANON_KEY: "anon-public",
  APPLE_SIGN_IN_TEAM_ID: "ABCDEFGHIJ", APPLE_SIGN_IN_KEY_ID: "KLMNOPQRST",
  APPLE_SIGN_IN_PRIVATE_KEY: pem, APPLE_SIGN_IN_CLIENT_ID: "com.kang88.carcar" };
const part = value => Buffer.from(JSON.stringify(value)).toString("base64url");
async function signed(claims = {}, header = {}) {
  const input = `${part({ alg: "RS256", kid: "apple-key", ...header })}.${part({
    iss: "https://appleid.apple.com", aud: "com.kang88.carcar", sub: "apple-user",
    iat: now / 1000, exp: now / 1000 + 300, nonce, ...claims,
  })}`;
  return `${input}.${Buffer.from(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", rsa.privateKey,
    new TextEncoder().encode(input))).toString("base64url")}`;
}
function input(body = { authorizationCode: "fresh-code", rawNonce }, headers = {}, method = "POST") {
  return new Request("https://project.supabase.co/functions/v1/apple-disconnect", {
    method, headers: { "content-type": "application/json", authorization: "Bearer user.session", ...headers },
    ...(method === "GET" ? {} : { body: typeof body === "string" ? body : JSON.stringify(body) }),
  });
}
async function fixture(options = {}) {
  const calls = [];
  const jwt = options.jwt ?? await signed(options.claims, options.header);
  const handler = createAppleDisconnect({ ...env, ...options.env }, async (url, init) => {
    calls.push({ url, init });
    assert.equal(init.redirect, "error");
    assert.ok(init.signal instanceof AbortSignal);
    if (options.fetch) {
      const result = await options.fetch(url, init);
      if (result) return result;
    }
    if (url.endsWith("/auth/v1/user")) return Response.json(options.user ?? {
      id: "supabase-user", identities: [{ provider: "apple", provider_id: "apple-user", identity_data: { sub: "apple-user" } }],
    }, { status: options.authStatus ?? 200 });
    if (url.endsWith("/auth/token")) return Response.json(options.tokens ?? { id_token: jwt, refresh_token: "refresh-secret", access_token: "access-secret" });
    if (url.endsWith("/auth/keys")) return Response.json({ keys: options.keys ?? [jwk] });
    if (url.endsWith("/auth/revoke")) return new Response("", { status: options.revokeStatus ?? 200 });
    assert.fail(`Unexpected URL: ${url}`);
  }, () => now, options.timeoutMs ?? 1000);
  return { handler, calls };
}
async function errorIs(fixture, request, status, code) {
  const response = await fixture.handler(request);
  assert.equal(response.status, status);
  assert.deepEqual(await response.json(), { error: code });
  assert.ok(!fixture.calls.some(call => call.url.endsWith("/auth/revoke")));
}

test("verified identity revokes refresh token; no database calls or user metadata trust", async () => {
  const f = await fixture();
  const response = await f.handler(input());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(f.calls.map(c => new URL(c.url).pathname), ["/auth/v1/user", "/auth/token", "/auth/keys", "/auth/revoke"]);
  assert.equal(f.calls[0].init.headers.authorization, "Bearer user.session");
  assert.equal(f.calls[0].init.headers.apikey, "anon-public");
  const exchange = f.calls[1].init.body;
  assert.equal(exchange.get("grant_type"), "authorization_code");
  assert.equal(exchange.get("code"), "fresh-code");
  const secret = exchange.get("client_secret").split(".");
  const claims = JSON.parse(Buffer.from(secret[1], "base64url"));
  assert.deepEqual(claims, { iss: env.APPLE_SIGN_IN_TEAM_ID, iat: now / 1000, exp: now / 1000 + 300, aud: "https://appleid.apple.com", sub: "com.kang88.carcar" });
  assert.ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, ec.publicKey,
    Buffer.from(secret[2], "base64url"), new TextEncoder().encode(`${secret[0]}.${secret[1]}`)));
  const revoke = f.calls[3].init.body;
  assert.equal(revoke.get("token"), "refresh-secret");
  assert.equal(revoke.get("token_type_hint"), "refresh_token");
  assert.equal(revoke.get("client_id"), "com.kang88.carcar");
});

test("access token fallback and provider_id-only identity", async () => {
  const f = await fixture({ tokens: { id_token: await signed(), access_token: "access-secret" },
    user: { id: "u", identities: [{ provider: "apple", provider_id: "apple-user" }] } });
  assert.equal((await f.handler(input())).status, 200);
  assert.equal(f.calls.at(-1).init.body.get("token_type_hint"), "access_token");
});

test("missing/malformed bearer makes no external calls", async () => {
  for (const authorization of ["", "Basic abc", "Bearer bad token"]) {
    const f = await fixture();
    await errorIs(f, input(undefined, { authorization }), 401, "session_invalid");
    assert.equal(f.calls.length, 0);
  }
});

test("invalid requests and bounded payloads make no external calls", async () => {
  for (const body of ["{", null, [], {}, { authorizationCode: "x", rawNonce, userId: "other" },
    { authorizationCode: "x", rawNonce: "A".repeat(64) }, { authorizationCode: "x".repeat(8193), rawNonce },
    { authorizationCode: "x\n", rawNonce }, "x".repeat(13000)]) {
    const f = await fixture();
    await errorIs(f, input(body), 400, "invalid_request");
    assert.equal(f.calls.length, 0);
  }
  for (const request of [input(undefined, {}, "GET"), input(undefined, { "content-type": "text/plain" })]) {
    const f = await fixture(); await errorIs(f, request, 400, "invalid_request"); assert.equal(f.calls.length, 0);
  }
});

test("invalid session stops before Apple", async () => {
  const f = await fixture({ authStatus: 401 });
  await errorIs(f, input(), 401, "session_invalid"); assert.equal(f.calls.length, 1);
});

test("missing or conflicting Apple identity never trusts metadata or identity UUID", async () => {
  for (const identities of [[], [{ provider: "apple", id: "apple-user" }],
    [{ provider: "apple", provider_id: "other", identity_data: { sub: "apple-user" } }]]) {
    const f = await fixture({ user: { id: "u", identities, user_metadata: { sub: "apple-user" } } });
    await errorIs(f, input(), 409, "apple_verification_failed"); assert.equal(f.calls.length, 1);
  }
});

test("different Apple account cannot revoke", async () => {
  const f = await fixture({ claims: { sub: "other-user" } });
  await errorIs(f, input(), 409, "apple_identity_mismatch");
});

test("signed issuer audience time nonce and subject claims validated", async () => {
  for (const claims of [{ iss: "https://evil.example" }, { aud: "other-app" }, { nonce: "bad" },
    { iat: now / 1000 + 61 }, { iat: now / 1000 - 601 }, { exp: now / 1000 },
    { exp: "9999999999" }, { sub: "" }]) {
    await errorIs(await fixture({ claims }), input(), 409, "apple_verification_failed");
  }
});

test("invalid signatures algorithms and JWKS never revoke", async () => {
  const jwt = await signed();
  for (const options of [{ jwt: `${jwt.slice(0, jwt.lastIndexOf(".") + 1)}AAAA` },
    { header: { alg: "none" } }, { keys: [] }, { keys: [jwk, jwk] }, { jwt: "bad" }]) {
    await errorIs(await fixture(options), input(), 409, "apple_verification_failed");
  }
});

test("missing Apple settings or malformed private key is configured error", async () => {
  for (const overrides of [{ APPLE_SIGN_IN_KEY_ID: undefined }, { APPLE_SIGN_IN_PRIVATE_KEY: "invalid-secret" },
    { APPLE_SIGN_IN_CLIENT_ID: "other-app" }, { SUPABASE_URL: "https://evil.example/?url=other" }]) {
    const f = await fixture({ env: overrides });
    await errorIs(f, input(), 503, "apple_not_configured");
    assert.ok(f.calls.length <= 1);
  }
});

test("invalid grant requires reauthentication; never interprets code reuse as success", async () => {
  const f = await fixture({ fetch: url => url.endsWith("/auth/token") ? Response.json({ error: "invalid_grant", secret: "DO_NOT_LEAK" }, { status: 400 }) : null });
  await errorIs(f, input(), 400, "apple_reauthentication_required");
});

test("network redirect timeout and oversize failures are sanitized", async () => {
  for (const fetch of [() => { throw new Error("SECRET_TOKEN"); },
    () => new Response("", { status: 302, headers: { location: "https://evil.example" } }),
    () => new Response("x".repeat(65537)),
    () => new Response("", { headers: { "content-length": "9999999" } }),
    () => new Promise(() => {}),
    () => new Response(new ReadableStream({ start() {} })),
  ]) {
    await errorIs(await fixture({ fetch, timeoutMs: 20 }), input(), 502, "apple_unavailable");
  }
});

test("revocation HTTP failure never reports success", async () => {
  const f = await fixture({ revokeStatus: 400 });
  const response = await f.handler(input());
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "apple_unavailable" });
});

test("successful exchange without a revoke token fails closed", async () => {
  await errorIs(await fixture({ tokens: { id_token: await signed() } }), input(), 409, "apple_verification_failed");
});
