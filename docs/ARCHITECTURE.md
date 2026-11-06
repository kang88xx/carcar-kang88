# 기술 설계

## 현재 구현 · 2026-11-06

아래 권장안은 제공받은 초기 설계입니다. 실제 배포 구조는 다음과 같으며, 공개 검증 범위는 [README](../README.md#검증)에 정리합니다. 계정별 배포 기록은 비공개로 관리합니다.

- `lib/main.dart`가 인증·복구 세션을 분기하고 계정 변경 시 컨트롤러와 네이티브 상태를 정리합니다. `core/repository.dart`는 실제 Supabase와 별도 로컬 체험 저장소의 공통 경계입니다. `core/app_controller.dart`가 연결된 차량 한 대·최신 기록·Realtime을 관리합니다. 계정 전환 시 이전 등록·참여 창을 닫고, 오래된 컨트롤러의 변경 요청을 차단합니다.
- 화면은 `features/`의 파일 단위로 구성합니다. `device_notifications.dart`는 기기별 서버 설정·권한·토큰 등록을 관리합니다. `NativeBridge`가 OCR, 위젯, 차량 찾기, 알림, iOS·Android 층수 런처 아이콘을 연결합니다.
- Flutter 3.47.9 / Dart 3.13.7을 사용합니다. iOS는 `Info.plist`의 단일 scene 설정과 `AppDelegate.swift`의 `SceneDelegate: FlutterSceneDelegate`를 사용합니다. 플러그인과 `carcar/native` 채널은 `didInitializeImplicitFlutterEngine`에서 등록하고, 공유 화면·Apple 인증의 표시 창은 활성 scene의 보이는 key window에서 찾습니다. 앱 최소 iOS 15.0과 위젯 17.0은 유지합니다.
- `app_links` 6.4.1 호환을 위해 종료 상태에서 링크로 시작할 때 `SceneDelegate`가 초기 URL과 `NSUserActivity.webpageURL`을 중복 제거해 전달합니다. 실행 중 링크는 Flutter의 기존 AppDelegate 플러그인 전달 경로에 맡깁니다. `FlutterDeepLinkingEnabled`는 false로 유지하며 플러그인을 갱신할 때 초기 링크 누락·중복 전달을 다시 검증합니다. iOS 의존성은 Swift Package Manager와 `flutter_secure_storage` 9.2.4용 CocoaPods를 함께 사용합니다.
- 인증·PostgreSQL·Realtime은 차자리 전용 Supabase Free 서울 프로젝트를 사용합니다. 차량·초대·주차 저장은 권한을 검사하는 SQL RPC이며 주차 이력과 최신 포인터를 같은 트랜잭션에서 확정합니다. 사진 Storage와 서버 OCR은 사용하지 않습니다.
- 알림 설정과 토큰은 `private` 스키마에 보관합니다. 주차 트랜잭션은 발송 작업만 추가하고, Vault 인증을 사용하는 매분 예약 작업이 필요한 경우에만 `parking-push` Edge Function을 호출합니다. worker는 발송 직전 권한·기기 설정을 재검사하고 APNs HTTP/2 또는 FCM data-only로 전송합니다. 전송 실패는 이미 저장된 주차 기록을 취소하지 않습니다. [푸시 구조와 배포](../supabase/deployment/PUSH.md).
- 현재 정사각형 위젯은 서버 확정 기록 스냅샷을 표시하고 `carcar://parking`으로 Flutter의 기존 주차 입력 화면을 엽니다. 상단 시각은 화면 갱신 시간이 아니라 `created_at`입니다. 로그인·차량 준비 후 한 번만 입력을 열고 계정 전환 시 이전 요청을 폐기합니다.
- 이전 위젯 직접 저장 기능의 호환용 보안 경로는 짧은 수명의 사용자 access token만 플랫폼 보안 저장소에 보관합니다. refresh token과 서버 비밀키를 전달하지 않습니다. 서버 확인 전 성공 표시를 하지 않으며 계정·차량 전환 뒤 늦은 응답을 폐기합니다.
- 로그인 진입은 Supabase Google OAuth이며 네이티브 복귀 주소는 `com.kang88.carcar://login-callback`입니다. 기존 비밀번호 복구 링크 처리는 호환 경로로 남아 있지만 새 가입 화면은 이메일/비밀번호를 받지 않습니다. Google 클라이언트 비밀키는 Supabase에만 둡니다. 실제 인증 플랫폼 설정 및 로그인 왕복 검증 여부는 릴리스 기록을 따릅니다.
- 정규화(NFKC·대문자·공백/하이픈 제거)한 차량번호의 고유 인덱스와 `vehicle_members(user_id)` 고유 제약으로 번호 중복·다중 차량 가입을 서버에서 막습니다. 번호 확인은 인증 사용자에게 boolean만 반환하며 요청 횟수를 제한합니다. 생성·참여·계정 삭제는 같은 사용자 잠금 순서를 사용합니다.
- `core/invite_links.dart`가 48자리 hex 초대와 허용된 링크를 해석합니다. 공유 HTTPS 링크의 fragment에서 사용자가 앱 열기를 누르면 `com.kang88.carcar://invite?invite_code=...`로 전달합니다. OAuth의 `code`와 초대의 `invite_code`를 분리하며, 받은 초대는 로그인 뒤 명시적 참여 확인까지 보관합니다. 저장 실패는 성공으로 숨기지 않습니다.
- 앱 아이콘은 확인된 최신 기록에서 `floor_f1`~`floor_f5`, `floor_b1`~`floor_b6` 중 하나를 골라 현재 기기에 적용합니다. 기록 없음·지원 외 층수·로그아웃은 기본 아이콘으로 복원합니다. 계정 간 변경 작업은 직렬화하고 오래된 요청은 무시합니다. 아이콘 실패는 이미 확정한 주차 기록을 되돌리지 않습니다. 기존 `vehicle.icon_id`와 색상 자산은 호환용으로 유지하며 색상 선택 화면은 제거했습니다.
- Live Activity는 얇은 두 줄 잠금 화면 카드, 특정 활동만 끝내는 종료 App Intent, 축약 Dynamic Island 왼쪽 자동차·층수 묶음을 사용합니다. 종료는 주차 기록 삭제가 아닙니다. 시작은 사용자 동작이며 원격 활동 갱신은 현재 범위에 포함되지 않습니다.
- 메인 배너에서 위젯 추가 안내와 앱 내부 위젯 설정으로 이동합니다. iOS 홈 위젯 자동 배치나 위젯 갤러리 직접 열기는 구현하지 않습니다. iOS 아이콘 변경 시스템 안내, 앱 비활성 중 갱신, 무료 한도·휴면 및 실기기 검증의 한계는 [README](../README.md#검증)를 따릅니다.

## 초기 설계 기록

아래는 최초 권장안이며 현재 구현 계약이 아닙니다. 특히 다중 차량 허용과 공유 색상 변경은 2026-11-02의 계정당 차량 한 대·자동 층수 아이콘 요구로 대체했습니다. 실제 파일 구성과 동작은 위 현재 구현을 따릅니다.

## 권장 아키텍처
- Flutter / Dart: 앱 공통 UI 및 도메인 로직.
- Supabase: Auth, PostgreSQL, Realtime, 비공개 Storage(사진 선택 사용), Edge Functions(초대 발급/알림 필요 시).
- OCR: iOS Vision (`VNRecognizeTextRequest`), Android 온디바이스 Google ML Kit Text Recognition. Flutter 패키지 API/버전은 구현 직전 검증.
- iOS 위젯: WidgetKit + App Intents + App Groups; Flutter↔네이티브 연동. Android: AppWidget/Glance 등 네이티브 위젯.
- iOS 상단: ActivityKit + SwiftUI Live Activity extension; Flutter plugin/platform channel.
- Android 상단: 표준 알림을 우선, 호환 기종에서 Live Updates/Now Bar는 기능 탐지 후 조건부 적용.
- 푸시: APNs/FCM. 실제 푸시 및 Live Activity 원격 갱신은 인증된 서버 측 전송 환경이 필요하며, Free 한도를 검토.

## 앱 프로젝트 구조 (권장)
```
lib/
  app/                 # 앱 초기화, 라우터, 테마
  core/                # Supabase, 오류, 세션, 보안 저장소
  features/
    auth/
    vehicles/
    invites/
    parking/
    ocr/
    history/
    settings/
    widgets/
    live_display/
  shared/              # 공통 UI
ios/                   # Widget extension, App Intents, ActivityKit, Vision
android/               # widget receiver, ML Kit, notifications
supabase/migrations/   # SQL migration
integration_test/
```

## DB 모델
- `profiles(id -> auth.users.id, nickname, created_at)`
- `apartments(id, owner_id, name, allowed_floors, allowed_zones)`
- `vehicles(id, apartment_id, plate_number, nickname, icon_id, owner_id, latest_parking_record_id)`
- `vehicle_members(vehicle_id, user_id, role, joined_at)`
- `vehicle_invites(id, vehicle_id, token_hash, expires_at, remaining_uses, created_by)`
- `parking_records(id, vehicle_id, floor, zone, spot, note, image_path, created_by, created_at)`
- `device_settings(id, user_id, device_installation_id, platform, push_enabled, live_enabled, notify_own, quiet_start, quiet_end, preferred_live_minutes)`
- `device_push_tokens(id, device_settings_id, token_ciphertext_or_secret_ref, updated_at)` — 권장: 토큰은 안전한 서버 저장 정책, 클라이언트 최소 노출.

## 서버 작업/API
1. `create_vehicle`: 소유자 멤버십까지 트랜잭션 처리.
2. `create_invite`: 로그인한 차량 소유자만 발급; 원시 코드는 **한 번만 노출**, DB에는 해시만 저장.
3. `redeem_invite`: 인증 사용자, 서버 측 검증, 만료/사용 횟수 감소와 멤버십 추가를 원자 처리. 초대 코드 brute-force rate limit.
4. `create_parking_record`: 회원 권한 확인, 입력 검증, 이력 추가 및 최신 포인터 갱신을 트랜잭션 처리. 중복 탭에 idempotency key 사용 권장.
5. `notify_members`: 작성자/개별 기기 알림 설정/야간 정책을 적용한 비동기 전송. 실패 시 기록 저장은 유지.
6. `update_icon`: 소유자 또는 승인된 역할만, 사전에 정해진 아이콘 ID만 허용.

## 상태/데이터 일관성
- 서버가 주차 위치의 source of truth.
- optimistic UI는 '저장 중'을 표시할 수 있으나 서버 성공 전 '저장 완료' 표시 금지.
- Realtime 수신과 앱 재진입 시 fetch를 같이 사용.
- 위젯은 캐시 스냅샷을 읽고, 액션 성공 후 갱신 요청; 다른 기기의 위젯 즉시 반영 보장 불가.
- 초기안은 다중 차량을 허용했으나 현재는 `vehicle_members(user_id)` 고유 제약으로 계정당 차량 한 대를 강제합니다.

## OCR 파이프라인
이미지 획득 → 촬영 이미지 회전/리사이즈 → 기기 내 OCR → 텍스트 정규화(`지하2층`, `B2`, `B-2` 등) → 층/구역/번호 후보 추출 → 사용자 확인·수정 → DB 저장.
- 층수와 번호가 서로 다른 표지판에 있으면 2장 촬영 또는 수동 보완.
- 출발은 규칙 기반 파싱. 사진 수집은 기본 OFF, 선택 저장만 진행.
- 테스트 이미지셋은 비식별 샘플을 사용; 차량번호·사람 얼굴·아파트 동호수 노출 방지.

## Live Activity/Now Bar 정책
- Live Activity **활성 최대 8시간은 각 활동 시작 시점 기준**. 활동 만료 후 Dynamic Island에서 제거; 잠금 화면에는 최대 4시간 추가 잔류 가능.
- 새 실제 주차 시 기존 활동을 종료하고 신규 활동을 시작하는 기능은 사용자 설정/OS 제약/사용자 의도에 따라 구현. 편법 반복 생성으로 영구 고정을 시도하지 않음.
- 차량 찾기 때 수동 시작(1·2·4시간 등), 수동 종료 가능하도록 설계.
- iOS가 표시 여부·우선순위를 결정; 서버가 사용자 기기 아일랜드를 강제로 켜거나 고정할 수 없음.
- Android Now Bar는 전 기기 공통 API가 아니므로 표준 알림 fallback 필수.

## 참조 문서
- Apple ActivityKit: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple App Intents: https://developer.apple.com/documentation/appintents/widgets-live-activities-and-controls
- Flutter home_widget: https://pub.dev/packages/home_widget (네이티브 위젯 구현 필요)
- Supabase: https://supabase.com/docs
