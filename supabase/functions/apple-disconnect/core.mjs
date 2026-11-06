// Credentials exist only for this request. This function never deletes application data.
const encoder = new TextEncoder();
const apple = "https://appleid.apple.com";
const encode = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
const jsonPart = (value) => encode(encoder.encode(JSON.stringify(value)));
const decode = (value) => {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid encoding");
  return Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/")), c => c.charCodeAt(0));
};
class Failure extends Error {
  constructor(status, code) { super(code); this.status = status; }
}
const fail = (status, code) => { throw new Failure(status, code); };
const verification = () => fail(409, "apple_verification_failed");
const tokenString = (value) => typeof value === "string" && value.length > 0 && value.length <= 16384;

async function readBounded(message, limit, signal) {
  if (signal?.aborted || Number(message.headers.get("content-length")) > limit) {
    void message.body?.cancel().catch(() => {});
    throw new Error("Body unavailable");
  }
  if (!message.body) return "";
  const reader = message.body.getReader();
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal?.addEventListener("abort", cancel, { once: true });
  let size = 0;
  const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (signal?.aborted) throw new Error("Timeout");
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new Error("Body too large");
      chunks.push(value);
    }
  } catch (error) {
    void reader.cancel().catch(() => {});
    throw error;
  } finally {
    signal?.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

async function bounded(operation, timeoutMs, controller = new AbortController()) {
  let timer;
  try {
    return await Promise.race([
      operation(controller.signal),
      new Promise((_, reject) => {
        timer = setTimeout(() => { controller.abort(); reject(new Error("Timeout")); }, timeoutMs);
      }),
    ]);
  } finally { clearTimeout(timer); }
}

export function createAppleDisconnect(env, fetcher = fetch, now = () => Date.now(), timeoutMs = 10000) {
  async function request(url, init, limit = 65536) {
    return bounded(async (signal) => {
      const response = await fetcher(url, { ...init, signal, redirect: "error" });
      if (response.status >= 300 && response.status < 400 || response.redirected) {
        throw new Error("Redirect rejected");
      }
      const body = await readBounded(response, limit, signal);
      return { status: response.status, body };
    }, timeoutMs);
  }
  async function clientSecret(clientId) {
    try {
      if (!/^[A-Z0-9]{10}$/.test(env.APPLE_SIGN_IN_TEAM_ID ?? "") ||
        !/^[A-Z0-9]{10}$/.test(env.APPLE_SIGN_IN_KEY_ID ?? "") ||
        clientId !== "com.kang88.carcar" ||
        typeof env.APPLE_SIGN_IN_PRIVATE_KEY !== "string" ||
        env.APPLE_SIGN_IN_PRIVATE_KEY.length > 8192) throw new Error("Configuration");
      const der = Uint8Array.from(atob(env.APPLE_SIGN_IN_PRIVATE_KEY
        .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "")), c => c.charCodeAt(0));
      const key = await crypto.subtle.importKey("pkcs8", der,
        { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
      const iat = Math.floor(now() / 1000);
      const input = `${jsonPart({ alg: "ES256", kid: env.APPLE_SIGN_IN_KEY_ID })}.${jsonPart({
        iss: env.APPLE_SIGN_IN_TEAM_ID, iat, exp: iat + 300, aud: apple, sub: clientId,
      })}`;
      const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(input));
      return `${input}.${encode(signature)}`;
    } catch { fail(503, "apple_not_configured"); }
  }
  async function verify(token, rawNonce, subject, clientId) {
    let parts, header, claims;
    try {
      if (!tokenString(token)) verification();
      parts = token.split(".");
      if (parts.length !== 3) verification();
      header = JSON.parse(new TextDecoder().decode(decode(parts[0])));
      claims = JSON.parse(new TextDecoder().decode(decode(parts[1])));
      if (header.alg !== "RS256" || typeof header.kid !== "string" || header.kid.length > 256) verification();
    } catch { verification(); }
    const keysResponse = await request(`${apple}/auth/keys`, { method: "GET" });
    if (keysResponse.status !== 200) fail(502, "apple_unavailable");
    try {
      const keys = JSON.parse(keysResponse.body).keys;
      if (!Array.isArray(keys)) verification();
      const matches = keys.filter(key => key.kid === header.kid && key.kty === "RSA" &&
        key.alg === "RS256" && key.use === "sig");
      if (matches.length !== 1) verification();
      const key = await crypto.subtle.importKey("jwk", matches[0],
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
      if (!await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, decode(parts[2]),
        encoder.encode(`${parts[0]}.${parts[1]}`))) verification();
      const seconds = Math.floor(now() / 1000);
      const digest = await crypto.subtle.digest("SHA-256", encoder.encode(rawNonce));
      const nonce = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, "0")).join("");
      if (claims.iss !== apple || claims.aud !== clientId ||
        !Number.isSafeInteger(claims.iat) || !Number.isSafeInteger(claims.exp) ||
        claims.iat > seconds + 60 || claims.iat < seconds - 600 ||
        claims.exp <= seconds || claims.exp <= claims.iat || claims.nonce !== nonce ||
        typeof claims.sub !== "string" || !claims.sub) verification();
    } catch { verification(); }
    if (claims.sub !== subject) fail(409, "apple_identity_mismatch");
  }
  return async (input) => {
    try {
      if (input.method !== "POST" || input.headers.get("content-type")?.split(";")[0].trim() !== "application/json") {
        fail(400, "invalid_request");
      }
      const bearer = input.headers.get("authorization");
      if (!bearer || bearer.length > 16384 || !/^Bearer [A-Za-z0-9._~-]+$/i.test(bearer)) {
        fail(401, "session_invalid");
      }
      let body;
      try { body = JSON.parse(await bounded(signal => readBounded(input, 12288, signal), timeoutMs)); }
      catch { fail(400, "invalid_request"); }
      if (!body || Array.isArray(body) || Object.keys(body).sort().join(",") !== "authorizationCode,rawNonce" ||
        typeof body.authorizationCode !== "string" || body.authorizationCode.length < 1 ||
        body.authorizationCode.length > 8192 || /[\x00-\x20\x7f]/.test(body.authorizationCode) ||
        typeof body.rawNonce !== "string" || !/^[a-f0-9]{64}$/.test(body.rawNonce)) fail(400, "invalid_request");
      let base;
      try {
        base = new URL(env.SUPABASE_URL);
        if (base.protocol !== "https:" || base.username || base.password || base.search || base.hash ||
          base.pathname !== "/" || !env.SUPABASE_ANON_KEY) throw new Error("Configuration");
      } catch { fail(503, "apple_not_configured"); }
      const userResponse = await request(`${base.origin}/auth/v1/user`, {
        method: "GET", headers: { authorization: bearer, apikey: env.SUPABASE_ANON_KEY },
      });
      if (userResponse.status === 401 || userResponse.status === 403) fail(401, "session_invalid");
      if (userResponse.status !== 200) fail(502, "apple_unavailable");
      let user;
      try { user = JSON.parse(userResponse.body); } catch { fail(401, "session_invalid"); }
      if (typeof user?.id !== "string" || !user.id) fail(401, "session_invalid");
      if (!Array.isArray(user.identities)) verification();
      const identities = user.identities.filter(identity => identity?.provider === "apple");
      if (!Array.isArray(identities) || identities.length !== 1) verification();
      const identity = identities[0];
      const subject = identity.identity_data?.sub ?? identity.provider_id;
      if (typeof subject !== "string" || !subject || subject.length > 256 ||
        (identity.provider_id != null && identity.provider_id !== subject)) verification();
      const clientId = env.APPLE_SIGN_IN_CLIENT_ID;
      const secret = await clientSecret(clientId);
      const form = { client_id: clientId, client_secret: secret };
      const tokenResponse = await request(`${apple}/auth/token`, {
        method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ ...form, code: body.authorizationCode, grant_type: "authorization_code" }),
      });
      let tokens;
      try { tokens = JSON.parse(tokenResponse.body); } catch { fail(502, "apple_unavailable"); }
      if (tokenResponse.status === 400 && tokens?.error === "invalid_grant") fail(400, "apple_reauthentication_required");
      if (tokenResponse.status !== 200) fail(502, "apple_unavailable");
      await verify(tokens?.id_token, body.rawNonce, subject, clientId);
      const tokenType = tokenString(tokens.refresh_token) ? "refresh_token" : "access_token";
      if (!tokenString(tokens[tokenType])) verification();
      const revoke = await request(`${apple}/auth/revoke`, {
        method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ ...form, token: tokens[tokenType], token_type_hint: tokenType }),
      });
      if (revoke.status !== 200) fail(502, "apple_unavailable");
      return Response.json({ ok: true }, { headers: { "cache-control": "no-store" } });
    } catch (error) {
      return Response.json({ error: error instanceof Failure ? error.message : "apple_unavailable" }, {
        status: error instanceof Failure ? error.status : 502,
        headers: { "cache-control": "no-store" },
      });
    }
  };
}
