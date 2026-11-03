# Design

## Source of truth
Active · 2026-11-02. Flutter Android/iOS and browser preview. Evidence: docs/PRD.md, ARCHITECTURE.md, DECISIONS.md, ROADMAP_AND_QA.md and the user's physical-iPhone lock-screen/Dynamic Island captures. Latest product direction: Google sign-in, one family vehicle per account, owner-issued invitation links/codes, and floor-number launcher icons.

## Brand
차자리 · 가족과 함께 기억하는 우리 차의 자리. 앱 이름은 런처 라벨과 앱 안에서만 쓰고, 아이콘·위젯에는 적지 않는다. Calm, editorial, practical (2026-11-03 Future Pro 참고 재설계). Neutral canvas, borderless white cards, ink pill actions, one pastel periwinkle hero tint and a lime highlight. Avoid noisy gradients, technical jargon, fake sync indicators and decorative statistics.

## Product goals
Find the current parking location immediately. Save with floor and zone taps plus explicit confirmation. Share only through authorized membership. No automatic location inference or paid OCR.

## Personas and jobs
Two to three family members sharing a car, often with one hand in a dim underground parking garage. Prioritize large text, predictable controls and clear save outcomes.

## Information architecture
Welcome/Google sign-in → register one new vehicle or join the owner's invitation → home, history, family, settings. Home opens parking form and a widget guide banner. The guide links directly to in-app widget settings; iOS home-widget installation remains an explicit system action. Camera OCR fills editable suggestions. Family owns invitations and membership controls. Settings owns apartment configuration, device display and privacy.

## Design principles
Location first; one primary action per screen; explicit server confirmation; plain language for errors; distinguish local demo from connected account at all times.

## Visual language
Canvas #F3F3F1; ink #17201C (text and primary pill buttons); green #2F6B52 only for toggles; muted #5F655F (≥4.8:1 on canvas); hairline #E8E9E5; lime #D9F27C for the selected tab, 최근 badge and guide step numbers; periwinkle tint #DCE3F2 for the hero location card, shared-vehicle card, invite code and form summary; info #E6EBF6 for notices; soft #E9EAE6 for secondary pills and chips. Cards are white with no border, 24–28px radius; every button and chip is a full pill. Only NotoSansKR Regular (400) and Bold (700) ship, so headlines are large Regular with tight tracking, like the time-of-day greeting, and labels, buttons and chips are Bold; nothing declares 500/600. Headlines, sheet titles and tab labels clamp text scaling at 1.3 so Korean words do not break mid-syllable. Small muted group labels sit on the canvas above grouped cards. Ink on the tint uses ≥.78 alpha. Material rounded icons. No external image or font request required. Motion 180–250ms respecting reduced motion.

## Components
App theme owns colors. Greeting header with round refresh and avatar controls; floating pill tab bar (NavigationBar in a white stadium, lime indicator) that stays above snackbars; hero group (tinted location card with 76px floor, zone and spot, author/time row, then a translucent quick-action strip of circular icons: 사진으로 · 차량 찾기 · 이력 보기 · 위젯); full-width ink pill primary action; dismissable white info banner with an ink pill CTA; white record list rows with circular floor badges; group label + grouped white card rows with chevrons (ActionRow) for settings; sheet dialog (Dialog pinned to the bottom edge on phones, centered card from 760px) for parking, vehicle, apartment, invite, finding, quiet-hours and name forms, with the dialog name announced to screen readers; AlertDialog only for short confirmations and the icon/guide/privacy notes. On phones the greeting sits under a right-aligned refresh and avatar row; the sidebar appears only when the window is both ≥760px wide and ≥520px tall. Consistent busy/error/disabled states. Home widgets use the deep ink surface with white location text, floor chips (up to 12, selected chip in lime), a zone cycle control and a lime 등록 button; no app name or title row. Live Activity is a compact two-line location row with a visible 44pt end control; ending it preserves parking data. Compact Dynamic Island groups car and floor together on the leading side. Launcher variants show only the floor label F1–F5 or B1–B6, replacing user-facing color selection.

## Accessibility
Target WCAG AA. Minimum 48 logical-pixel hit targets, semantic labels on icon controls, visible keyboard focus, form labels and validation, scrollable forms, no color-only status. Allow text scaling and reduced motion.

## Responsive behavior
Mobile floating pill navigation below 760px; desktop white sidebar card and bounded 1056px content. Dialogs max 560px; forms scroll with keyboard. Support 320px phones and large text.

## Interaction states
Explicit loading and retry; first-car empty state; no-record state; no-history search result; server error preserves draft; no save success before acknowledgment; camera rejection falls back to manual entry. Demo records persist locally under a separate key. Logout clears native snapshots.

## Content voice
Korean first. Short helpful sentences. Use '주차 기록', '가족 초대', '위치 확인'. Show exact date/time and local timezone. Never imply that a demo invite or local notification is real family synchronization/push.

## Implementation constraints
Flutter shared UI, Supabase production repository and isolated local demo repository. Secure native session storage. Native on-device OCR; no photo upload. Snapshot widgets must show last update time. macOS required for signed iOS/TestFlight verification. Plate availability reveals only a boolean; membership requires an owner-issued invite. Icon changes follow confirmed parking state and run when the app is active; iOS may show its own change notice. Never present an icon update or a widget instruction as successful home-widget installation.

## Open questions
- [x] App/widget identifiers and signing CI are connected. Internal TestFlight delivery is verified; physical-device installation remains unverified. Signing credentials and deployment receipts stay in private CI.
- [x] Dedicated Supabase Free Seoul project is connected. Hosted Auth/PostgREST/Realtime and server push paths have been tested; detailed account-specific evidence stays private.
- [ ] Owner: user supplies existing sender domain/SMTP details; agent connects and verifies authentication email delivery.
- [ ] Real parking-sign samples and physical-device camera, notification, widget and Live Activity observations remain needed.
- [x] Final native settings/icon captures and 19 connected-auth UI checks supplement the nine-screen browser audit. Selected-chip contrast and 320px intro wrapping were fixed and reverified.
