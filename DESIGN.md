# Design

## Source of truth
Active · 2026-11-02. Flutter Android/iOS and browser preview. Evidence: docs/PRD.md, ARCHITECTURE.md, DECISIONS.md and ROADMAP_AND_QA.md. No prior visual assets or app implementation supplied.

## Brand
차곡 · 가족과 함께 기억하는 우리 차의 자리. Calm, friendly, practical. Warm ivory, deep forest green and a small lime accent. Avoid noisy gradients, technical jargon, fake sync indicators and decorative statistics.

## Product goals
Find the current parking location immediately. Save with floor and zone taps plus explicit confirmation. Share only through authorized membership. No automatic location inference or paid OCR.

## Personas and jobs
Two to three family members sharing a car, often with one hand in a dim underground parking garage. Prioritize large text, predictable controls and clear save outcomes.

## Information architecture
Welcome/auth → vehicle onboarding → home, history, family, settings. Home opens parking form. Camera OCR fills editable suggestions. Family owns invitations, vehicle appearance and membership controls. Settings owns apartment configuration, device display and privacy.

## Design principles
Location first; one primary action per screen; explicit server confirmation; plain language for errors; distinguish local demo from connected account at all times.

## Visual language
Canvas #F7F8F4; ink #203C34; brand #295C49; accent #DCEBB4; white cards; subdued borders #E4E9E1. 8px spacing rhythm, 20–28px card radii. System Korean font fallback. Material outlined icons. No external image or font request required. Motion 180–250ms respecting reduced motion.

## Components
App theme owns colors. Location card, section heading, primary action, choice chip, empty state, status banner, member avatar, settings tile. Consistent busy/error/disabled states.

## Accessibility
Target WCAG AA. Minimum 48 logical-pixel hit targets, semantic labels on icon controls, visible keyboard focus, form labels and validation, scrollable forms, no color-only status. Allow text scaling and reduced motion.

## Responsive behavior
Mobile bottom navigation below 760px; desktop left navigation and bounded 1040px content. Dialogs max 560px; forms scroll with keyboard. Support 320px phones and large text.

## Interaction states
Explicit loading and retry; first-car empty state; no-record state; no-history search result; server error preserves draft; no save success before acknowledgment; camera rejection falls back to manual entry. Demo records persist locally under a separate key. Logout clears native snapshots.

## Content voice
Korean first. Short helpful sentences. Use '주차 기록', '가족 초대', '위치 확인'. Show exact date/time and local timezone. Never imply that a demo invite or local notification is real family synchronization/push.

## Implementation constraints
Flutter shared UI, Supabase production repository and isolated local demo repository. Secure native session storage. Native on-device OCR; no photo upload. Snapshot widgets must show last update time. macOS required for signed iOS/TestFlight verification.

## Open questions
- [x] App/widget identifiers and signing CI are connected. Internal TestFlight delivery is verified; physical-device installation remains unverified. Signing credentials and deployment receipts stay in private CI.
- [x] Dedicated Supabase Free Seoul project is connected. Hosted Auth/PostgREST/Realtime and server push paths have been tested; detailed account-specific evidence stays private.
- [ ] Owner: user supplies existing sender domain/SMTP details; agent connects and verifies authentication email delivery.
- [ ] Real parking-sign samples and physical-device camera, notification, widget and Live Activity observations remain needed.
- [x] Final native settings/icon captures and 19 connected-auth UI checks supplement the nine-screen browser audit. Selected-chip contrast and 320px intro wrapping were fixed and reverified.
