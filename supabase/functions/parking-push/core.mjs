// Dependency-free transport used by the Edge entrypoint and local regression tests.
const textEncoder = new TextEncoder();
const base64url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
const encodeJson = (value) => base64url(textEncoder.encode(JSON.stringify(value)));
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function jwt(header, claims, pem, algorithm) {
  if (typeof pem !== "string" || !pem.includes("-----BEGIN PRIVATE KEY-----")) {
    throw new Error("Push signing key unavailable");
  }
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, algorithm, false, ["sign"]);
  const input = `${encodeJson(header)}.${encodeJson(claims)}`;
  const signature = await crypto.subtle.sign(
    algorithm.name === "ECDSA" ? { name: "ECDSA", hash: "SHA-256" } : algorithm,
    key,
    textEncoder.encode(input),
  );
  return `${input}.${base64url(signature)}`;
}

export async function authorized(provided, expected) {
  if (
    typeof expected !== "string" || expected.length < 32 ||
    typeof provided !== "string" || provided.length > 4096
  ) return false;
  const [a, b] = await Promise.all(
    [provided, expected].map((v) => crypto.subtle.digest("SHA-256", textEncoder.encode(v))),
  );
  const left = new Uint8Array(a), right = new Uint8Array(b);
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference === 0;
}

export function retrySeconds(response, now = Date.now()) {
  const value = response.headers.get("retry-after");
  const parsed = value && /^\d+$/.test(value)
    ? Number(value)
    : value
    ? Math.ceil((Date.parse(value) - now) / 1000)
    : 60;
  return Math.max(30, Math.min(Number.isFinite(parsed) ? parsed : 60, 3600));
}

export function classifyResponse(provider, status, body) {
  if (status >= 200 && status < 300) return "sent";
  if (
    provider === "apns" && (body?.reason === "Unregistered" ||
      body?.reason === "BadDeviceToken" || body?.reason === "DeviceTokenNotForTopic")
  ) return "invalid_token";
  if (
    provider === "fcm" &&
    body?.error?.details?.some((x) =>
      x?.["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError" &&
      x.errorCode === "UNREGISTERED"
    )
  ) return "invalid_token";
  if (status === 408 || status === 429 || status >= 500) return "retry";
  if (status === 401 || status === 403) return "configuration_error";
  return "rejected";
}

export function createPushSender(env, fetcher = fetch, now = () => Date.now()) {
  let apnsCache, fcmCache;
  const request = (url, options) =>
    fetcher(url, {
      ...options,
      redirect: "error",
      signal: AbortSignal.timeout(12000),
    });
  async function apnsBearer() {
    if (apnsCache && apnsCache.expires > now()) return apnsCache.token;
    if (
      !/^[A-Z0-9]{10}$/.test(env.APNS_KEY_ID ?? "") ||
      !/^[A-Z0-9]{10}$/.test(env.APNS_TEAM_ID ?? "") || env.APNS_TOPIC !== "com.kang88.carcar"
    ) {
      throw new Error("APNs configuration unavailable");
    }
    const token = await jwt(
      { alg: "ES256", kid: env.APNS_KEY_ID },
      { iss: env.APNS_TEAM_ID, iat: Math.floor(now() / 1000) },
      env.APNS_PRIVATE_KEY,
      { name: "ECDSA", namedCurve: "P-256" },
    );
    apnsCache = { token, expires: now() + 40 * 60 * 1000 };
    return token;
  }
  async function fcmBearer() {
    if (fcmCache && fcmCache.expires > now()) return fcmCache;
    const account = JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON ?? "{}");
    if (
      !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(account.project_id ?? "") ||
      typeof account.client_email !== "string" ||
      !account.client_email.endsWith(".iam.gserviceaccount.com")
    ) {
      throw new Error("FCM configuration unavailable");
    }
    const seconds = Math.floor(now() / 1000);
    const assertion = await jwt(
      { alg: "RS256", typ: "JWT" },
      {
        iss: account.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: seconds,
        exp: seconds + 3600,
      },
      account.private_key,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    );
    const response = await request("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });
    const data = await response.json();
    if (!response.ok || typeof data.access_token !== "string") {
      throw new Error("FCM authorization failed");
    }
    fcmCache = {
      token: data.access_token,
      project: account.project_id,
      expires: now() + Math.max(0, Math.min(Number(data.expires_in) || 3600, 3600) - 60) * 1000,
    };
    return fcmCache;
  }
  return async (delivery) => {
    if (
      !uuid.test(delivery?.vehicle_id ?? "") || !uuid.test(delivery?.job_id ?? "") ||
      !Number.isSafeInteger(delivery.expires_at)
    ) return { result: "rejected", retrySeconds: 60 };
    const ttl = Math.max(0, Math.min(3600, delivery.expires_at - Math.floor(now() / 1000)));
    if (ttl === 0) return { result: "rejected", retrySeconds: 60 };
    let response;
    try {
      if (delivery.provider === "apns") {
        if (
          !["production", "sandbox"].includes(delivery.environment) ||
          !/^[0-9a-f]{64,200}$/.test(delivery.token ?? "")
        ) return { result: "rejected", retrySeconds: 60 };
        const bearer = await apnsBearer();
        const host = delivery.environment === "production"
          ? "api.push.apple.com"
          : "api.sandbox.push.apple.com";
        response = await request(`https://${host}/3/device/${delivery.token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${bearer}`,
            "apns-topic": env.APNS_TOPIC,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "apns-expiration": String(delivery.expires_at),
            "apns-collapse-id": delivery.vehicle_id,
            "apns-id": delivery.job_id,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            aps: {
              alert: { title: "차자리", body: "가족의 주차 위치가 업데이트됐어요." },
              sound: "default",
              category: "carcar_family",
              "thread-id": delivery.vehicle_id,
            },
            kind: "parking_updated",
            vehicle_id: delivery.vehicle_id,
          }),
        });
      } else if (delivery.provider === "fcm") {
        if (
          delivery.environment !== "production" ||
          !/^[A-Za-z0-9:_-]{32,4096}$/.test(delivery.token ?? "")
        ) return { result: "rejected", retrySeconds: 60 };
        const bearer = await fcmBearer();
        response = await request(
          `https://fcm.googleapis.com/v1/projects/${bearer.project}/messages:send`,
          {
            method: "POST",
            headers: {
              authorization: `Bearer ${bearer.token}`,
              "content-type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: delivery.token,
                data: { kind: "parking_updated", vehicle_id: delivery.vehicle_id },
                android: { ttl: `${ttl}s`, priority: "HIGH", collapse_key: delivery.vehicle_id },
              },
            }),
          },
        );
      } else return { result: "rejected", retrySeconds: 60 };
    } catch (error) {
      // Fixed classification only; upstream error bodies/URLs can contain tokens.
      const configuration = /configuration unavailable|signing key unavailable|authorization failed/
        .test(error?.message ?? "");
      return {
        result: configuration ? "configuration_error" : "retry",
        retrySeconds: configuration ? 900 : 60,
      };
    }
    let body = null;
    try {
      body = await response.json();
    } catch { /* APNs 200 has no JSON body. */ }
    return {
      result: classifyResponse(delivery.provider, response.status, body),
      retrySeconds: retrySeconds(response, now()),
    };
  };
}

export function createWorker({ secret, rpc, send }) {
  return async (request) => {
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
    if (!await authorized(request.headers.get("x-carcar-worker-secret"), secret)) {
      return new Response("Unauthorized", { status: 401 });
    }
    const totals = { claimed: 0, sent: 0, skipped: 0, deferred: 0, failed: 0 };
    try {
      const jobs = await rpc("claim_push_jobs", { p_limit: 10 });
      if (!Array.isArray(jobs) || jobs.length > 20) throw new Error("Invalid claim");
      totals.claimed = jobs.length;
      // Limit outstanding provider requests and finish inside the 2-minute lease.
      let cursor = 0;
      await Promise.all(Array.from({ length: Math.min(4, jobs.length) }, async () => {
        while (cursor < jobs.length) {
          const job = jobs[cursor++];
          try {
            if (!uuid.test(job?.job_id ?? "") || !uuid.test(job?.lease_token ?? "")) {
              throw new Error("Invalid lease");
            }
            const args = { p_job_id: job.job_id, p_lease_token: job.lease_token };
            const delivery = await rpc("prepare_push_delivery", args);
            if (!delivery) {
              totals.skipped++;
              continue;
            }
            const result = await send(delivery);
            const finished = await rpc("finish_push_job", {
              ...args,
              p_result: result.result,
              p_retry_seconds: result.retrySeconds,
            });
            if (!finished) {
              totals.failed++;
              continue;
            }
            if (result.result === "sent") totals.sent++;
            else if (["retry", "configuration_error"].includes(result.result)) totals.deferred++;
            else totals.failed++;
          } catch {
            totals.failed++;
          } // Lease recovery handles interrupted requests.
        }
      }));
      return Response.json(totals);
    } catch {
      return Response.json({ error: "Notification worker unavailable" }, { status: 503 });
    }
  };
}
