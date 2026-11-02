# Codex project instructions

You are building a Korean-first family-shared apartment parking location app (Flutter iOS+Android).

## Read before coding
Read README.md, docs/PRD.md, docs/ARCHITECTURE.md, docs/SECURITY_AND_COST.md, docs/DECISIONS.md and docs/ROADMAP_AND_QA.md.

## Non-negotiable
- Prioritize Phase 0 through Phase 7 in order. Implement a runnable small vertical slice before adding advanced native platform functionality.
- Keep initial monthly backend cost at $0: Supabase Free, on-device OCR (iOS Vision, Android ML Kit). Do not add paid AI APIs, AWS servers, or billing-enabled infrastructure without explicit approval.
- Never put Supabase service_role keys, push credentials, or other secrets in apps, widgets, Git, or logs.
- Treat a plate number as public-ish identifying data, **not** authorization. Require membership/owner-issued invitation and enforce RLS on all access.
- The server is source of truth for parking records. Never report save success before server confirmation.
- OCR extracts suggestions; user must confirm and may edit fields.
- In-app vehicle icon is shared via vehicle.icon_id. OS launcher icon application is local and opt-in per device.
- Live Activity 8h begins on activity start, not app signup or record creation. Do not promise permanent Dynamic Island/Now Bar placement or try perpetual auto-restart workarounds.
- iOS widgets require native SwiftUI/WidgetKit/App Intents; Android widgets need native platform implementation even if Flutter bridge is used.
- On Windows, do not pretend iOS builds can run locally; implement Android and shared Flutter, provide Mac/Xcode follow-up steps.

## Work style
- Before each phase: propose files to create/modify, risks, acceptance tests. Then implement only agreed phase.
- After edits: run `dart format`, `flutter analyze`, and relevant tests when available; report exact command results.
- Explain any platform limitation and fallback explicitly.
- Use Korean for user-facing UI and reports; code identifiers in English.
- Put database changes in versioned migration files; review RLS/SECURITY DEFINER functions carefully.
- Never fake integrations or hardcode success responses to simulate Supabase.
