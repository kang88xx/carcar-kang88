# Apple 연결 해제 서버 함수

`apple-disconnect`는 현재 Supabase 사용자와 재인증한 Apple 계정이 같은지 확인하고 Apple 토큰만 철회합니다. 데이터베이스 삭제 권한·service_role 키를 사용하지 않습니다. 실제 계정 삭제는 앱의 기존 `delete_my_account` RPC에서 별도로 수행합니다.

## 배포 상태 · 2026-11-06

- 사용자 승인 후 차자리 전용 `Chagok Apple Login` 키를 생성하고, Sign in with Apple 권한과 해당 primary App ID 연결을 재조회했다. 개인 키는 형식 검증 후 `~/.local/share/carcar-release/apple-sign-in/`에 보호 저장했다(디렉터리 0700, 파일 0600). Downloads 임시 사본은 제거했다.
- 아래 서버 secret 4개를 등록했다. 새로고침 후 각 SHA-256이 로컬 값과 일치하며 기존 secret digest는 유지됨을 확인했다.
- `apple-disconnect` **ACTIVE / v1** 배포를 확인했다. 원격에서 다시 받은 `index.ts`, `core.mjs`, `deno.json`은 로컬 배포 파일과 정확히 일치한다. 기존 `parking-push` 소스 checksum은 그대로이며, 공통 secret 갱신으로 함수 버전만 v1에서 v2로 자동 변경됐다.
- 운영 endpoint 검사에서 Authorization 누락·가짜 bearer는 401 `session_invalid`, 잘못된 JSON은 400 `invalid_request`를 반환했다. 모두 `Cache-Control: no-store`이며 실제 Apple 자격·토큰 교환·철회·계정 삭제는 사용하지 않았다.
- 검증 기록은 로컬 `build/account-deletion-qa/production-smoke.json`, `verification.json`과 비공개 키 디렉터리의 `setup-receipt.json`에 있다. 서명된 실제 iPhone의 Apple 로그인·철회·삭제 성공은 별도 검증이 필요하다. 새 앱/TestFlight 배포를 완료한 상태는 아니다.

## 서버 설정

Supabase가 제공하는 `SUPABASE_URL`, `SUPABASE_ANON_KEY` 외에 다음 값을 **서버 함수 비밀 설정**에 등록합니다. 현재 배포에는 등록을 완료했습니다. Apple 개인 키는 앱, Git, 빌드 로그, 채팅에 넣지 않습니다.

- `APPLE_SIGN_IN_TEAM_ID`: 해당 앱을 소유한 Apple Developer Team ID
- `APPLE_SIGN_IN_KEY_ID`: Sign in with Apple 권한이 있는 서버 키 ID
- `APPLE_SIGN_IN_PRIVATE_KEY`: 해당 키의 PKCS#8 PEM 전체 내용 (`.p8`)
- `APPLE_SIGN_IN_CLIENT_ID`: `com.kang88.carcar`

로그인용 App ID 기능 활성화만으로 이 서버 키가 생기지는 않습니다. 해당 App ID에 사용할 수 있는 Sign in with Apple 키가 별도로 필요합니다. 기존 APNs 키를 이름만 바꿔 재사용하지 않습니다.

배포 시 Edge gateway JWT 검사를 비활성화하고 함수 내부의 `/auth/v1/user` 검증을 사용합니다. 예: `supabase functions deploy apple-disconnect --no-verify-jwt`. 현재 배포는 위 배포 상태의 원격 재조회와 검사 결과로 확인했습니다. 이후 재배포도 대상 프로젝트·비밀 설정·원격 소스를 다시 확인합니다. `--no-verify-jwt`는 함수의 사용자 인증을 생략하는 옵션이 아닙니다.

## 요청 및 검증

`POST` JSON 요청은 `authorizationCode`, 64자리 소문자 16진수 `rawNonce` 두 필드만 받습니다. `Authorization: Bearer <현재 Supabase 세션 토큰>`이 필요합니다. 앱은 Apple 재인증 과정에서 기존 Supabase 세션을 교체하면 안 됩니다.

1. 고정 Supabase 프로젝트의 사용자 API에서 세션을 검증합니다.
2. 서버가 반환한 `identities`에서 Apple `identity_data.sub` 또는 `provider_id`를 확인합니다. 두 값이 있으면 일치해야 합니다. 이메일·사용자 메타데이터·identity UUID는 사용하지 않습니다.
3. 5분 유효 ES256 client secret으로 Apple의 고정 token endpoint에서 코드를 교환합니다.
4. Apple 고정 JWKS endpoint의 RSA 공개 키로 응답 ID token의 RS256 서명을 검증합니다. issuer, audience, subject, nonce SHA-256, 만료·발급 시각도 검사합니다. 시계 오차는 미래 60초까지만 허용하고 발급 후 10분을 넘은 토큰은 거부합니다.
5. refresh token 우선, 없으면 access token을 철회합니다. revoke HTTP 200 이후에만 `{ "ok": true }`를 반환합니다.

요청 본문은 12 KiB, 외부 응답은 각각 64 KiB, 개별 네트워크 요청 및 본문 수신은 10초로 제한합니다. 리디렉션은 금지합니다. 토큰·코드·키는 저장하거나 로그에 남기지 않습니다. 재인증 코드는 일회용이므로 동일 코드의 실패를 이미 철회된 상태로 처리하지 않습니다.

| HTTP | error | 앱 처리 |
| --- | --- | --- |
| 400 | `invalid_request` | 요청 수정, 삭제 중지 |
| 401 | `session_invalid` | 세션 확인, 삭제 중지 |
| 409 | `apple_identity_mismatch` | 같은 Apple 계정으로 재인증, 삭제 중지 |
| 409 | `apple_verification_failed` | 검증 실패, 삭제 중지 |
| 503 | `apple_not_configured` | 서버 설정 필요 |
| 502 | `apple_unavailable` | 연결 또는 Apple 응답 실패 |
| 400 | `apple_reauthentication_required` | 새 Apple 인증 코드 필요 |

마지막 세 오류에서만 앱이 사용자의 명시적 선택을 받아 수동 Apple 연결 해제 안내와 계정 삭제를 제공할 수 있습니다. 세션·계정 불일치·서명 검증 오류를 우회하지 않습니다. 자동 철회 또는 데이터 삭제가 성공한 것처럼 표시하면 안 됩니다.

## 검증

`node --test supabase/tests/apple_disconnect.test.mjs`는 실제 생성한 EC/RSA 키와 가짜 HTTP 전송으로 서명, 계정/nonce 일치, 시간, 입력 제한, 리디렉션, 타임아웃, 응답 크기, 오류 정제, 성공 순서를 검사합니다. 실제 Apple 계정 철회·실제 서버 배포 검증을 대신하지 않습니다.

공식 근거: [Apple 사용자 검증](https://developer.apple.com/documentation/signinwithapplerestapi/verifying-a-user), [Apple 계정 삭제·토큰 철회 TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).
