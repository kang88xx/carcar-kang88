# App Store 등록 작업 인계 · 2026-11-06

사용자가 작업을 여기까지 저장하고 맥북에서 이어가기로 했다. 아래 Apple 로그인 변경은 **미완성 체크포인트**이며 심사 제출·새 TestFlight 배포를 하지 않았다. 실패한 테스트를 고치고 인증·삭제·서명 설정을 완료하기 전에는 이 브랜치로 배포하지 않는다.

## 맥북에서 이어가기

소스 저장소: `git@github.com:kang88xx/carcar-kang88.git`

```sh
git fetch origin
git switch --track origin/wip/app-store-prep-2026-11-06
```

이미 이 로컬 브랜치가 있으면 `git switch wip/app-store-prep-2026-11-06`을 사용한다. 기존 작업 파일이 있는 맥북 체크아웃은 변경을 덮어쓰지 말고 별도 checkout/worktree를 사용한다.

다음 작업자는 이 문서, `AGENTS.md`, 프로젝트 기본 문서 및 `docs/app-store/submission-draft.json`을 먼저 읽는다. Flutter 3.35.4 / Dart 3.9.2가 프로젝트 기준이다.

## 사용자 확정 사항

- 기존 유료 Apple Developer 계정으로 App Store 등록을 진행한다. 신규 계정 결제나 유료 서버 도입은 요청하지 않았다.
- 앱 가격: 무료. 최초 배포 국가: 대한민국.
- 공개 고객지원 이메일: `kang88xx@gmail.com`.
- 심사용 이름·이메일·전화번호는 받았으며 비공개로 취급한다. 공개 저장소에 넣지 않았다.
- 이번 작업과 테스트는 iOS 우선이다. Android 실기기 검증은 나중에 진행한다.

## 완료·게시된 결과

- 최신 TestFlight: **1.0.0 (12)**. Apple 처리 `VALID`, 기존 내부 테스트 그룹 연결 완료.
- 빌드 12의 앱 소스는 `f3373a6`, 비공개 빌드 소스는 `cdace91`. 이후 문서 커밋은 바이너리 변경이 아니다.
- [빌드 12 배포 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42171293207), [공개 앱 검증](https://github.com/kang88xx/carcar-kang88/actions/runs/42171242680) 성공.
- 네 탭 헤더 고정과 작은 화면 기록 버튼 문구 수정: Flutter 188개, 별도 화면 검사 4개/44장 통과. 최신 실제 iPhone 동작 확인은 별도다.
- 지원 사이트와 등록 초안은 main의 `243c3b8`에 저장·push했다. [사이트 게시 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42180853820), [해당 main 검증 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42180853943) 성공.
- 공개 지원 페이지: https://kang88xx.github.io/carcar-kang88/support/
- 개인정보 페이지: https://kang88xx.github.io/carcar-kang88/privacy/
- `site/support/index.html`, 홈의 지원 링크, 공개 개인정보 페이지의 위젯 설명·문의 경로를 정리했다. 지원 사이트의 320/768/1280px 브라우저 검사와 링크 16개 검사를 통과했다.
- `docs/app-store/submission-draft.json`: 한국어 설명·부제·키워드·스크린샷 촬영 계획과 무료/KOR 설정 초안. 문자열 제한·키워드 UTF-8 100바이트 제한을 검사했다. 자동 업로드/제출 도구는 아니다.

## App Store Connect 조회 결과

2026-11-06 조회 시 등록명은 `차자리 - 가족 주차 기록`, 기본 언어 `ko`, iOS 버전 `1.0`은 `PREPARE_FOR_SUBMISSION`이었다.

- 설명·키워드·스크린샷·지원 URL·부제·개인정보 URL·저작권자·카테고리가 비어 있다.
- 선택된 심사용 빌드와 App Review 연락처/로그인 정보가 없다.
- 연령 등급 답변이 비어 있다. App Privacy 신고 완료 여부와 가격/판매 국가의 실제 서버 설정은 아직 확인하지 않았다.
- 기존 출시 옵션은 `AFTER_APPROVAL`이다. 초안은 승인 후 수동 출시를 제안하지만 원격 설정은 바꾸지 않았다. 제출 전에 출시 방식을 명확히 확인한다.
- App Store Connect 메타데이터 수정, 심사 제출, 공개 출시는 아직 실행하지 않았다.
- 바이너리는 iPhone과 iPad(`TARGETED_DEVICE_FAMILY = 1,2`)를 지원한다. 두 기기군의 스토어 스크린샷이 필요하다. 기존 작은 QA PNG를 실제 기기 캡처로 가장하지 않는다.

## 이 브랜치에만 있는 미완성 코드

다음 다섯 파일은 Apple 로그인 작업 중 사용자의 저장 요청으로 중단했다.

- `ios/Runner/AppDelegate.swift`: AuthenticationServices/CryptoKit 기반 Apple 인증 요청, nonce/state, delegate와 presentation anchor.
- `ios/Runner/Runner.entitlements`: `com.apple.developer.applesignin = [Default]` 추가.
- `lib/core/native_bridge.dart`: iOS 전용 `supportsAppleSignIn`, `AppleCredential`, `signInWithApple()` 추가.
- `lib/features/auth_screen.dart`: 기존 Google 로그인을 유지하며 iOS Apple 버튼과 Supabase ID token 로그인 추가.
- `test/apple_auth_test.dart`: 신규 테스트 초안.

현재 NativeBridge 계약:

```text
signInWithApple() -> Future<AppleCredential?>
사용자 취소 -> null
필드: identityToken, authorizationCode, userIdentifier, rawNonce, fullName?
MethodChannel: carcar/native / signInWithApple
```

최초 이름은 반환하지만 기존 프로필 nickname/metadata를 자동 덮어쓰지 않는다. 실제 계정의 표시 이름 처리는 후속 검토 대상이다.

### 마지막 검사 결과

- 수정 Dart 파일 포맷 완료, `git diff --check` 통과.
- `flutter test --no-pub test/apple_auth_test.dart test/account_usability_test.dart`: **17 통과 / 10 실패**, 종료 코드 1.
- 기존 `account_usability_test.dart` 13개는 통과했다.
- 신규 테스트의 `debugDefaultTargetPlatformOverride` 복원이 테스트 invariant 검사보다 늦고, `FilledButton.icon`/`OutlinedButton.icon`을 `find.byType(FilledButton/OutlinedButton)`으로 찾는 일부 finder가 실패한다. 플랫폼 variant/복원 및 실제 버튼 타입에 맞는 finder 수정부터 진행한다.
- 이 브랜치 전체 `flutter analyze`, 전체 회귀, Swift 컴파일, 실제 Apple 로그인은 아직 검증하지 않았다.
- 위 실패는 앞서 검증·배포된 TestFlight 12와 별개다.

## Apple·서버 설정의 현재 상태

- 기존 App ID는 `com.kang88.carcar`, Widget은 `com.kang88.carcar.ParkingWidget`이다. 식별자는 바꾸지 않는다.
- 기존 App ID capability 조회에는 In-App Purchase/App Groups/Push만 있었다. Apple 로그인 권한 활성화는 **완료하지 못했다**.
- API의 capability 이름은 `APPLE_ID_AUTH`이다. 잘못된 `SIGN_IN_WITH_APPLE` 요청은 HTTP 409 `ENTITY_ERROR.ATTRIBUTE.TYPE`, 수정한 `APPLE_ID_AUTH` 요청도 HTTP 409 `ENTITY_ERROR`로 거절됐다. 반복 요청하지 말고 공식 schema/settings 또는 Developer 사이트에서 원인을 확인한다.
- Developer 사이트의 개별 App ID 화면 이동도 완료하지 못했다. 원격 capability 변경 성공을 가정하지 않는다.
- 차자리용 Sign in with Apple 개인 키를 새로 만들거나 다운로드하지 않았다. 다른 앱 `60BASE`의 기존 Apple 로그인 키는 변경하지 않았다.
- Supabase Apple provider 활성화·Client IDs 설정·Edge 배포·새 secret 등록은 모두 아직 하지 않았다.
- 기존 배포 프로파일에 Apple 로그인 entitlement가 없을 수 있다. 앱 권한 설정 후 새 프로파일과 CI의 재사용/검증 로직을 같이 수정해야 한다.
- 계정 삭제/철회 담당자는 읽기 조사만 했으며 해당 코드·서버 파일은 아직 수정하지 않았다.

## 다음 작업 순서

1. 신규 Apple 테스트를 고치고 코드 검토·분석·전체 회귀를 수행한다. iOS 네이티브를 Xcode에서 컴파일한다.
2. App ID에 Sign in with Apple을 활성화하고 entitlement가 포함된 앱 프로파일을 준비한다. `fastlane/prepare_existing_signing.mjs`와 `prepare_signing.py`가 옛 프로파일을 고르지 않도록 검사·테스트를 보완한다.
3. 네이티브 전용 로그인은 Services ID 없이 가능하다. Supabase Apple provider를 활성화하고 Client IDs에 `com.kang88.carcar`를 등록하며 nonce 검증을 유지한다. 기존 Google 설정과 사용자를 변경하지 않는다.
4. Apple 로그인 키와 서버 철회 기능을 구현한다. App Store Connect API 키를 Apple 로그인 키로 재사용하지 않는다.
5. 계정 삭제의 계정 전환 방어와 Apple 연결 해제/수동 fallback을 구현한다. 아래 설계 경계를 따른다.
6. 공개 앱의 문의 UI를 TestFlight 전용 안내에서 지원 페이지로 바꾼다. 개인정보 문구와 실제 인증·삭제 동작을 맞춘다.
7. 실제 iPhone에서 Apple/Google 로그인·취소·재시도·가족 공유·삭제를 검증한다. Apple 비공개 이메일은 기존 Google 계정과 별도 계정일 수 있으므로 이메일 추측으로 합치지 않는다.
8. 최종 iPhone/iPad 스크린샷, 개인정보 수집 신고, 연령 등급, 저작권, 심사용 전 기능 접근 방법을 준비한다. 로컬 체험은 실제 가족 공유를 제공하지 않으므로 심사용 접근을 대체한다고 단정하지 않는다.
9. 무료/KOR·등록 자료·심사 연락처·최종 빌드를 App Store Connect에 반영·재조회한 뒤 심사 제출한다. Apple 심사 통과를 미리 보장하지 않는다.

### 삭제 설계 검토 결과 — 아직 구현하지 않음

- 삭제 재인증에서 `signInWithIdToken`으로 Supabase 세션을 교체하지 않는다. 기존 bearer를 유지한 채 native 자격만 얻는다.
- `apple-disconnect` Edge 입력은 `authorizationCode`와 `rawNonce`로 제한한다.
- Edge가 Supabase `/auth/v1/user`로 bearer를 검증하고 서버 identity의 Apple `sub`를 확보한다. 이메일·클라이언트 userId를 권한 근거로 사용하지 않는다.
- 고정 Apple HTTPS `/auth/token` 응답에서만 받은 ID token의 issuer/audience/시간/subject/nonce를 검사하고, 현재 사용자와 일치할 때 반환 토큰을 `/auth/revoke`로 철회한다. 클라이언트가 보낸 ID token을 단순 파싱하는 방식은 금지한다.
- 이 직접 TLS token endpoint 경로에 한해 OIDC 3.1.3.7(6)의 검증 규칙을 적용할 수 있다. redirect 차단·시간/크기 제한·토큰 로그 금지를 지킨다.
- 계획된 서버 secret 이름: `APPLE_SIGN_IN_TEAM_ID`, `APPLE_SIGN_IN_KEY_ID`, `APPLE_SIGN_IN_PRIVATE_KEY`, `APPLE_SIGN_IN_CLIENT_ID`. 일반 Supabase URL/anon 설정과 함께 사용하되 키는 앱·Git에 넣지 않는다.
- 철회 뒤 기존 `delete_my_account` RPC를 실행한다. 현재 `repository.deleteAccount()`에는 `_requireSameUser()`가 없어 보완해야 한다. 삭제 시작/직전에 사용자 검사, 캡처한 access token으로 RPC Authorization 고정, 응답 뒤 같은 사용자일 때만 local sign-out을 한다.
- 토큰 부재·일시 장애로 계정 삭제를 영구 차단하면 안 된다. 재시도/취소 또는 명시적인 계정 삭제 후 수동 Apple 접근 철회 안내를 제공한다. identity 불일치·세션 변경은 자동 fallback으로 넘기지 않는다.
- 장기 Apple 토큰을 저장하지 않는 최소안을 검토했다. 삭제 시 재인증과 수동 fallback이 필수이며, Apple의 신규 토큰 안전 보관 권고와의 차이를 후속 구현 검토에서 고려한다.

## 비공개 자료와 비용

Windows/WSL 작업 환경에만 있는 다음 자료는 공개 Git에 포함하지 않았다. 맥북에서 기존 개발자 로그인/보안 자격 저장소를 확인하고 필요한 자격은 안전하게 옮긴다. 키를 채팅이나 Git에 복사하지 않는다.

- `/home/kang/.local/share/carcar-release/apple.json`: 기존 API 키 경로 등. 파일 자체나 키 내용을 공개하지 않는다.
- `/home/kang/.local/share/carcar-release/app-store-review-contact.json`: 사용자 제공 심사 연락처, 권한 0600.
- `/home/kang/.local/share/carcar-release/backend-qa.json`: 서버 테스트 자격. 앱에 포함 금지.
- `docs/qa/appstore-readiness-2026-11-06/`: App Store 조회 결과, 사이트 검증·캡처.
- 비공개 빌드 저장소는 `kang88xx/60base-mobile-build`, 앱 경로는 `apps/carcar`. 현재 private main `f5571a3`은 TestFlight 12 기록까지이며 이 WIP를 동기화하지 않았다.

GitHub Actions 추가 유료 예산은 $0/Usage blocked를 유지한다. 마지막 실행 전 확인한 포함 compute 사용액은 $10.36/$12였고 그 뒤 빌드 12가 6분 44초 실행됐다. 잔액을 다시 확인하기 전 새 private macOS CI를 실행하지 않는다. 맥북 로컬 Xcode 검증을 우선 사용할 수 있다. Supabase Free와 기기 내 OCR을 유지한다.

## 공식 근거

- [App Review 4.8 로그인](https://developer.apple.com/app-store/review/guidelines/#login-services)
- [Supabase Apple 로그인](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)
- [Apple 계정 삭제·토큰 철회 TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [OIDC ID Token 검증](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
- [스토어 버전 정보](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [스크린샷 규격](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
