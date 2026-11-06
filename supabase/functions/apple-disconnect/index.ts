import { createAppleDisconnect } from "./core.mjs";

const env = Object.fromEntries([
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "APPLE_SIGN_IN_TEAM_ID",
  "APPLE_SIGN_IN_KEY_ID",
  "APPLE_SIGN_IN_PRIVATE_KEY",
  "APPLE_SIGN_IN_CLIENT_ID",
].map((key) => [key, Deno.env.get(key)]));

Deno.serve(createAppleDisconnect(env));
