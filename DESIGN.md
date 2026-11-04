# Design

## Source of truth
Active · 2026-11-04. Flutter Android/iOS and browser preview. Evidence: docs/PRD.md, ARCHITECTURE.md, DECISIONS.md, ROADMAP_AND_QA.md the user's physical-iPhone lock-screen/Dynamic Island captures, current Flutter browser captures, and Mobbin iOS reference screens inspected on 2026-11-04. Latest product direction: Google sign-in, one family vehicle per account, owner-issued invitation links/codes, and floor-number launcher icons.

## Brand
차자리 · 가족과 함께 기억하는 우리 차의 자리. 앱 이름은 런처 라벨과 앱 안에서만 쓰고, 아이콘·위젯에는 적지 않는다. Calm, practical. 2026-11-04 사용자 선택: 담백하고 또렷하게, 정보와 버튼 위계 중심. Neutral canvas, borderless white cards, ink pill actions, one pastel periwinkle hero tint and a lime highlight. Avoid noisy gradients, technical jargon, fake sync indicators and decorative statistics.

## Product goals
Find the current parking location immediately. Save with floor and zone taps plus explicit confirmation. Share only through authorized membership. No automatic location inference or paid OCR.

## Personas and jobs
Two to three family members sharing a car, often with one hand in a dim underground parking garage. Prioritize large text, predictable controls and clear save outcomes.

## Information architecture
Welcome/Google sign-in → register one new vehicle or join the owner's invitation → home, history, family, settings. Home opens parking form and a widget guide banner. The guide links directly to in-app widget settings; iOS home-widget installation remains an explicit system action. Camera OCR fills editable suggestions. Family owns invitations and membership controls. Settings owns apartment configuration, device display and privacy.

## Design principles
Location first; one primary action per screen; explicit server confirmation; plain language for errors; distinguish local demo from connected account at all times.

## Visual language
Canvas #F3F3F1; ink #17201C (text and primary pill buttons); green #2F6B52 only for toggles; muted #5F655F (≥4.8:1 on canvas); hairline #E8E9E5; lime #D9F27C for the selected tab, 최근 badge and guide step numbers; periwinkle tint #DCE3F2 for the hero location card, shared-vehicle card, invite code and form summary; info #E6EBF6 for notices; soft #E9EAE6 for secondary pills and chips. Cards are white with no border, 24–28px radius; every button and chip is a full pill. Only NotoSansKR Regular (400) and Bold (700) ship, so page headlines are Regular with tight tracking, the home greeting is small muted supporting text, and labels, buttons and chips are Bold; nothing declares 500/600. Headlines, sheet titles and tab labels clamp text scaling at 1.3 so Korean words do not break mid-syllable. Small muted group labels sit on the canvas above grouped cards. Ink on the tint uses ≥.78 alpha. Material rounded icons. No external image or font request required. Motion 180–250ms respecting reduced motion.

## Components
App theme owns colors. Home has a compact brand header with 48px refresh/profile controls and a small greeting. The vehicle name, plate and apartment sit above the location. A single tinted location card shows the floor, zone/spot, optional note, plain author/time metadata and the primary record button in that order. Four existing quick actions (사진 기록 · 차량 찾기 · 이력 보기 · 위젯) sit in a separate white row below the record button. The location semantic label groups only the location; note and author/time remain accessible. Long configured labels or large text stack location values vertically. Floating pill tab bar (NavigationBar in a white stadium, lime indicator) stays above snackbars. Widget guide is a dismissable white card with text actions, so it does not compete with recording. White record rows use circular floor badges; settings use group labels and grouped ActionRow cards. SheetDialog stays bottom-aligned on phones and centered from 760px; parking alone supplies a summary/save footer. Pin that footer only with sufficient available height and normal text size; short screens, keyboard insets, large text and long location summaries use one scrollable body. Other sheets keep their existing behavior. AlertDialog is for short confirmations. Sidebar appears only when width is at least 760px and height at least 520px. Consistent busy/error/disabled states. Home widgets use the deep ink surface with white location text, floor chips (up to 12, selected chip in lime), a zone cycle control and a lime 등록 button; no app name or title row. Live Activity is a compact two-line location row with a visible 44pt end control; ending it preserves parking data. Compact Dynamic Island groups car and floor together on the leading side. Launcher variants show only the floor label F1–F5 or B1–B6, replacing user-facing color selection.

## Accessibility
Target WCAG AA. Minimum 48 logical-pixel hit targets, semantic labels on icon controls, visible keyboard focus, form labels and validation, scrollable forms, no color-only status. Allow text scaling and reduced motion.

## Responsive behavior
Mobile floating pill navigation below 760px; desktop white sidebar card and bounded 1056px content. Home content uses two columns only when its available width reaches 840px; location/actions lead, guide/history/family follow. Dialogs max 560px; forms scroll with keyboard. Support 320px phones and large text.

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

## UI improvement plan · 2026-11-04

Scope: existing shared Flutter home and parking entry. User asked for UI improvement with Mobbin and chose a restrained, legible direction. Preserve the palette, bundled NotoSansKR font, account/vehicle data, all action destinations, explicit demo notice, editable OCR suggestions and server-confirmed save behavior. No new packages or backend/native changes.

| Observed problem | Change | Inspected Mobbin evidence |
| --- | --- | --- |
| Vehicle identity is small inside the location card while the greeting leads. | Compact header; name/plate/apartment beside a vehicle icon above location. Values lead within a single location card. Exact typography and vehicle identity placement are local design judgement. | [My BMW, iOS](https://mobbin.com/screens/cf22ee55-9841-41bd-a02e-6db812757746): compact vehicle header, status, then separate control groups. |
| Four secondary actions separate the current location from its record button; widget guide adds another filled action. | Put record directly below the location in its card; move the same four secondary actions into their own row; use text actions for the guide. | [My BMW, iOS](https://mobbin.com/screens/cf22ee55-9841-41bd-a02e-6db812757746) and [Tesla, iOS](https://mobbin.com/screens/230a86d8-9bf8-4815-b937-b5f541ba02fe): status and secondary control row are separate. [Waymo, iOS](https://mobbin.com/screens/3d8fcf1b-dce6-4520-b096-c87e569a5d08): location choice followed by one primary save action. |
| Parking confirmation/save scrolls away with the fields. | Optional bottom footer for parking summary/save; scroll fallback when vertical space is constrained. | [Waymo, iOS](https://mobbin.com/screens/3d8fcf1b-dce6-4520-b096-c87e569a5d08) and [Zocdoc, iOS](https://mobbin.com/screens/ddb98b00-78a2-49bf-aeb7-fb4eafc56dec): location choices with a separate lower save action. Zocdoc supplies structure only, not medical content or styling. |

Files: `lib/features/shell.dart`, `lib/features/parking_form.dart`, `lib/shared/components.dart`, layout regression tests, `scripts/design_qa.cjs` and `scripts/browser_qa.cjs`. Risks: long configured names, text scaling, keyboard height, shared sheets and missing accessibility metadata. Acceptance: format/analyzer/full Flutter tests, browser save and draft protection, 320/390px and desktop captures, short-screen/large-text/keyboard tests. iOS visual and native behavior verification still requires Mac/Xcode.

The car-art-led and multi-colored tile references were not adopted: the parking location is the app's primary information. Before/after captures are kept in local `docs/qa/ui-redesign/`; `scripts/design_qa.cjs` reproduces a fixed-clock local-demo comparison without live account data.
