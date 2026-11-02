import { createPushSender, createWorker } from "./core.mjs";

const env = Object.fromEntries([
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "CARCAR_PUSH_WORKER_SECRET",
  "APNS_KEY_ID",
  "APNS_TEAM_ID",
  "APNS_PRIVATE_KEY",
  "APNS_TOPIC",
  "FCM_SERVICE_ACCOUNT_JSON",
].map((key) => [key, Deno.env.get(key)]));
const base = env.SUPABASE_URL;
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY;
async function rpc(name: string, args: Record<string, unknown>) {
  if (
    !base || !serviceKey ||
    !["claim_push_jobs", "prepare_push_delivery", "finish_push_job"].includes(name)
  ) {
    throw new Error("Worker database unavailable");
  }
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(10000),
    headers: {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error("Worker database request failed");
  return response.json();
}
let apnsClient: Deno.HttpClient | undefined;
const providerFetch: typeof fetch = (input, init) => {
  const host = new URL(String(input)).hostname;
  if (host === "api.push.apple.com" || host === "api.sandbox.push.apple.com") {
    apnsClient ??= Deno.createHttpClient({ http1: false, http2: true });
    return fetch(input, { ...init, client: apnsClient });
  }
  return fetch(input, init);
};
Deno.serve(
  createWorker({
    secret: env.CARCAR_PUSH_WORKER_SECRET,
    rpc,
    send: createPushSender(env, providerFetch),
  }),
);
