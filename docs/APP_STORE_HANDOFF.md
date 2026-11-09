# App Store 등록 작업 인계 · 2026-11-08

맥북에서 이어가는 App Store 준비 작업 기록이다. 현재 브랜치에는 Flutter·iOS 실행 환경 복구와 Apple 로그인 보완이 포함된다. **TestFlight 1.0.0 (13) 배포와 Apple 연결 해제 서버 설정은 완료했다. 2026-11-08 사용자가 Apple 로그인·주차 저장 성공을 보고했고, 실기기 미러링 탐색·입력 취소 후 기록 보존 및 시뮬레이터 촬영 자료를 확인했다. 스토어 등록 자료·JPEG 8장과 App Privacy 답변 게시를 완료했고, App Store 버전 1.0은 심사 대기 중(`WAITING_FOR_REVIEW`)이다. 심사 승인·공개와 실제 철회·삭제 검증은 아직 완료되지 않았다.** 현재 검증 결과는 아래 최신 상태를 우선한다.

## 최신 확인 · App Store 심사 제출 완료 · 2026-11-08

- 비공개 `release/carcar-appstore-20261108`의 [등록 준비 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42486691651)가 성공했다. 설명·부제·`UTILITIES` 카테고리·개인정보/지원 링크, 타사 콘텐츠 권리 사용 없음, 저작권, 연령 등급을 반영하고 재조회했다.
- 기존 스토어 버전 **1.0**에 빌드 **1.0.0 (13)**을 연결했다. 심사 연락처와 한국어·영어 전 기능 접근 안내도 저장·검증했다. 개인 연락처 값은 공개 문서에 기록하지 않는다.
- 가격 **무료(0)**, 배포 국가 **대한민국(KOR)만**, 새 국가 자동 추가 꺼짐을 확인했다. 출시 옵션은 **`AFTER_APPROVAL`(심사 승인 후 출시)**이다.
- iPhone/iPad 각 4장, **JPEG 8장 모두 `COMPLETE`와 로컬 MD5 일치**를 확인했다. QA MOV와 비공개 실기기 영상은 스토어 미디어로 올리지 않았다.
- 공개 개인정보 안내는 `fa8d690`의 [사이트 게시 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42484097529) 성공과 HTTP 200으로 확인했다. 사용자·설치 식별자, 수동 주차 위치, 보안·운영 로그, 선택적 이메일 문의 처리를 반영했다.
- **App Privacy 답변 게시를 완료했다.** CUA로 열린 Chrome에서 12개 유형을 모두 앱 기능 목적·사용자 신원 연결·추적 사용 안 함으로 입력했다. 게시 확인창의 정확성·관련 법 준수·변경 시 갱신 문구에 사용자가 동의한 뒤 게시했고, 화면의 게시 완료 표시를 확인했다. [입력·게시 기록](app-store/privacy-console-steps.md)과 [분류 근거](app-store/privacy-answers.md)를 참고한다.
- **최종 심사 제출을 완료했다.** [제출 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42488929909)는 2026-11-08 **14:16:11 UTC / 23:16:11 KST**에 성공했다. `submission.json`의 `versionState`와 `submissionState`는 모두 **`WAITING_FOR_REVIEW`**, **`submitted=true`**, `blockers=[]`다. 스크린샷 8장 완료와 무료·KOR 한정 배포 설정도 함께 재확인했다.
- 심사 제출 ID는 `26696dda-35de-4157-a091-a4bf4bec0334`다. 증거는 비공개 `~/.local/share/carcar-release/appstore-runs/42488929909/carcar-appstore-registration-12/submission.json`에 보관한다. 이전 [제출 시도](https://github.com/kang88xx/60base-mobile-build/actions/runs/42487225872)의 `APP_DATA_USAGES_REQUIRED` 오류는 개인정보 게시 후 해소됐다. 현재는 Apple 심사 결과를 기다리며 중복 제출하지 않는다. 심사 승인이나 App Store 공개가 완료된 것은 아니다.
- 이번 도구 검증은 **Node 57/57개 통과**, Dart 포맷 **46개 파일·변경 0개**, `flutter analyze --no-pub` **문제 0개(2.4초)**다. 제품 코드는 `069dd4c` 그대로다. 심사 연락처 전달용 임시 secret은 작업 후 제거했고 잔여 0개를 확인했다.
- 아래 실기기 확인 범위와 미검증 항목은 그대로다. 심사 접수 완료는 실제 인증·삭제·가족 공유 검증이나 심사 통과를 뜻하지 않는다.

## 최신 확인 · 실기기 탐색과 스토어 촬영 자료 · 2026-11-08

- **사용자 확인:** 사용자가 TestFlight 13에서 Apple 로그인과 주차 저장이 됐다고 답했다. 이 인증·저장 성공은 사용자 보고이며 에이전트가 로그인 왕복이나 운영 저장을 재실행한 결과는 아니다.
- **직접 관찰:** iPhone Mirroring으로 실제 차자리의 로그인 상태와 홈·이력·가족·설정을 탐색했다. 기존 이력 2건을 확인하고 새 주차 위치를 입력한 뒤 취소 경고에서 나갔다. 홈 새로고침 후 기존 위치가 보존됨을 확인했다. 운영 저장·로그아웃·초대·계정 삭제는 수행하지 않았다.
- 실제 설치 빌드 번호는 기기 조회로 확인하지 못했다. Developer Mode가 꺼져 조회가 실패했으며 이를 켜지 않았다. 실기기 결과는 **사용자가 앞서 확인한 TestFlight 13 기준의 화면 관찰**로 기록한다. 카메라 OCR·Face ID·두 기기 가족 공유·푸시·계정 삭제/Apple 철회는 미검증이다.
- **실기기 QA 원본 저장·장면 검증 완료:** 미러링 창을 지정한 터미널 녹화로 `physical/terminal-capture/physical-iphone-qa.mov`를 생성했다. 원본은 **89.997초 / 742×1528 / 비디오 1개·오디오 없음**이다. 디코딩한 장면에서 가족(18초)·설정(26초)·입력(50~58초)·취소 확인(66초)·기존 홈 복귀(74~88초)를 확인했고 다른 Mac 앱은 포함되지 않았다. 새 로그인·운영 저장·OCR·가족 공유·계정 삭제 성공을 검증한 영상은 아니다. 정리본 `physical/derived/physical-iphone-qa.mp4`는 **84초 / 618×1344 / 오디오 없음**이며 최종 10개 장면에서 홈·이력·가족·설정·입력·취소·복귀·새로고침 완료를 확인했다. 폰 영역 자르기와 끝의 대기 구간 정리만 했고 UI 내용은 수정하지 않았다. 툴바·다른 Mac 앱은 없으며 약 90초 원본도 보존한다.
- 실기기 영상은 실제 개인정보가 있어 비공개 `~/.local/share/carcar-release/media-20261108/physical/`에서 관리하며 Git·공개 ZIP에 포함하지 않는다. 앞서 미러링 구간이 누락된 Mac 녹화 2개는 실패 진단 자료로 분리한다. 재촬영 시 화면 기록 권한을 확인하고 미러링 창 ID를 그때 조회해 지정하며, 파일 생성 뒤 실제 장면을 디코딩·검증한다.
- **시뮬레이터 촬영 완료:** iPhone 1320×2868과 iPad 2064×2752에서 홈·주차 입력·가족·이력 각 4장, 총 **JPEG 8장**을 준비했다. alpha 채널이 없고 8장 모두 시각 검토를 통과했다. 제품 코드는 TestFlight 13의 `069dd4c`와 동일하며 내장 체험 데이터를 사용했다. 네이티브 홈 화면 위젯 촬영은 남았다.
- 체험 동영상은 iPhone **28.25초**, iPad **29.42초**의 MOV 2개다. 시뮬레이터 QA 영상이며 App Preview 제출용 완성본은 아니다. 두 기기군의 통합 촬영 검사, 포맷·분석·Bash 문법·diff 검사를 통과했다. 실제 인증·서버 저장·가족 동기화 증거와 구분한다.
- 전달 폴더는 `build/app-store-media-20261108/delivery/`이며 `index.html`, `README.txt`, `manifest.json`에 갤러리·규격·검증 범위를 담았다. `build/app-store-media-20261108/차자리-스토어-촬영자료.zip`은 **13개 파일 / 7.99 MB**, ZIP 무결성 검사 통과다. 이후 메타데이터와 JPEG 8장 업로드는 완료했으며, 심사 제출 결과는 맨 위 등록 진행 상태를 따른다.

## 현재 배포 상태 · TestFlight 13 완료

- **설치 가능한 최신 빌드는 1.0.0 (13)**이다. [빌드 13 비공개 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42215777783)가 성공했고 Apple 처리 `VALID`, 만료 아님, 기존 내부 테스트 그룹에 빌드 연결을 확인했다. 기존 테스터의 그룹 소속도 확인했으며 초대 재전송이나 멤버 추가는 하지 않았다.
- 공개 WIP 브랜치 `wip/app-store-prep-2026-11-06`의 앱 소스 `069dd4c`를 push하고, 비공개 `release/carcar-apple-login-20261106` 브랜치의 `6b2ea85`로 동기화했다. 복사한 소스의 해시 일치를 검사했고 두 저장소의 main은 변경하지 않았다.
- CI는 Xcode 26.6에서 기존 배포 인증서·프로파일을 재사용해 실행했다. 인증서 생성·폐기는 없었다. 작업 시간은 2026-11-06 12:11:38–12:23:00 UTC, **11분 22초**다. 12:22:28 UTC의 배포 증거에서 build `13`, `processingState=VALID`, `ready=true`, `groupContainsBuild=true`를 확인했다.
- 그룹의 모든 미래 빌드 자동 접근 설정 변경은 변경 불가 409로 거절됐지만, 이번 빌드의 명시적 그룹 연결은 성공했다. 미래 빌드 자동 배포가 활성화됐다고 간주하지 않는다.
- Apple 로그인·계정 삭제·UIScene 전환과 함께 설정의 문의 UI를 공개 고객지원으로 변경하고 Apple 계정 삭제 안내를 개인정보 문구에 반영했다. 최종 로컬 검사: **Flutter 268개 통과 / 4개 선택 검사 건너뜀, Python 19개·Node 70개 통과**, 분석·포맷 성공.
- CI 실행 후 GitHub Billing 화면을 다시 확인했다. 포함 compute는 **$11.54 / $12**, 잔여액은 **$0.46**, 저장소는 **0.3 / 0.5 GB**, Actions 유료 청구는 **$0**이다. 추가 유료 예산은 **$0 / Usage blocked**를 유지한다. 이번 실행은 18분 timeout으로 제한했으며, 추가 비공개 macOS CI 실행 전 잔액·예산을 다시 확인하고 로컬 검증을 우선한다.
- 배포 로그·증거는 비공개 `~/.local/share/carcar-release/testflight-13/`, 로컬 출시 검사는 `build/release-prep/`에 보관한다. 이후의 사용자 보고·실기기 관찰·촬영 자료는 맨 위 2026-11-08 기록을 따른다. 스토어 등록 준비의 후속 결과는 맨 위 2026-11-08 기록을 따르며 실제 인증·철회·삭제 검증 범위는 별도로 유지한다.

아래는 단계별 작업 기록이다. 과거 단계의 검사 수·실패·미완료 표현은 당시 상태이며 현재 배포·검증 상태는 이 절을 우선한다.

## 맥북 재개 결과 · 2026-11-06

### Apple 철회 키·서버 배포 완료

- 사용자가 키 생성·서버 등록·배포를 승인한 뒤 `Chagok Apple Login` 키를 생성했다. Apple Developer에서 Sign in with Apple 권한과 차곡의 primary App ID 연결을 재확인했다. 기존 60BASE·APNs 키는 변경하지 않았다.
- 내려받은 개인 키의 형식을 검증하고 `~/.local/share/carcar-release/apple-sign-in/`에 보관했다. 디렉터리 권한은 0700, 파일은 0600이며 Downloads의 임시 사본은 제거했다. 키 값은 채팅·Git·앱에 넣지 않았다.
- `APPLE_SIGN_IN_*` 서버 secret 4개를 등록하고 새로고침 후 각 SHA-256이 로컬 값과 일치함을 확인했다. 기존 secret의 digest는 그대로다. `apple-disconnect`는 **ACTIVE / v1**이며 원격에서 다시 받은 3개 소스 파일이 로컬 배포 파일과 정확히 일치한다.
- 운영 endpoint에서 Authorization 누락·가짜 bearer는 **401 `session_invalid`**, 잘못된 JSON은 **400 `invalid_request`**를 반환했고 모두 `Cache-Control: no-store`였다. 실제 Apple 자격·토큰 교환·철회나 계정 삭제는 실행하지 않았다.
- 기존 `parking-push`의 소스 checksum은 그대로다. 프로젝트 공통 secret 갱신에 따라 버전만 **v1→v2**로 자동 변경됐다.
- 공개 가능한 검증 기록은 로컬 `build/account-deletion-qa/production-smoke.json`과 `verification.json`, 키·서버 설정 영수증은 비공개 `~/.local/share/carcar-release/apple-sign-in/setup-receipt.json`에 보관한다. 다음은 서명된 실제 iPhone의 Apple/Google 로그인과 통제된 삭제 검증이며, 빌드 13 배포 완료 증거는 맨 위 기록을 따른다.

### 계정 삭제 보호·Apple 연결 해제 구현 및 로컬 검증

- 삭제 시작 시 사용자와 access token을 고정하고, 해당 토큰으로 서버 사용자·연결 identity를 다시 조회한다. Apple 계정이면 네이티브 재인증 자격만 얻으며 공유 Supabase 로그인 세션을 교체하지 않는다. 재인증·수동 확인·서버 요청 사이에 계정이 바뀌면 중단한다. A→B→A 전환도 이전 요청을 되살리지 않는다.
- `apple-disconnect`는 서버 identity와 Apple token endpoint 응답을 비교한다. 고정 JWKS의 RS256 서명, issuer·audience·시간·subject·nonce를 검증한 뒤에만 Apple 토큰을 철회한다. 이 함수에는 DB 삭제 권한이나 service role 키가 없고, 토큰을 저장·출력하지 않는다. 설정·오류 계약은 [서버 함수 배포 문서](../supabase/deployment/APPLE_SIGN_IN.md)를 따른다.
- 네이티브 Apple 인증의 알려진 일시 실패·지원 불가도 `apple_unavailable`로 분류한다. `apple_not_configured`, `apple_unavailable`, `apple_reauthentication_required`에서만 별도 확인을 받아 계정 삭제와 수동 Apple 연결 해제 안내를 제공한다. 사용자 취소·identity 불일치·서명 검증 실패·세션 변경은 삭제를 진행하지 않는다.
- 실제 삭제 RPC의 Authorization도 최초 bearer로 고정한다. 서버 삭제 성공 뒤 같은 세션일 때만 로컬 로그아웃하며, 뒤늦은 완료·auth 이벤트가 새 계정 화면을 지우지 않게 했다. 로컬 로그아웃 네트워크 실패를 서버 삭제 실패로 바꾸지 않는다.
- 로컬 검증: `flutter test --no-pub` **267개 통과 / 4개 선택 검사 건너뜀**, `flutter analyze --no-pub` **No issues found**, Dart 포맷 **45개 / 변경 0**. 추가 56개는 저장소 37개·삭제 UI 12개·루트 세션 7개이며 실제 Supabase SDK와 로컬 HTTP를 사용한 경합 검사를 포함한다. Node 선택 검사 **52개 통과**(Apple 함수 14개 포함), Deno `check`도 종료 0이다.
- 검증 로그와 코드 해시는 로컬 `build/account-deletion-qa/verification.json` 및 같은 폴더에 보관했다. 웹 release 빌드도 종료 0이다.
- 변경 후 iOS Simulator debug 빌드와 패키징 검사를 다시 통과해 **앱 iOS 15.0 / 위젯 iOS 17.0**을 확인했다. 앱 삭제 흐름·Edge 보안 코드의 독립 검토에서도 차단 결함은 발견하지 못했다. 이 빌드 성공은 실제 Apple 인증·철회를 대신하지 않는다.
- 위 로컬 검증 후 키·서버 설정 및 Edge 배포를 완료했다. 운영 endpoint의 입력·인증 거절 검사는 위 배포 기록을 따른다. 실제 Apple 인증·철회·계정 삭제는 아직 검증하지 않았다. 빌드 13 배포 완료 증거는 맨 위 기록을 따른다.

### Apple 로그인 설정 1단계 완료

- 사용자 요청으로 기존 로그인된 Apple Developer에서 `com.kang88.carcar`의 **Sign In with Apple을 primary App ID로 활성화**했다. 저장 후 페이지를 다시 열어 체크 상태와 primary 구성을 확인했다. 다른 앱과 그룹화하거나 다른 앱 설정을 바꾸지 않았다.
- 기존 `Chagok App Store Push 20261102` 프로파일을 같은 Distribution 인증서 선택으로 재생성했다. 새 인증서를 발급·폐기하지 않았다. 내려받은 프로파일을 기존 `validate_profile`로 검사해 앱 Bundle ID·Team·App Group·공유 Keychain·App Store 유형·production APNs·`com.apple.developer.applesignin = [Default]`를 확인했다. Xcode 프로파일 저장소에도 설치했다. 위젯 프로파일은 변경하지 않았다.
- 차자리 Supabase 프로젝트의 Apple provider를 활성화하고 Client IDs를 `com.kang88.carcar`로 설정했다. 페이지 새로고침 후 enabled와 Client ID를 재확인했다. 기존 Google provider는 enabled를 유지한다. 네이티브 ID-token 로그인 범위이므로 웹 OAuth Secret Key와 Services ID는 추가하지 않았다. 이는 추후 Apple 토큰 철회용 개인 키가 불필요하다는 뜻이 아니다.
- 원격 설정 증거는 비공개 `~/.local/share/carcar-release/apple-login-setup-receipt.json`, 프로파일 검증은 같은 경로의 `profiles/apple-sign-in-app-receipt.json`에 저장했다. 프로파일 파일은 Git에 넣지 않았다.
- 현재 Mac Keychain에는 해당 배포 인증서와 일치하는 서명 identity가 **0개**다. 새 기기용 서명 빌드에는 기존 비공개 CI의 개인 키를 안전하게 이전하거나 기존 CI를 사용해야 한다. 이후 기존 비공개 CI 자격으로 빌드 13 배포를 완료했다. Mac 개인 키 이전과 실제 Apple 로그인 검증은 여전히 별도다.

### 최신 상태: Flutter 업그레이드와 UIScene 전환

- 사용자가 Flutter 업그레이드를 승인했다. 현재 기준은 **Flutter 3.47.9 / Dart 3.13.7**이며 공개 CI 3개도 같은 버전으로 고정했다. 새 SDK는 `~/development/flutter-3.47.9`, 이전 3.35.4 SDK는 `~/development/flutter`에 보존했다. 로컬 명령은 `PATH="$HOME/development/flutter-3.47.9/bin:$PATH"`와 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 사용한다.
- `Info.plist`의 Scene Manifest와 `SceneDelegate`를 추가하고, 플러그인·`carcar/native` 채널 등록을 implicit engine 초기화로 옮겼다. 공유 시트·Apple 인증은 현재 활성 scene의 key window를 사용한다. `app_links 6.4.1`의 cold URL/user activity는 직접 전달하고 warm 이벤트는 Flutter의 기존 plugin fallback으로 전달한다. 같은 이벤트를 두 경로에서 중복 전달하지 않는다.
- SDK가 생성한 Swift Package Manager 연결을 유지하며, `flutter_secure_storage 9.2.4`는 CocoaPods fallback으로 빌드한다. 향후 Flutter에서는 이 플러그인의 SwiftPM 지원이 필요하다는 경고가 남는다. 직접 의존성을 추가하거나 플러그인 버전을 임의로 올리지 않았다.
- 새 Flutter의 ListTile 검사에서 기존 장식 배경이 Material ink를 가리는 오류를 발견했다. 공통 `Surface`를 `Material + Padding`으로 바꾸고 사이드바에서 재사용했다. 색상·반경·여백을 유지했고 assertion이나 검사를 끄지 않았다.
- `flutter analyze --no-pub`: **No issues found**. `flutter test --no-pub`: **211개 통과 / 4개 선택 검사 건너뜀**, 종료 0. 기존 검사로 호환성 오류 해결을 확인했다. `flutter build web --release --no-pub`도 성공했다. 기존 secure-storage의 Wasm 비호환·Cupertino 폰트 경고는 남고 JavaScript 웹 빌드는 정상 생성됐다.
- 네이티브 QA의 첫 재실행은 Dart 테스트까지 진입했으나 스크롤 직후 이전 좌표로 기록 버튼을 눌러 실패했다. `integration_test/native_app_test.dart`는 버튼을 스크롤 중앙에 놓고 프레임을 반영한 다음 hit-test 가능 여부를 검사하도록 수정했다. 기능 assertion은 유지했고 나머지 큰 diff는 새 formatter에 따른 형식 변경이다.
- 아이콘 알림 도우미는 기존 영어 문구 외에 실제 한국어 `‘차자리’ 아이콘을 변경했습니다.`와 `확인` 버튼의 정확한 조합을 지원한다. 일반 알림을 임의로 닫지 않는다. 실패한 실행이 남긴 시스템 알림은 앱 삭제만으로 사라지지 않아, 재실행 전에 잔류 알림과 앱을 정리했다.
- 프로필 편집 검사는 옛 `AlertDialog` 가정 대신 실제 `ProfileEditorDialog`와 내부 이름 입력란을 검증한다. 편집 취소 후 이름·차량·기록이 그대로인지 확인하며, 제품 동작이나 기능 assertion을 줄이지 않았다. 관련 주차 배치 8개·계정 사용성 13개 검사도 통과했다.
- `flutter build ios --simulator --debug --no-pub`: **성공**, 3.35의 fat binary 검사 오류와 시작 시 UIScene 크래시를 해결했다. 빌드 앱 검사에서 **앱 15.0 / 위젯 17.0**을 유지했다. iPhone 18 Pro / iOS 27.2에서 실제 화면과 cold 초대·주차 입력 링크 진입을 확인했다.
- `bash scripts/ios_qa.sh`: **최종 종료 0**, `test-complete`와 `All tests passed` 확인. 실제 기기 내 Vision OCR이 테스트 표지 `B2 / C / 24`를 읽었고, 체험 `B3 / D / 52` 저장·저장소 재조회·이력·층수 아이콘·위젯 안내→설정·프로필 편집 취소가 통과했다. 별도 XCTest가 이번 실행의 아이콘 안내 2회를 처리했고, 앱/위젯 패키징과 APNs 빌드 설정 검사도 통과했다.
- 최종 네이티브 증거는 **`build/ios-runtime-qa-347-verified/`**의 `integration.log`, `observations.json`, `icon-alerts.xcresult`, `deployment-targets.json`, 화면 캡처 10장이다. 이전 `ios-runtime-qa*` 디렉터리의 실패·중단 기록과 구분한다. Flutter 분석·전체 테스트·포맷 41개 변경 0·웹 빌드 로그는 `build/macos-continuation/flutter-347/`에 보관했다.
- 일반 앱을 다시 빌드해 실행 중 초대 링크 수신과 홈→주차 입력 진입을 확인했다. 종료 상태의 초대·주차 입력, 열린 입력창의 중복 주차 링크와 초안 보존, cold/warm 인증 취소 콜백 뒤 앱 생존도 확인했다. `build/ios-scene-links/RESULTS.md`와 화면 캡처에 기록했다. synthetic 초대·서버 설정 없는 환경이므로 실제 초대 수락이나 OAuth 왕복 성공을 뜻하지 않는다.
- 이 QA는 실제 서버 인증·푸시 전송·홈 위젯 배치·서명 archive를 검증하지 않으며, 저장소 재조회는 앱 프로세스 재시작 검사가 아니다. 실제 Apple/Google 인증, 계정 삭제·철회와 새 배포·심사 제출은 남아 있다. 원격 capability·provider 설정은 위 1단계 완료 기록을 따른다. 아래 3.35 환경의 실패 기록은 원인과 비교 근거로 보존한다.

### 추가 환경 준비와 서명 검사

- `brew install cocoapods` 완료, `pod --version` **1.17.0** 확인. Xcode 미설치를 확인하는 데서 멈추지 않고 App Store의 기존 Xcode 다시 다운로드를 실행했다.
- App Store가 기존 Apple 계정의 암호를 요구해 사용자가 시스템 창에서 직접 로그인했다. 이후 다운로드·설치 완료, **Xcode 27.2 / Build 27B52**를 확인했다. 암호는 채팅·Git·로그로 받지 않는다. 첫 실행의 약관 화면이 외부 조작으로 넘어갔고 에이전트는 Agree를 누르지 않았다. 사용자의 재열기 요청으로 설치된 `License.pdf`를 미리보기에 열었다.
- `fastlane/Gemfile.lock`에는 `arm64-darwin-27` 플랫폼만 추가했다. 패키지 버전은 유지했고 Bundler 설치 및 `generate_ios_alert_watcher.rb`의 XCTest 프로젝트 생성이 성공했다. Ruby 4/Bundler 2.4의 상수 중복 경고가 있으나 생성기 종료는 0이다.
- 현재 로컬 Ruby 도구 실행에는 `PATH=/opt/homebrew/opt/ruby/bin:$PATH`, `GEM_PATH=$PWD/build/fastlane-local/vendor/bundle/ruby/4.0.0`, `BUNDLE_PATH=$PWD/build/fastlane-local/vendor/bundle`, `BUNDLE_GEMFILE=fastlane/Gemfile`을 사용했다. 생성물은 ignored `build/` 아래에 보관한다.
- 초기 설정 완료 후 iOS SDK·Simulator 설치를 시작했다. Xcode의 별도 외부 에이전트 도구 연결은 `Never`로 선택했다. 명령에는 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 지정하므로 시스템 전역 `xcode-select`를 변경할 필요가 없다.
- `fastlane/prepare_signing.py`는 APP 프로파일에 `com.apple.developer.applesignin = [Default]`를 요구한다. Widget 프로파일에는 이 권한을 요구하지 않는다.
- 비공개/ignored `fastlane/prepare_existing_signing.mjs`도 앱 프로파일 재사용 및 신규 발급 결과에서 Apple entitlement를 검사한다. 전체 plist는 날짜·바이너리가 있어 JSON 변환할 수 없으므로 `Entitlements`만 추출한다. 당시에는 비공개 배포 저장소에 동기화하지 않았으며, 이후 빌드 13 브랜치에 반영했다.
- 서명 회귀: Python **19개**, Node **9개** 통과. Node 검사는 실제 `plutil`로 날짜·인증서 data가 포함된 plist를 읽는 경우도 포함한다. 원격 Apple capability나 프로파일을 변경한 것은 아니다.

### Apple 로그인 세션 경합 수정

- 코드 검토에서 shared `signInWithIdToken`의 HTTP 응답이 늦으면 그사이 로그인한 다른 계정을 덮는 문제를 확인했다. 네이티브 자격 반환 직후 검사만으로는 막을 수 없었다.
- `main.dart`가 같은 서버 설정의 별도 `GoTrueClient(autoRefreshToken: false)` factory를 전달한다. `auth_screen.dart`는 이 클라이언트에서 교환하고, 화면 수명·클라이언트 동일성·인증 이벤트 세대·현재 로그아웃 상태를 확인한 뒤에만 공유 세션을 반영한다.
- SDK의 초기 이벤트 replay는 화면 생성 시부터 구독해 처리한다. refresh token과 60초 이상 남은 만료 시각을 검증해 `recoverSession`의 네트워크 갱신 경로로 들어가지 않게 한다. 만료되지 않은 세션 반영은 설치 SDK에서 첫 await 전에 수행된다. SDK 변경 시 이 경계를 다시 검증한다.
- 인증·계정 검사 **36개**, 전체 Flutter 검사 **211개 통과/4개 선택 검사 건너뜀**. 실제 SDK + 로컬 HTTP를 사용하는 정상 로그인·replay·계정 전환 검사를 포함한다. 정적 분석, 포맷 40개 변경 0, 별도 코드 리뷰 통과. 실제 Apple 서버 로그인은 별도다.

### 로컬 Xcode 컴파일

- 실제 빌드에서 `PODS_ROOT` 설정 누락 및 플러그인의 iOS 9/12/13 타깃 오류를 확인했다. `ios/Flutter/Debug.xcconfig`와 `Release.xcconfig`에 Pods 설정을 포함하고, `ios/Podfile`에서 pod 최소 버전이 15보다 낮을 때만 15로 올렸다. CocoaPods의 프로젝트/workspace 연결 변경을 유지했다.
- 일반 `flutter build ios --simulator --debug --no-pub`는 그다음 Flutter 3.35의 fat binary 아키텍처 검사에서 실패했다. 요구 `arm64 x86_64`와 실제 `x86_64 arm64`의 검사 문제이며 SDK 파일이나 Intel 지원을 변경하지 않았다.
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**, 종료 0. Apple 로그인 Swift와 위젯을 포함한다.
- 생성된 앱에 `scripts/check_ios_deployment.py`를 실행해 **앱 15.0 / 위젯 17.0**을 확인했다. Simulator 런타임 설치 후 특정 기기를 지정해 실행 검증한다. 이 빌드는 실제 서버 인증·서명 archive 검증을 대신하지 않는다.

### 이전 Flutter 3.35 환경의 iOS 27 실행 실패 기록

- iOS 27.2 Simulator 설치 완료 후 iPhone 18 Pro에서 `bash scripts/ios_qa.sh` 실행. 도우미 XCTest와 앱 컴파일은 성공했으나 Runner가 Dart `test-start` 이전에 종료돼 **네이티브 QA는 미통과**다. 정체된 driver를 종료하고 스크립트가 이 실행에서 부팅한 Simulator를 정리했다.
- Runner 크래시의 첫 프레임은 `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`이며, 시스템 로그는 `UIScene life cycle is required for apps built with this SDK`라고 명시한다. 아이콘 도우미의 Lost connection은 앱 종료 뒤의 2차 오류다.
- 이 실패 당시 `Info.plist`에는 Scene Manifest가 없었고 `AppDelegate.swift`의 채널 등록은 이전 `window.rootViewController` 시점에 의존한다. [Apple 공식 전환 안내](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)와 일치하는 실행 차단이다.
- [Flutter 공식 UIScene 지원](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)은 3.38부터이고 기본 전환은 3.41부터다. 3.35에는 초기 SceneDelegate/옛 pluginRegistrant API만 있어 수동 호환 구현은 가능성을 검증해야 하며, 최신 implicit-engine 예제를 그대로 적용할 수 없다.
- 사용자에게 두 방식의 방향을 확인한 뒤 **지원 Flutter로 업그레이드하는 안을 승인받았다**. 이후 구현·검증은 맨 위 최신 상태에 기록한다.
- 근거: `build/ios-runtime-qa/`의 integration·icon-watcher 로그 및 `stalled-startup.png`, `build/macos-continuation/`의 빌드·회귀 로그. 이번 작업에서 새 TestFlight 배포·App Store 제출은 하지 않았다.

### 첫 재개 검증 기록

- 기존 `wip/app-store-prep-2026-11-06` 브랜치에서 이어갔다. 운영 코드와 서버 설정은 변경하지 않았다.
- Flutter 3.35.4 / Dart 3.9.2를 `~/development/flutter`에 설치하고 `flutter pub get`으로 이전 Linux 경로를 참조하던 로컬 의존성 정보를 복구했다. 실행 시 `export PATH="$HOME/development/flutter/bin:$PATH"`를 사용한다. 의존성 버전은 변경하지 않았다.
- `test/apple_auth_test.dart`: widget test의 플랫폼을 `TargetPlatformVariant`로 관리하고, 아이콘 버튼의 하위 타입까지 찾는 finder로 수정했다. iOS/Android 노출 검사는 각각 실행한다.
- `flutter test --no-pub test/apple_auth_test.dart test/account_usability_test.dart`: **28개 통과**, 종료 0. 기존 로그인 검사 13개를 포함하며 실제 Apple/Supabase 인증 성공을 뜻하지 않는다.
- `dart format --output=none --set-exit-if-changed lib test`: **40개 파일, 변경 0**, 종료 0.
- `flutter analyze --no-pub`: **No issues found**, 종료 0.
- `flutter test --no-pub`: **203개 통과, 4개 건너뜀**, 종료 0. 선택 실행하는 iOS 캡처 검사는 별도다.
- `flutter build web --release --no-pub`: 성공, 종료 0. 기존 secure-storage의 Wasm 비호환 및 Cupertino 폰트 경고가 남아 있으며 일반 JavaScript 웹 빌드는 생성됐다.
- `python3 fastlane/test_prepare_signing.py`: **18개 통과**. `node --test supabase/tests/push_worker.test.mjs`: **15개 통과**.
- `swiftc -frontend -parse ios/Runner/AppDelegate.swift`: 문법 검사 통과. iOS SDK 타입 검사나 링크·실행 검증이 아니다.
- `flutter build ios --simulator --debug --no-pub`: **종료 1**, `Application not configured for iOS`. 프로젝트 파일은 존재하지만 현재 Xcode 환경에서 빌드 구성을 조회·컴파일하지 못했다.
- `flutter doctor -v`와 `xcodebuild -version`: 전체 Xcode가 없고 `/Library/Developer/CommandLineTools`만 활성화돼 있다. CocoaPods·iOS Simulator도 준비되지 않아 **다음 단계는 Xcode 환경 준비 후 네이티브 컴파일**이다. Android SDK도 없으나 이번 단계는 iOS 우선이다.
- 실제 Apple 로그인, App ID capability·서명 프로파일, Supabase Apple provider, 계정 삭제·철회, App Store 제출은 여전히 미완료다. 새 배포나 유료 CI 실행은 하지 않았다.

추가 코드 검토 항목: Apple 버튼의 공식 로고·규격, `credentialRevokedNotification` 및 `getCredentialState`를 통한 철회 감지. nonce 전달 방식은 [Supabase Dart 계약](https://supabase.com/docs/reference/dart/auth-signinwithidtoken)과 일치한다. 버튼은 [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple/), 철회는 [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)를 기준으로 후속 검증한다.

아래의 실패 횟수와 중단 상황은 **맥북 재개 이전 기록**이다. 현재 검증 결과는 위 내용을 우선한다.

## 맥북에서 이어가기

소스 저장소: `git@github.com:kang88xx/carcar-kang88.git`

```sh
git fetch origin
git switch --track origin/wip/app-store-prep-2026-11-06
```

이미 이 로컬 브랜치가 있으면 `git switch wip/app-store-prep-2026-11-06`을 사용한다. 기존 작업 파일이 있는 맥북 체크아웃은 변경을 덮어쓰지 말고 별도 checkout/worktree를 사용한다.

다음 작업자는 이 문서, `AGENTS.md`, 프로젝트 기본 문서 및 `docs/app-store/submission-draft.json`을 먼저 읽는다. Flutter 3.47.9 / Dart 3.13.7이 현재 프로젝트 기준이다.

## 사용자 확정 사항

- 기존 유료 Apple Developer 계정으로 App Store 등록을 진행한다. 신규 계정 결제나 유료 서버 도입은 요청하지 않았다.
- 앱 가격: 무료. 최초 배포 국가: 대한민국.
- 공개 고객지원 이메일: `kang88xx@gmail.com`.
- 심사용 이름·이메일·전화번호는 받았으며 비공개로 취급한다. 공개 저장소에 넣지 않았다.
- 이번 작업과 테스트는 iOS 우선이다. Android 실기기 검증은 나중에 진행한다.

## 완료·게시된 결과

- 최신 TestFlight: **1.0.0 (13)**. Apple 처리 `VALID`, 기존 내부 테스트 그룹 연결 완료. 소스·CI·검증 증거는 맨 위 현재 배포 상태를 따른다.
- 아래 빌드 12 항목은 이전 배포 이력이다.
- 빌드 12의 앱 소스는 `f3373a6`, 비공개 빌드 소스는 `cdace91`. 이후 문서 커밋은 바이너리 변경이 아니다.
- [빌드 12 배포 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42171293207), [공개 앱 검증](https://github.com/kang88xx/carcar-kang88/actions/runs/42171242680) 성공.
- 네 탭 헤더 고정과 작은 화면 기록 버튼 문구 수정: Flutter 188개, 별도 화면 검사 4개/44장 통과. 최신 실제 iPhone 동작 확인은 별도다.
- 지원 사이트와 등록 초안은 main의 `243c3b8`에 저장·push했다. [사이트 게시 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42180853820), [해당 main 검증 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42180853943) 성공.
- 공개 지원 페이지: https://kang88xx.github.io/carcar-kang88/support/
- 개인정보 페이지: https://kang88xx.github.io/carcar-kang88/privacy/
- `site/support/index.html`, 홈의 지원 링크, 공개 개인정보 페이지의 위젯 설명·문의 경로를 정리했다. 지원 사이트의 320/768/1280px 브라우저 검사와 링크 16개 검사를 통과했다.
- `docs/app-store/submission-draft.json`: 한국어 설명·부제·키워드·스크린샷 촬영 계획과 무료/KOR 설정 초안. 문자열 제한·키워드 UTF-8 100바이트 제한을 검사했다. 자동 업로드/제출 도구는 아니다.

## App Store Connect 조회 결과 · 2026-11-06 당시 기록

아래 빈 필드와 미실행 표현은 당시 상태다. 2026-11-08 반영·업로드 결과는 맨 위 최신 기록을 우선한다.

2026-11-06 조회 시 등록명은 `차자리 - 가족 주차 기록`, 기본 언어 `ko`, iOS 버전 `1.0`은 `PREPARE_FOR_SUBMISSION`이었다.

- 설명·키워드·스크린샷·지원 URL·부제·개인정보 URL·저작권자·카테고리가 비어 있다.
- 선택된 심사용 빌드와 App Review 연락처/로그인 정보가 없다.
- 연령 등급 답변이 비어 있다. App Privacy 신고 완료 여부와 가격/판매 국가의 실제 서버 설정은 아직 확인하지 않았다.
- 기존 출시 옵션은 `AFTER_APPROVAL`이다. 초안은 승인 후 수동 출시를 제안하지만 원격 설정은 바꾸지 않았다. 제출 전에 출시 방식을 명확히 확인한다.
- App Store Connect 메타데이터 수정, 심사 제출, 공개 출시는 아직 실행하지 않았다.
- 바이너리는 iPhone과 iPad(`TARGETED_DEVICE_FAMILY = 1,2`)를 지원한다. 두 기기군의 스토어 스크린샷이 필요하다. 기존 작은 QA PNG를 실제 기기 캡처로 가장하지 않는다.

## 맥북 재개 전 미완성 코드 기록

이 절은 이전 인계 시점의 기록이다. 아래 중단·검사 실패는 이후 구현과 검증으로 해결했으며 최신 결과는 맨 위를 따른다. 당시 다음 다섯 파일을 Apple 로그인 작업 중 사용자의 저장 요청으로 중단했다.

- `ios/Runner/AppDelegate.swift`: AuthenticationServices/CryptoKit 기반 Apple 인증 요청, nonce/state, delegate와 presentation anchor.
- `ios/Runner/Runner.entitlements`: `com.apple.developer.applesignin = [Default]` 추가.
- `lib/core/native_bridge.dart`: iOS 전용 `supportsAppleSignIn`, `AppleCredential`, `signInWithApple()` 추가.
- `lib/features/auth_screen.dart`: 기존 Google 로그인을 유지하며 iOS Apple 버튼과 Supabase ID token 로그인 추가.
- `test/apple_auth_test.dart`: 신규 테스트 초안.

당시 정한 NativeBridge 계약:

```text
signInWithApple() -> Future<AppleCredential?>
사용자 취소 -> null
필드: identityToken, authorizationCode, userIdentifier, rawNonce, fullName?
MethodChannel: carcar/native / signInWithApple
```

최초 이름은 반환하지만 기존 프로필 nickname/metadata를 자동 덮어쓰지 않는다. 실제 계정의 표시 이름 처리는 후속 검토 대상이다.

### 맥북 재개 전 검사 결과

- 수정 Dart 파일 포맷 완료, `git diff --check` 통과.
- `flutter test --no-pub test/apple_auth_test.dart test/account_usability_test.dart`: **17 통과 / 10 실패**, 종료 코드 1.
- 기존 `account_usability_test.dart` 13개는 통과했다.
- 신규 테스트의 `debugDefaultTargetPlatformOverride` 복원이 테스트 invariant 검사보다 늦고, `FilledButton.icon`/`OutlinedButton.icon`을 `find.byType(FilledButton/OutlinedButton)`으로 찾는 일부 finder가 실패한다. 플랫폼 variant/복원 및 실제 버튼 타입에 맞는 finder 수정부터 진행한다.
- 이 브랜치 전체 `flutter analyze`, 전체 회귀, Swift 컴파일, 실제 Apple 로그인은 아직 검증하지 않았다.
- 위 실패는 앞서 검증·배포된 TestFlight 12와 별개다.

## Apple·서버 설정의 현재 상태

- 기존 App ID는 `com.kang88.carcar`, Widget은 `com.kang88.carcar.ParkingWidget`이다. 식별자는 바꾸지 않는다.
- `com.kang88.carcar`의 Sign In with Apple primary 설정은 **활성화 완료 및 재조회 확인**했다. 기존 App Groups/Push를 유지했다.
- 이전 API 요청은 HTTP 409로 실패했으나 이번에는 Developer 사이트의 해당 App ID에서 저장·재조회했다. 과거 409의 정확한 원인을 확정하지 않는다. 공식 API의 capability는 `APPLE_ID_AUTH`, primary 설정 key는 `APPLE_ID_AUTH_APP_CONSENT` / option `PRIMARY_APP_CONSENT`다.
- 차자리용 `Chagok Apple Login` 키를 생성·다운로드·검증해 보호 저장했다. 다른 앱 `60BASE`의 기존 Apple 로그인 키와 APNs 키는 변경하지 않았다.
- Supabase Apple provider 활성화와 Client IDs의 `com.kang88.carcar` 등록은 **완료 및 새로고침 후 확인**했다. 철회용 secret 4개 등록과 `apple-disconnect` 배포·원격 소스 일치 검사도 완료했다.
- 앱 배포 프로파일은 기존 배포 인증서를 유지해 갱신했으며 Apple 로그인 entitlement와 기존 권한 검사를 통과했다. CI 재사용/검증 로직도 비공개 빌드 13 브랜치에 동기화했다. Mac의 배포 개인 키는 여전히 별도 준비가 필요하며 현재 배포는 기존 CI 자격을 사용한다.
- 계정 삭제 보호·Apple 연결 해제 앱/서버 코드의 로컬 회귀, 원격 함수 배포와 입력·인증 거절 검사를 완료했다. 실제 Apple 인증·철회·계정 삭제 검증은 남았다.

## 다음 작업 순서

1. **로컬 완료:** Apple 테스트·세션 경합 보완, 코드 검토·분석·전체 회귀, Flutter 3.47.9 전환과 iOS Simulator 네이티브 QA·링크 확인. 실제 기기 인증은 7번에서 검증한다.
2. **설정 완료:** App ID Apple 로그인 활성화 및 기존 배포 인증서로 앱 프로파일 갱신·권한 검사. 비공개 빌드 13 브랜치 동기화도 완료했다. Mac의 배포 개인 키는 없으므로 현재는 기존 CI 자격으로 서명한다.
3. **설정 완료:** Supabase Apple provider 활성화, Client IDs의 `com.kang88.carcar` 등록. 네이티브 전용 범위로 기존 nonce 검증과 Google 설정을 유지했다. 실제 서명 앱에서 로그인 왕복 검증은 7번에 남아 있다.
4. **서버 배포 완료:** 차자리 전용 Apple 로그인 키·서버 secret 등록과 `apple-disconnect` 배포, 원격 소스 일치 및 입력·인증 거절 검사를 완료했다. 실제 Apple 왕복은 7번에서 검증한다.
5. **앱 배포 완료:** 계정 전환 방어와 Apple 연결 해제/수동 fallback을 TestFlight 빌드 13에 포함했다. 실제 기기에 설치한 뒤 7번의 인증·삭제 검증을 수행한다.
6. **앱 코드 완료:** 문의 UI를 공개 고객지원으로 바꾸고 개인정보 문구에 Apple 재인증·삭제·수동 연결 해제 안내를 반영했다. TestFlight 빌드 13에 포함했다.
7. **일부 확인:** Apple 로그인·저장 성공은 사용자 보고, 로그인된 실기기 화면 탐색과 입력 취소 후 기존 기록 보존은 직접 관찰했다. 설치 빌드 번호 직접 조회·인증 재시도·카메라 OCR·Face ID·두 기기 공유·푸시·계정 삭제/철회는 남았다. 실기기 QA 원본과 84초 정리본의 폰 조작·취소·새로고침 장면 검증은 완료했다. Apple 비공개 이메일을 추측해 Google 계정과 합치지 않는다.
8. **등록 자료 반영 완료:** iPhone/iPad의 홈·입력·가족·이력 각 4장을 업로드·검증했고 연령 등급·저작권·심사용 전 기능 접근 안내도 반영했다. 네이티브 홈 위젯 촬영은 남았다. QA MOV는 App Preview 제출본이 아니며 체험 데이터는 실제 가족 공유 심사용 접근을 대신하지 않는다.
9. **심사 제출 완료:** 개인정보 12개 유형을 게시하고 [최종 제출 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42488929909)에서 빌드 13의 `WAITING_FOR_REVIEW`, `submitted=true`를 확인했다. 무료·대한민국 한정·심사 승인 후 자동 출시 설정을 유지한다.
10. **Apple 심사 결과 대기:** [App Store Connect 앱 심사](https://appstoreconnect.apple.com/apps/6829616379/distribution/reviewsubmissions)에서 결과와 추가 정보 요청을 확인한다. 현재 제출을 다시 실행하지 않는다. Apple의 요청이 있으면 해당 내용을 근거로 대응하고, 승인 후 공개 상태는 별도로 확인한다. 7번의 미검증 실기기 항목은 심사 접수와 별도로 남아 있다.

### 구현한 삭제 흐름의 보안 경계

- 삭제 재인증에서 `signInWithIdToken`으로 Supabase 세션을 교체하지 않는다. 기존 bearer를 유지한 채 native 자격만 얻는다.
- `apple-disconnect` Edge 입력은 `authorizationCode`와 `rawNonce`로 제한한다.
- Edge가 Supabase `/auth/v1/user`로 bearer를 검증하고 서버 identity의 Apple `sub`를 확보한다. 이메일·클라이언트 userId를 권한 근거로 사용하지 않는다.
- 고정 Apple HTTPS `/auth/token` 응답의 ID token을 고정 JWKS의 RS256 공개키로 검증한다. issuer/audience/시간/subject/nonce도 검사하고 현재 사용자와 일치할 때 반환 토큰을 `/auth/revoke`로 철회한다. TLS 검증만으로 서명 검증을 대체하지 않으며 redirect 차단·시간/크기 제한·토큰 로그 금지를 지킨다.
- 배포에 필요한 서버 secret 이름: `APPLE_SIGN_IN_TEAM_ID`, `APPLE_SIGN_IN_KEY_ID`, `APPLE_SIGN_IN_PRIVATE_KEY`, `APPLE_SIGN_IN_CLIENT_ID`. 일반 Supabase URL/anon 설정과 함께 사용하되 키는 앱·Git에 넣지 않는다.
- 철회 또는 별도 수동 해제 확인 뒤 기존 `delete_my_account` RPC를 실행한다. 삭제 시작/각 비동기 경계에서 사용자·세션 변경을 검사하고, 캡처한 access token으로 RPC Authorization을 고정했다. 서버 성공 뒤 같은 세션일 때만 local sign-out을 한다.
- 토큰 부재·일시 장애로 계정 삭제를 영구 차단하면 안 된다. 재시도/취소 또는 명시적인 계정 삭제 후 수동 Apple 접근 철회 안내를 제공한다. identity 불일치·세션 변경은 자동 fallback으로 넘기지 않는다.
- 장기 Apple 토큰을 저장하지 않는 구현이다. 삭제 시 재인증으로 일회용 코드를 얻어 교환·철회하며, 자동 해제 불가 시 명시적인 수동 해제 선택을 제공한다. 실제 Apple 왕복 성공은 별도로 검증한다.

## 비공개 자료와 비용

Windows/WSL 작업 환경에만 있는 다음 자료는 공개 Git에 포함하지 않았다. 맥북에서 기존 개발자 로그인/보안 자격 저장소를 확인하고 필요한 자격은 안전하게 옮긴다. 키를 채팅이나 Git에 복사하지 않는다.

- `/home/kang/.local/share/carcar-release/apple.json`: 기존 API 키 경로 등. 파일 자체나 키 내용을 공개하지 않는다.
- `/home/kang/.local/share/carcar-release/app-store-review-contact.json`: 사용자 제공 심사 연락처, 권한 0600.
- `/home/kang/.local/share/carcar-release/backend-qa.json`: 서버 테스트 자격. 앱에 포함 금지.
- `docs/qa/appstore-readiness-2026-11-06/`: App Store 조회 결과, 사이트 검증·캡처.
- 비공개 빌드 저장소는 `kang88xx/60base-mobile-build`, 앱 경로는 `apps/carcar`다. 공개 앱 소스 `069dd4c`를 비공개 `release/carcar-apple-login-20261106`의 `6b2ea85`로 동기화했다. main은 변경하지 않았다.

GitHub Actions 추가 유료 예산은 $0/Usage blocked를 유지한다. 빌드 13은 18분 timeout 안에 11분 22초로 성공했다. 실행 후 Billing 화면에서 포함 compute $11.54/$12(잔여 $0.46), 저장소 0.3/0.5 GB, Actions 유료 청구 $0을 재확인했다. 추가 비공개 macOS CI 실행 전 잔액·예산을 다시 확인하고 로컬 검증을 우선한다. Supabase Free와 기기 내 OCR을 유지한다.

## 공식 근거

- [App Review 4.8 로그인](https://developer.apple.com/app-store/review/guidelines/#login-services)
- [Supabase Apple 로그인](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)
- [Apple 계정 삭제·토큰 철회 TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [OIDC ID Token 검증](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
- [스토어 버전 정보](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [스크린샷 규격](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)## 자리 핀 아이콘 빌드 14 준비와 GitHub Actions 차단 · 2026-11-10

- 공개 `wip/app-store-prep-2026-11-06`의 `b9dbc15`(자리 핀 아이콘·헤더 핀·블루 톤)와 `302f95f`(App Store Connect 사용자 초대 도우미)를 비공개 `release/carcar-pin-icon-20261110`(`e44ba65`)의 `apps/carcar`에 동기화했다. 비공개 main에는 `carcar-user-invitations.yml` 워크플로만 추가했다(`033a507`).
- **TestFlight 1.0.1 (14) 업로드를 완료했다.** 사용자가 GitHub Pro로 전환해 Actions 차단이 풀린 뒤 [빌드 14 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42659222423)가 2026-11-09 17:02 UTC(11-10 02:02 KST)에 성공했다. Apple 처리 `VALID`, 만료 아님, 내부 그룹 `차자리 내부 테스트`에 빌드 연결(`addedNow=true`), 기존 테스터 그룹 소속 확인. 첫 시도([실행 42657924535](https://github.com/kang88xx/60base-mobile-build/actions/runs/42657924535))는 서명·아카이브까지 성공한 뒤 ITMS-90062/90186(승인된 1.0.0 트레인 닫힘)으로 업로드가 거절돼 마케팅 버전을 1.0.1로 올려 재실행했다. 증거는 비공개 `~/.local/share/carcar-release/testflight-14/`. 차단 원인이던 11월 포함 사용량(청구 기준 약 2,031분, 저장 0.53GB·월)은 Pro 한도(3,000분·2GB) 안으로 들어왔고, 다른 앱의 산출물 8개 삭제와 보존 기간 3일 설정으로 저장공간 재발을 막았다. 실기기 설치와 아이콘 전환 관찰은 아직이다.
- 다음 행동: 실기기에서 빌드 14를 설치해 새 핀 아이콘, 주차 저장 후 층수 핀 아이콘 전환, 홈 헤더 핀 표시를 확인한다. 앞으로 macOS CI는 서명 업로드에만 쓰고 시뮬레이터 QA·스크린샷은 이 맥북에서 수행한다. 이 맥북에는 배포 서명 인증서가 없어 로컬 업로드 대안은 없다.
- **가족 테스터:** 11-08 읽기 전용 점검 실행(`ensure=false`)이 아직 등록되지 않은 테스터를 "실패"로 기록해 실패 메일을 보냈다. 테스터 주소와 교체 주소는 비공개 기록 `appstore-private/internal-tester-*.json`에만 둔다. 새 워크플로 `Chagok App Store Connect user invitations`로 2026-11-09 16:45 UTC 조회 결과 기존 주소에는 사용자·대기 초대가 없었고(이미 취소됨), 교체 주소에는 대기 초대 1건이 있었다. 상대방이 수락 오류를 겪어 이를 취소하고 교체 주소로 새 초대를 보냈다(첫 시도는 Apple 409 DUPLICATE, 재시도 성공; 스크립트에 재시도 추가). 상대방이 그 주소의 Apple 계정으로 수락하면 `Chagok TestFlight testers`(`ensure=true`, 두 주소 지정)로 내부 그룹에 추가한다.

## 최신 확인 · App Store 심사 제출 완료 · 2026-11-08

- 비공개 `release/carcar-appstore-20261108`의 [등록 준비 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42486691651)가 성공했다. 설명·부제·`UTILITIES` 카테고리·개인정보/지원 링크, 타사 콘텐츠 권리 사용 없음, 저작권, 연령 등급을 반영하고 재조회했다.
- 기존 스토어 버전 **1.0**에 빌드 **1.0.0 (13)**을 연결했다. 심사 연락처와 한국어·영어 전 기능 접근 안내도 저장·검증했다. 개인 연락처 값은 공개 문서에 기록하지 않는다.
- 가격 **무료(0)**, 배포 국가 **대한민국(KOR)만**, 새 국가 자동 추가 꺼짐을 확인했다. 출시 옵션은 **`AFTER_APPROVAL`(심사 승인 후 출시)**이다.
- iPhone/iPad 각 4장, **JPEG 8장 모두 `COMPLETE`와 로컬 MD5 일치**를 확인했다. QA MOV와 비공개 실기기 영상은 스토어 미디어로 올리지 않았다.
- 공개 개인정보 안내는 `fa8d690`의 [사이트 게시 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42484097529) 성공과 HTTP 200으로 확인했다. 사용자·설치 식별자, 수동 주차 위치, 보안·운영 로그, 선택적 이메일 문의 처리를 반영했다.
- **App Privacy 답변 게시를 완료했다.** CUA로 열린 Chrome에서 12개 유형을 모두 앱 기능 목적·사용자 신원 연결·추적 사용 안 함으로 입력했다. 게시 확인창의 정확성·관련 법 준수·변경 시 갱신 문구에 사용자가 동의한 뒤 게시했고, 화면의 게시 완료 표시를 확인했다. [입력·게시 기록](app-store/privacy-console-steps.md)과 [분류 근거](app-store/privacy-answers.md)를 참고한다.
- **최종 심사 제출을 완료했다.** [제출 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42488929909)는 2026-11-08 **14:16:11 UTC / 23:16:11 KST**에 성공했다. `submission.json`의 `versionState`와 `submissionState`는 모두 **`WAITING_FOR_REVIEW`**, **`submitted=true`**, `blockers=[]`다. 스크린샷 8장 완료와 무료·KOR 한정 배포 설정도 함께 재확인했다.
- 심사 제출 ID는 `26696dda-35de-4157-a091-a4bf4bec0334`다. 증거는 비공개 `~/.local/share/carcar-release/appstore-runs/42488929909/carcar-appstore-registration-12/submission.json`에 보관한다. 이전 [제출 시도](https://github.com/kang88xx/60base-mobile-build/actions/runs/42487225872)의 `APP_DATA_USAGES_REQUIRED` 오류는 개인정보 게시 후 해소됐다. 현재는 Apple 심사 결과를 기다리며 중복 제출하지 않는다. 심사 승인이나 App Store 공개가 완료된 것은 아니다.
- 이번 도구 검증은 **Node 57/57개 통과**, Dart 포맷 **46개 파일·변경 0개**, `flutter analyze --no-pub` **문제 0개(2.4초)**다. 제품 코드는 `069dd4c` 그대로다. 심사 연락처 전달용 임시 secret은 작업 후 제거했고 잔여 0개를 확인했다.
- 아래 실기기 확인 범위와 미검증 항목은 그대로다. 심사 접수 완료는 실제 인증·삭제·가족 공유 검증이나 심사 통과를 뜻하지 않는다.

## 최신 확인 · 실기기 탐색과 스토어 촬영 자료 · 2026-11-08

- **사용자 확인:** 사용자가 TestFlight 13에서 Apple 로그인과 주차 저장이 됐다고 답했다. 이 인증·저장 성공은 사용자 보고이며 에이전트가 로그인 왕복이나 운영 저장을 재실행한 결과는 아니다.
- **직접 관찰:** iPhone Mirroring으로 실제 차자리의 로그인 상태와 홈·이력·가족·설정을 탐색했다. 기존 이력 2건을 확인하고 새 주차 위치를 입력한 뒤 취소 경고에서 나갔다. 홈 새로고침 후 기존 위치가 보존됨을 확인했다. 운영 저장·로그아웃·초대·계정 삭제는 수행하지 않았다.
- 실제 설치 빌드 번호는 기기 조회로 확인하지 못했다. Developer Mode가 꺼져 조회가 실패했으며 이를 켜지 않았다. 실기기 결과는 **사용자가 앞서 확인한 TestFlight 13 기준의 화면 관찰**로 기록한다. 카메라 OCR·Face ID·두 기기 가족 공유·푸시·계정 삭제/Apple 철회는 미검증이다.
- **실기기 QA 원본 저장·장면 검증 완료:** 미러링 창을 지정한 터미널 녹화로 `physical/terminal-capture/physical-iphone-qa.mov`를 생성했다. 원본은 **89.997초 / 742×1528 / 비디오 1개·오디오 없음**이다. 디코딩한 장면에서 가족(18초)·설정(26초)·입력(50~58초)·취소 확인(66초)·기존 홈 복귀(74~88초)를 확인했고 다른 Mac 앱은 포함되지 않았다. 새 로그인·운영 저장·OCR·가족 공유·계정 삭제 성공을 검증한 영상은 아니다. 정리본 `physical/derived/physical-iphone-qa.mp4`는 **84초 / 618×1344 / 오디오 없음**이며 최종 10개 장면에서 홈·이력·가족·설정·입력·취소·복귀·새로고침 완료를 확인했다. 폰 영역 자르기와 끝의 대기 구간 정리만 했고 UI 내용은 수정하지 않았다. 툴바·다른 Mac 앱은 없으며 약 90초 원본도 보존한다.
- 실기기 영상은 실제 개인정보가 있어 비공개 `~/.local/share/carcar-release/media-20261108/physical/`에서 관리하며 Git·공개 ZIP에 포함하지 않는다. 앞서 미러링 구간이 누락된 Mac 녹화 2개는 실패 진단 자료로 분리한다. 재촬영 시 화면 기록 권한을 확인하고 미러링 창 ID를 그때 조회해 지정하며, 파일 생성 뒤 실제 장면을 디코딩·검증한다.
- **시뮬레이터 촬영 완료:** iPhone 1320×2868과 iPad 2064×2752에서 홈·주차 입력·가족·이력 각 4장, 총 **JPEG 8장**을 준비했다. alpha 채널이 없고 8장 모두 시각 검토를 통과했다. 제품 코드는 TestFlight 13의 `069dd4c`와 동일하며 내장 체험 데이터를 사용했다. 네이티브 홈 화면 위젯 촬영은 남았다.
- 체험 동영상은 iPhone **28.25초**, iPad **29.42초**의 MOV 2개다. 시뮬레이터 QA 영상이며 App Preview 제출용 완성본은 아니다. 두 기기군의 통합 촬영 검사, 포맷·분석·Bash 문법·diff 검사를 통과했다. 실제 인증·서버 저장·가족 동기화 증거와 구분한다.
- 전달 폴더는 `build/app-store-media-20261108/delivery/`이며 `index.html`, `README.txt`, `manifest.json`에 갤러리·규격·검증 범위를 담았다. `build/app-store-media-20261108/차자리-스토어-촬영자료.zip`은 **13개 파일 / 7.99 MB**, ZIP 무결성 검사 통과다. 이후 메타데이터와 JPEG 8장 업로드는 완료했으며, 심사 제출 결과는 맨 위 등록 진행 상태를 따른다.

## 현재 배포 상태 · TestFlight 13 완료

- **설치 가능한 최신 빌드는 1.0.0 (13)**이다. [빌드 13 비공개 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42215777783)가 성공했고 Apple 처리 `VALID`, 만료 아님, 기존 내부 테스트 그룹에 빌드 연결을 확인했다. 기존 테스터의 그룹 소속도 확인했으며 초대 재전송이나 멤버 추가는 하지 않았다.
- 공개 WIP 브랜치 `wip/app-store-prep-2026-11-06`의 앱 소스 `069dd4c`를 push하고, 비공개 `release/carcar-apple-login-20261106` 브랜치의 `6b2ea85`로 동기화했다. 복사한 소스의 해시 일치를 검사했고 두 저장소의 main은 변경하지 않았다.
- CI는 Xcode 26.6에서 기존 배포 인증서·프로파일을 재사용해 실행했다. 인증서 생성·폐기는 없었다. 작업 시간은 2026-11-06 12:11:38–12:23:00 UTC, **11분 22초**다. 12:22:28 UTC의 배포 증거에서 build `13`, `processingState=VALID`, `ready=true`, `groupContainsBuild=true`를 확인했다.
- 그룹의 모든 미래 빌드 자동 접근 설정 변경은 변경 불가 409로 거절됐지만, 이번 빌드의 명시적 그룹 연결은 성공했다. 미래 빌드 자동 배포가 활성화됐다고 간주하지 않는다.
- Apple 로그인·계정 삭제·UIScene 전환과 함께 설정의 문의 UI를 공개 고객지원으로 변경하고 Apple 계정 삭제 안내를 개인정보 문구에 반영했다. 최종 로컬 검사: **Flutter 268개 통과 / 4개 선택 검사 건너뜀, Python 19개·Node 70개 통과**, 분석·포맷 성공.
- CI 실행 후 GitHub Billing 화면을 다시 확인했다. 포함 compute는 **$11.54 / $12**, 잔여액은 **$0.46**, 저장소는 **0.3 / 0.5 GB**, Actions 유료 청구는 **$0**이다. 추가 유료 예산은 **$0 / Usage blocked**를 유지한다. 이번 실행은 18분 timeout으로 제한했으며, 추가 비공개 macOS CI 실행 전 잔액·예산을 다시 확인하고 로컬 검증을 우선한다.
- 배포 로그·증거는 비공개 `~/.local/share/carcar-release/testflight-13/`, 로컬 출시 검사는 `build/release-prep/`에 보관한다. 이후의 사용자 보고·실기기 관찰·촬영 자료는 맨 위 2026-11-08 기록을 따른다. 스토어 등록 준비의 후속 결과는 맨 위 2026-11-08 기록을 따르며 실제 인증·철회·삭제 검증 범위는 별도로 유지한다.

아래는 단계별 작업 기록이다. 과거 단계의 검사 수·실패·미완료 표현은 당시 상태이며 현재 배포·검증 상태는 이 절을 우선한다.

## 맥북 재개 결과 · 2026-11-06

### Apple 철회 키·서버 배포 완료

- 사용자가 키 생성·서버 등록·배포를 승인한 뒤 `Chagok Apple Login` 키를 생성했다. Apple Developer에서 Sign in with Apple 권한과 차곡의 primary App ID 연결을 재확인했다. 기존 60BASE·APNs 키는 변경하지 않았다.
- 내려받은 개인 키의 형식을 검증하고 `~/.local/share/carcar-release/apple-sign-in/`에 보관했다. 디렉터리 권한은 0700, 파일은 0600이며 Downloads의 임시 사본은 제거했다. 키 값은 채팅·Git·앱에 넣지 않았다.
- `APPLE_SIGN_IN_*` 서버 secret 4개를 등록하고 새로고침 후 각 SHA-256이 로컬 값과 일치함을 확인했다. 기존 secret의 digest는 그대로다. `apple-disconnect`는 **ACTIVE / v1**이며 원격에서 다시 받은 3개 소스 파일이 로컬 배포 파일과 정확히 일치한다.
- 운영 endpoint에서 Authorization 누락·가짜 bearer는 **401 `session_invalid`**, 잘못된 JSON은 **400 `invalid_request`**를 반환했고 모두 `Cache-Control: no-store`였다. 실제 Apple 자격·토큰 교환·철회나 계정 삭제는 실행하지 않았다.
- 기존 `parking-push`의 소스 checksum은 그대로다. 프로젝트 공통 secret 갱신에 따라 버전만 **v1→v2**로 자동 변경됐다.
- 공개 가능한 검증 기록은 로컬 `build/account-deletion-qa/production-smoke.json`과 `verification.json`, 키·서버 설정 영수증은 비공개 `~/.local/share/carcar-release/apple-sign-in/setup-receipt.json`에 보관한다. 다음은 서명된 실제 iPhone의 Apple/Google 로그인과 통제된 삭제 검증이며, 빌드 13 배포 완료 증거는 맨 위 기록을 따른다.

### 계정 삭제 보호·Apple 연결 해제 구현 및 로컬 검증

- 삭제 시작 시 사용자와 access token을 고정하고, 해당 토큰으로 서버 사용자·연결 identity를 다시 조회한다. Apple 계정이면 네이티브 재인증 자격만 얻으며 공유 Supabase 로그인 세션을 교체하지 않는다. 재인증·수동 확인·서버 요청 사이에 계정이 바뀌면 중단한다. A→B→A 전환도 이전 요청을 되살리지 않는다.
- `apple-disconnect`는 서버 identity와 Apple token endpoint 응답을 비교한다. 고정 JWKS의 RS256 서명, issuer·audience·시간·subject·nonce를 검증한 뒤에만 Apple 토큰을 철회한다. 이 함수에는 DB 삭제 권한이나 service role 키가 없고, 토큰을 저장·출력하지 않는다. 설정·오류 계약은 [서버 함수 배포 문서](../supabase/deployment/APPLE_SIGN_IN.md)를 따른다.
- 네이티브 Apple 인증의 알려진 일시 실패·지원 불가도 `apple_unavailable`로 분류한다. `apple_not_configured`, `apple_unavailable`, `apple_reauthentication_required`에서만 별도 확인을 받아 계정 삭제와 수동 Apple 연결 해제 안내를 제공한다. 사용자 취소·identity 불일치·서명 검증 실패·세션 변경은 삭제를 진행하지 않는다.
- 실제 삭제 RPC의 Authorization도 최초 bearer로 고정한다. 서버 삭제 성공 뒤 같은 세션일 때만 로컬 로그아웃하며, 뒤늦은 완료·auth 이벤트가 새 계정 화면을 지우지 않게 했다. 로컬 로그아웃 네트워크 실패를 서버 삭제 실패로 바꾸지 않는다.
- 로컬 검증: `flutter test --no-pub` **267개 통과 / 4개 선택 검사 건너뜀**, `flutter analyze --no-pub` **No issues found**, Dart 포맷 **45개 / 변경 0**. 추가 56개는 저장소 37개·삭제 UI 12개·루트 세션 7개이며 실제 Supabase SDK와 로컬 HTTP를 사용한 경합 검사를 포함한다. Node 선택 검사 **52개 통과**(Apple 함수 14개 포함), Deno `check`도 종료 0이다.
- 검증 로그와 코드 해시는 로컬 `build/account-deletion-qa/verification.json` 및 같은 폴더에 보관했다. 웹 release 빌드도 종료 0이다.
- 변경 후 iOS Simulator debug 빌드와 패키징 검사를 다시 통과해 **앱 iOS 15.0 / 위젯 iOS 17.0**을 확인했다. 앱 삭제 흐름·Edge 보안 코드의 독립 검토에서도 차단 결함은 발견하지 못했다. 이 빌드 성공은 실제 Apple 인증·철회를 대신하지 않는다.
- 위 로컬 검증 후 키·서버 설정 및 Edge 배포를 완료했다. 운영 endpoint의 입력·인증 거절 검사는 위 배포 기록을 따른다. 실제 Apple 인증·철회·계정 삭제는 아직 검증하지 않았다. 빌드 13 배포 완료 증거는 맨 위 기록을 따른다.

### Apple 로그인 설정 1단계 완료

- 사용자 요청으로 기존 로그인된 Apple Developer에서 `com.kang88.carcar`의 **Sign In with Apple을 primary App ID로 활성화**했다. 저장 후 페이지를 다시 열어 체크 상태와 primary 구성을 확인했다. 다른 앱과 그룹화하거나 다른 앱 설정을 바꾸지 않았다.
- 기존 `Chagok App Store Push 20261102` 프로파일을 같은 Distribution 인증서 선택으로 재생성했다. 새 인증서를 발급·폐기하지 않았다. 내려받은 프로파일을 기존 `validate_profile`로 검사해 앱 Bundle ID·Team·App Group·공유 Keychain·App Store 유형·production APNs·`com.apple.developer.applesignin = [Default]`를 확인했다. Xcode 프로파일 저장소에도 설치했다. 위젯 프로파일은 변경하지 않았다.
- 차자리 Supabase 프로젝트의 Apple provider를 활성화하고 Client IDs를 `com.kang88.carcar`로 설정했다. 페이지 새로고침 후 enabled와 Client ID를 재확인했다. 기존 Google provider는 enabled를 유지한다. 네이티브 ID-token 로그인 범위이므로 웹 OAuth Secret Key와 Services ID는 추가하지 않았다. 이는 추후 Apple 토큰 철회용 개인 키가 불필요하다는 뜻이 아니다.
- 원격 설정 증거는 비공개 `~/.local/share/carcar-release/apple-login-setup-receipt.json`, 프로파일 검증은 같은 경로의 `profiles/apple-sign-in-app-receipt.json`에 저장했다. 프로파일 파일은 Git에 넣지 않았다.
- 현재 Mac Keychain에는 해당 배포 인증서와 일치하는 서명 identity가 **0개**다. 새 기기용 서명 빌드에는 기존 비공개 CI의 개인 키를 안전하게 이전하거나 기존 CI를 사용해야 한다. 이후 기존 비공개 CI 자격으로 빌드 13 배포를 완료했다. Mac 개인 키 이전과 실제 Apple 로그인 검증은 여전히 별도다.

### 최신 상태: Flutter 업그레이드와 UIScene 전환

- 사용자가 Flutter 업그레이드를 승인했다. 현재 기준은 **Flutter 3.47.9 / Dart 3.13.7**이며 공개 CI 3개도 같은 버전으로 고정했다. 새 SDK는 `~/development/flutter-3.47.9`, 이전 3.35.4 SDK는 `~/development/flutter`에 보존했다. 로컬 명령은 `PATH="$HOME/development/flutter-3.47.9/bin:$PATH"`와 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 사용한다.
- `Info.plist`의 Scene Manifest와 `SceneDelegate`를 추가하고, 플러그인·`carcar/native` 채널 등록을 implicit engine 초기화로 옮겼다. 공유 시트·Apple 인증은 현재 활성 scene의 key window를 사용한다. `app_links 6.4.1`의 cold URL/user activity는 직접 전달하고 warm 이벤트는 Flutter의 기존 plugin fallback으로 전달한다. 같은 이벤트를 두 경로에서 중복 전달하지 않는다.
- SDK가 생성한 Swift Package Manager 연결을 유지하며, `flutter_secure_storage 9.2.4`는 CocoaPods fallback으로 빌드한다. 향후 Flutter에서는 이 플러그인의 SwiftPM 지원이 필요하다는 경고가 남는다. 직접 의존성을 추가하거나 플러그인 버전을 임의로 올리지 않았다.
- 새 Flutter의 ListTile 검사에서 기존 장식 배경이 Material ink를 가리는 오류를 발견했다. 공통 `Surface`를 `Material + Padding`으로 바꾸고 사이드바에서 재사용했다. 색상·반경·여백을 유지했고 assertion이나 검사를 끄지 않았다.
- `flutter analyze --no-pub`: **No issues found**. `flutter test --no-pub`: **211개 통과 / 4개 선택 검사 건너뜀**, 종료 0. 기존 검사로 호환성 오류 해결을 확인했다. `flutter build web --release --no-pub`도 성공했다. 기존 secure-storage의 Wasm 비호환·Cupertino 폰트 경고는 남고 JavaScript 웹 빌드는 정상 생성됐다.
- 네이티브 QA의 첫 재실행은 Dart 테스트까지 진입했으나 스크롤 직후 이전 좌표로 기록 버튼을 눌러 실패했다. `integration_test/native_app_test.dart`는 버튼을 스크롤 중앙에 놓고 프레임을 반영한 다음 hit-test 가능 여부를 검사하도록 수정했다. 기능 assertion은 유지했고 나머지 큰 diff는 새 formatter에 따른 형식 변경이다.
- 아이콘 알림 도우미는 기존 영어 문구 외에 실제 한국어 `‘차자리’ 아이콘을 변경했습니다.`와 `확인` 버튼의 정확한 조합을 지원한다. 일반 알림을 임의로 닫지 않는다. 실패한 실행이 남긴 시스템 알림은 앱 삭제만으로 사라지지 않아, 재실행 전에 잔류 알림과 앱을 정리했다.
- 프로필 편집 검사는 옛 `AlertDialog` 가정 대신 실제 `ProfileEditorDialog`와 내부 이름 입력란을 검증한다. 편집 취소 후 이름·차량·기록이 그대로인지 확인하며, 제품 동작이나 기능 assertion을 줄이지 않았다. 관련 주차 배치 8개·계정 사용성 13개 검사도 통과했다.
- `flutter build ios --simulator --debug --no-pub`: **성공**, 3.35의 fat binary 검사 오류와 시작 시 UIScene 크래시를 해결했다. 빌드 앱 검사에서 **앱 15.0 / 위젯 17.0**을 유지했다. iPhone 18 Pro / iOS 27.2에서 실제 화면과 cold 초대·주차 입력 링크 진입을 확인했다.
- `bash scripts/ios_qa.sh`: **최종 종료 0**, `test-complete`와 `All tests passed` 확인. 실제 기기 내 Vision OCR이 테스트 표지 `B2 / C / 24`를 읽었고, 체험 `B3 / D / 52` 저장·저장소 재조회·이력·층수 아이콘·위젯 안내→설정·프로필 편집 취소가 통과했다. 별도 XCTest가 이번 실행의 아이콘 안내 2회를 처리했고, 앱/위젯 패키징과 APNs 빌드 설정 검사도 통과했다.
- 최종 네이티브 증거는 **`build/ios-runtime-qa-347-verified/`**의 `integration.log`, `observations.json`, `icon-alerts.xcresult`, `deployment-targets.json`, 화면 캡처 10장이다. 이전 `ios-runtime-qa*` 디렉터리의 실패·중단 기록과 구분한다. Flutter 분석·전체 테스트·포맷 41개 변경 0·웹 빌드 로그는 `build/macos-continuation/flutter-347/`에 보관했다.
- 일반 앱을 다시 빌드해 실행 중 초대 링크 수신과 홈→주차 입력 진입을 확인했다. 종료 상태의 초대·주차 입력, 열린 입력창의 중복 주차 링크와 초안 보존, cold/warm 인증 취소 콜백 뒤 앱 생존도 확인했다. `build/ios-scene-links/RESULTS.md`와 화면 캡처에 기록했다. synthetic 초대·서버 설정 없는 환경이므로 실제 초대 수락이나 OAuth 왕복 성공을 뜻하지 않는다.
- 이 QA는 실제 서버 인증·푸시 전송·홈 위젯 배치·서명 archive를 검증하지 않으며, 저장소 재조회는 앱 프로세스 재시작 검사가 아니다. 실제 Apple/Google 인증, 계정 삭제·철회와 새 배포·심사 제출은 남아 있다. 원격 capability·provider 설정은 위 1단계 완료 기록을 따른다. 아래 3.35 환경의 실패 기록은 원인과 비교 근거로 보존한다.

### 추가 환경 준비와 서명 검사

- `brew install cocoapods` 완료, `pod --version` **1.17.0** 확인. Xcode 미설치를 확인하는 데서 멈추지 않고 App Store의 기존 Xcode 다시 다운로드를 실행했다.
- App Store가 기존 Apple 계정의 암호를 요구해 사용자가 시스템 창에서 직접 로그인했다. 이후 다운로드·설치 완료, **Xcode 27.2 / Build 27B52**를 확인했다. 암호는 채팅·Git·로그로 받지 않는다. 첫 실행의 약관 화면이 외부 조작으로 넘어갔고 에이전트는 Agree를 누르지 않았다. 사용자의 재열기 요청으로 설치된 `License.pdf`를 미리보기에 열었다.
- `fastlane/Gemfile.lock`에는 `arm64-darwin-27` 플랫폼만 추가했다. 패키지 버전은 유지했고 Bundler 설치 및 `generate_ios_alert_watcher.rb`의 XCTest 프로젝트 생성이 성공했다. Ruby 4/Bundler 2.4의 상수 중복 경고가 있으나 생성기 종료는 0이다.
- 현재 로컬 Ruby 도구 실행에는 `PATH=/opt/homebrew/opt/ruby/bin:$PATH`, `GEM_PATH=$PWD/build/fastlane-local/vendor/bundle/ruby/4.0.0`, `BUNDLE_PATH=$PWD/build/fastlane-local/vendor/bundle`, `BUNDLE_GEMFILE=fastlane/Gemfile`을 사용했다. 생성물은 ignored `build/` 아래에 보관한다.
- 초기 설정 완료 후 iOS SDK·Simulator 설치를 시작했다. Xcode의 별도 외부 에이전트 도구 연결은 `Never`로 선택했다. 명령에는 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 지정하므로 시스템 전역 `xcode-select`를 변경할 필요가 없다.
- `fastlane/prepare_signing.py`는 APP 프로파일에 `com.apple.developer.applesignin = [Default]`를 요구한다. Widget 프로파일에는 이 권한을 요구하지 않는다.
- 비공개/ignored `fastlane/prepare_existing_signing.mjs`도 앱 프로파일 재사용 및 신규 발급 결과에서 Apple entitlement를 검사한다. 전체 plist는 날짜·바이너리가 있어 JSON 변환할 수 없으므로 `Entitlements`만 추출한다. 당시에는 비공개 배포 저장소에 동기화하지 않았으며, 이후 빌드 13 브랜치에 반영했다.
- 서명 회귀: Python **19개**, Node **9개** 통과. Node 검사는 실제 `plutil`로 날짜·인증서 data가 포함된 plist를 읽는 경우도 포함한다. 원격 Apple capability나 프로파일을 변경한 것은 아니다.

### Apple 로그인 세션 경합 수정

- 코드 검토에서 shared `signInWithIdToken`의 HTTP 응답이 늦으면 그사이 로그인한 다른 계정을 덮는 문제를 확인했다. 네이티브 자격 반환 직후 검사만으로는 막을 수 없었다.
- `main.dart`가 같은 서버 설정의 별도 `GoTrueClient(autoRefreshToken: false)` factory를 전달한다. `auth_screen.dart`는 이 클라이언트에서 교환하고, 화면 수명·클라이언트 동일성·인증 이벤트 세대·현재 로그아웃 상태를 확인한 뒤에만 공유 세션을 반영한다.
- SDK의 초기 이벤트 replay는 화면 생성 시부터 구독해 처리한다. refresh token과 60초 이상 남은 만료 시각을 검증해 `recoverSession`의 네트워크 갱신 경로로 들어가지 않게 한다. 만료되지 않은 세션 반영은 설치 SDK에서 첫 await 전에 수행된다. SDK 변경 시 이 경계를 다시 검증한다.
- 인증·계정 검사 **36개**, 전체 Flutter 검사 **211개 통과/4개 선택 검사 건너뜀**. 실제 SDK + 로컬 HTTP를 사용하는 정상 로그인·replay·계정 전환 검사를 포함한다. 정적 분석, 포맷 40개 변경 0, 별도 코드 리뷰 통과. 실제 Apple 서버 로그인은 별도다.

### 로컬 Xcode 컴파일

- 실제 빌드에서 `PODS_ROOT` 설정 누락 및 플러그인의 iOS 9/12/13 타깃 오류를 확인했다. `ios/Flutter/Debug.xcconfig`와 `Release.xcconfig`에 Pods 설정을 포함하고, `ios/Podfile`에서 pod 최소 버전이 15보다 낮을 때만 15로 올렸다. CocoaPods의 프로젝트/workspace 연결 변경을 유지했다.
- 일반 `flutter build ios --simulator --debug --no-pub`는 그다음 Flutter 3.35의 fat binary 아키텍처 검사에서 실패했다. 요구 `arm64 x86_64`와 실제 `x86_64 arm64`의 검사 문제이며 SDK 파일이나 Intel 지원을 변경하지 않았다.
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**, 종료 0. Apple 로그인 Swift와 위젯을 포함한다.
- 생성된 앱에 `scripts/check_ios_deployment.py`를 실행해 **앱 15.0 / 위젯 17.0**을 확인했다. Simulator 런타임 설치 후 특정 기기를 지정해 실행 검증한다. 이 빌드는 실제 서버 인증·서명 archive 검증을 대신하지 않는다.

### 이전 Flutter 3.35 환경의 iOS 27 실행 실패 기록

- iOS 27.2 Simulator 설치 완료 후 iPhone 18 Pro에서 `bash scripts/ios_qa.sh` 실행. 도우미 XCTest와 앱 컴파일은 성공했으나 Runner가 Dart `test-start` 이전에 종료돼 **네이티브 QA는 미통과**다. 정체된 driver를 종료하고 스크립트가 이 실행에서 부팅한 Simulator를 정리했다.
- Runner 크래시의 첫 프레임은 `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`이며, 시스템 로그는 `UIScene life cycle is required for apps built with this SDK`라고 명시한다. 아이콘 도우미의 Lost connection은 앱 종료 뒤의 2차 오류다.
- 이 실패 당시 `Info.plist`에는 Scene Manifest가 없었고 `AppDelegate.swift`의 채널 등록은 이전 `window.rootViewController` 시점에 의존한다. [Apple 공식 전환 안내](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)와 일치하는 실행 차단이다.
- [Flutter 공식 UIScene 지원](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)은 3.38부터이고 기본 전환은 3.41부터다. 3.35에는 초기 SceneDelegate/옛 pluginRegistrant API만 있어 수동 호환 구현은 가능성을 검증해야 하며, 최신 implicit-engine 예제를 그대로 적용할 수 없다.
- 사용자에게 두 방식의 방향을 확인한 뒤 **지원 Flutter로 업그레이드하는 안을 승인받았다**. 이후 구현·검증은 맨 위 최신 상태에 기록한다.
- 근거: `build/ios-runtime-qa/`의 integration·icon-watcher 로그 및 `stalled-startup.png`, `build/macos-continuation/`의 빌드·회귀 로그. 이번 작업에서 새 TestFlight 배포·App Store 제출은 하지 않았다.

### 첫 재개 검증 기록

- 기존 `wip/app-store-prep-2026-11-06` 브랜치에서 이어갔다. 운영 코드와 서버 설정은 변경하지 않았다.
- Flutter 3.35.4 / Dart 3.9.2를 `~/development/flutter`에 설치하고 `flutter pub get`으로 이전 Linux 경로를 참조하던 로컬 의존성 정보를 복구했다. 실행 시 `export PATH="$HOME/development/flutter/bin:$PATH"`를 사용한다. 의존성 버전은 변경하지 않았다.
- `test/apple_auth_test.dart`: widget test의 플랫폼을 `TargetPlatformVariant`로 관리하고, 아이콘 버튼의 하위 타입까지 찾는 finder로 수정했다. iOS/Android 노출 검사는 각각 실행한다.
- `flutter test --no-pub test/apple_auth_test.dart test/account_usability_test.dart`: **28개 통과**, 종료 0. 기존 로그인 검사 13개를 포함하며 실제 Apple/Supabase 인증 성공을 뜻하지 않는다.
- `dart format --output=none --set-exit-if-changed lib test`: **40개 파일, 변경 0**, 종료 0.
- `flutter analyze --no-pub`: **No issues found**, 종료 0.
- `flutter test --no-pub`: **203개 통과, 4개 건너뜀**, 종료 0. 선택 실행하는 iOS 캡처 검사는 별도다.
- `flutter build web --release --no-pub`: 성공, 종료 0. 기존 secure-storage의 Wasm 비호환 및 Cupertino 폰트 경고가 남아 있으며 일반 JavaScript 웹 빌드는 생성됐다.
- `python3 fastlane/test_prepare_signing.py`: **18개 통과**. `node --test supabase/tests/push_worker.test.mjs`: **15개 통과**.
- `swiftc -frontend -parse ios/Runner/AppDelegate.swift`: 문법 검사 통과. iOS SDK 타입 검사나 링크·실행 검증이 아니다.
- `flutter build ios --simulator --debug --no-pub`: **종료 1**, `Application not configured for iOS`. 프로젝트 파일은 존재하지만 현재 Xcode 환경에서 빌드 구성을 조회·컴파일하지 못했다.
- `flutter doctor -v`와 `xcodebuild -version`: 전체 Xcode가 없고 `/Library/Developer/CommandLineTools`만 활성화돼 있다. CocoaPods·iOS Simulator도 준비되지 않아 **다음 단계는 Xcode 환경 준비 후 네이티브 컴파일**이다. Android SDK도 없으나 이번 단계는 iOS 우선이다.
- 실제 Apple 로그인, App ID capability·서명 프로파일, Supabase Apple provider, 계정 삭제·철회, App Store 제출은 여전히 미완료다. 새 배포나 유료 CI 실행은 하지 않았다.

추가 코드 검토 항목: Apple 버튼의 공식 로고·규격, `credentialRevokedNotification` 및 `getCredentialState`를 통한 철회 감지. nonce 전달 방식은 [Supabase Dart 계약](https://supabase.com/docs/reference/dart/auth-signinwithidtoken)과 일치한다. 버튼은 [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple/), 철회는 [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)를 기준으로 후속 검증한다.

아래의 실패 횟수와 중단 상황은 **맥북 재개 이전 기록**이다. 현재 검증 결과는 위 내용을 우선한다.

## 맥북에서 이어가기

소스 저장소: `git@github.com:kang88xx/carcar-kang88.git`

```sh
git fetch origin
git switch --track origin/wip/app-store-prep-2026-11-06
```

이미 이 로컬 브랜치가 있으면 `git switch wip/app-store-prep-2026-11-06`을 사용한다. 기존 작업 파일이 있는 맥북 체크아웃은 변경을 덮어쓰지 말고 별도 checkout/worktree를 사용한다.

다음 작업자는 이 문서, `AGENTS.md`, 프로젝트 기본 문서 및 `docs/app-store/submission-draft.json`을 먼저 읽는다. Flutter 3.47.9 / Dart 3.13.7이 현재 프로젝트 기준이다.

## 사용자 확정 사항

- 기존 유료 Apple Developer 계정으로 App Store 등록을 진행한다. 신규 계정 결제나 유료 서버 도입은 요청하지 않았다.
- 앱 가격: 무료. 최초 배포 국가: 대한민국.
- 공개 고객지원 이메일: `kang88xx@gmail.com`.
- 심사용 이름·이메일·전화번호는 받았으며 비공개로 취급한다. 공개 저장소에 넣지 않았다.
- 이번 작업과 테스트는 iOS 우선이다. Android 실기기 검증은 나중에 진행한다.

## 완료·게시된 결과

- 최신 TestFlight: **1.0.0 (13)**. Apple 처리 `VALID`, 기존 내부 테스트 그룹 연결 완료. 소스·CI·검증 증거는 맨 위 현재 배포 상태를 따른다.
- 아래 빌드 12 항목은 이전 배포 이력이다.
- 빌드 12의 앱 소스는 `f3373a6`, 비공개 빌드 소스는 `cdace91`. 이후 문서 커밋은 바이너리 변경이 아니다.
- [빌드 12 배포 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42171293207), [공개 앱 검증](https://github.com/kang88xx/carcar-kang88/actions/runs/42171242680) 성공.
- 네 탭 헤더 고정과 작은 화면 기록 버튼 문구 수정: Flutter 188개, 별도 화면 검사 4개/44장 통과. 최신 실제 iPhone 동작 확인은 별도다.
- 지원 사이트와 등록 초안은 main의 `243c3b8`에 저장·push했다. [사이트 게시 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42180853820), [해당 main 검증 CI](https://github.com/kang88xx/carcar-kang88/actions/runs/42180853943) 성공.
- 공개 지원 페이지: https://kang88xx.github.io/carcar-kang88/support/
- 개인정보 페이지: https://kang88xx.github.io/carcar-kang88/privacy/
- `site/support/index.html`, 홈의 지원 링크, 공개 개인정보 페이지의 위젯 설명·문의 경로를 정리했다. 지원 사이트의 320/768/1280px 브라우저 검사와 링크 16개 검사를 통과했다.
- `docs/app-store/submission-draft.json`: 한국어 설명·부제·키워드·스크린샷 촬영 계획과 무료/KOR 설정 초안. 문자열 제한·키워드 UTF-8 100바이트 제한을 검사했다. 자동 업로드/제출 도구는 아니다.

## App Store Connect 조회 결과 · 2026-11-06 당시 기록

아래 빈 필드와 미실행 표현은 당시 상태다. 2026-11-08 반영·업로드 결과는 맨 위 최신 기록을 우선한다.

2026-11-06 조회 시 등록명은 `차자리 - 가족 주차 기록`, 기본 언어 `ko`, iOS 버전 `1.0`은 `PREPARE_FOR_SUBMISSION`이었다.

- 설명·키워드·스크린샷·지원 URL·부제·개인정보 URL·저작권자·카테고리가 비어 있다.
- 선택된 심사용 빌드와 App Review 연락처/로그인 정보가 없다.
- 연령 등급 답변이 비어 있다. App Privacy 신고 완료 여부와 가격/판매 국가의 실제 서버 설정은 아직 확인하지 않았다.
- 기존 출시 옵션은 `AFTER_APPROVAL`이다. 초안은 승인 후 수동 출시를 제안하지만 원격 설정은 바꾸지 않았다. 제출 전에 출시 방식을 명확히 확인한다.
- App Store Connect 메타데이터 수정, 심사 제출, 공개 출시는 아직 실행하지 않았다.
- 바이너리는 iPhone과 iPad(`TARGETED_DEVICE_FAMILY = 1,2`)를 지원한다. 두 기기군의 스토어 스크린샷이 필요하다. 기존 작은 QA PNG를 실제 기기 캡처로 가장하지 않는다.

## 맥북 재개 전 미완성 코드 기록

이 절은 이전 인계 시점의 기록이다. 아래 중단·검사 실패는 이후 구현과 검증으로 해결했으며 최신 결과는 맨 위를 따른다. 당시 다음 다섯 파일을 Apple 로그인 작업 중 사용자의 저장 요청으로 중단했다.

- `ios/Runner/AppDelegate.swift`: AuthenticationServices/CryptoKit 기반 Apple 인증 요청, nonce/state, delegate와 presentation anchor.
- `ios/Runner/Runner.entitlements`: `com.apple.developer.applesignin = [Default]` 추가.
- `lib/core/native_bridge.dart`: iOS 전용 `supportsAppleSignIn`, `AppleCredential`, `signInWithApple()` 추가.
- `lib/features/auth_screen.dart`: 기존 Google 로그인을 유지하며 iOS Apple 버튼과 Supabase ID token 로그인 추가.
- `test/apple_auth_test.dart`: 신규 테스트 초안.

당시 정한 NativeBridge 계약:

```text
signInWithApple() -> Future<AppleCredential?>
사용자 취소 -> null
필드: identityToken, authorizationCode, userIdentifier, rawNonce, fullName?
MethodChannel: carcar/native / signInWithApple
```

최초 이름은 반환하지만 기존 프로필 nickname/metadata를 자동 덮어쓰지 않는다. 실제 계정의 표시 이름 처리는 후속 검토 대상이다.

### 맥북 재개 전 검사 결과

- 수정 Dart 파일 포맷 완료, `git diff --check` 통과.
- `flutter test --no-pub test/apple_auth_test.dart test/account_usability_test.dart`: **17 통과 / 10 실패**, 종료 코드 1.
- 기존 `account_usability_test.dart` 13개는 통과했다.
- 신규 테스트의 `debugDefaultTargetPlatformOverride` 복원이 테스트 invariant 검사보다 늦고, `FilledButton.icon`/`OutlinedButton.icon`을 `find.byType(FilledButton/OutlinedButton)`으로 찾는 일부 finder가 실패한다. 플랫폼 variant/복원 및 실제 버튼 타입에 맞는 finder 수정부터 진행한다.
- 이 브랜치 전체 `flutter analyze`, 전체 회귀, Swift 컴파일, 실제 Apple 로그인은 아직 검증하지 않았다.
- 위 실패는 앞서 검증·배포된 TestFlight 12와 별개다.

## Apple·서버 설정의 현재 상태

- 기존 App ID는 `com.kang88.carcar`, Widget은 `com.kang88.carcar.ParkingWidget`이다. 식별자는 바꾸지 않는다.
- `com.kang88.carcar`의 Sign In with Apple primary 설정은 **활성화 완료 및 재조회 확인**했다. 기존 App Groups/Push를 유지했다.
- 이전 API 요청은 HTTP 409로 실패했으나 이번에는 Developer 사이트의 해당 App ID에서 저장·재조회했다. 과거 409의 정확한 원인을 확정하지 않는다. 공식 API의 capability는 `APPLE_ID_AUTH`, primary 설정 key는 `APPLE_ID_AUTH_APP_CONSENT` / option `PRIMARY_APP_CONSENT`다.
- 차자리용 `Chagok Apple Login` 키를 생성·다운로드·검증해 보호 저장했다. 다른 앱 `60BASE`의 기존 Apple 로그인 키와 APNs 키는 변경하지 않았다.
- Supabase Apple provider 활성화와 Client IDs의 `com.kang88.carcar` 등록은 **완료 및 새로고침 후 확인**했다. 철회용 secret 4개 등록과 `apple-disconnect` 배포·원격 소스 일치 검사도 완료했다.
- 앱 배포 프로파일은 기존 배포 인증서를 유지해 갱신했으며 Apple 로그인 entitlement와 기존 권한 검사를 통과했다. CI 재사용/검증 로직도 비공개 빌드 13 브랜치에 동기화했다. Mac의 배포 개인 키는 여전히 별도 준비가 필요하며 현재 배포는 기존 CI 자격을 사용한다.
- 계정 삭제 보호·Apple 연결 해제 앱/서버 코드의 로컬 회귀, 원격 함수 배포와 입력·인증 거절 검사를 완료했다. 실제 Apple 인증·철회·계정 삭제 검증은 남았다.

## 다음 작업 순서

1. **로컬 완료:** Apple 테스트·세션 경합 보완, 코드 검토·분석·전체 회귀, Flutter 3.47.9 전환과 iOS Simulator 네이티브 QA·링크 확인. 실제 기기 인증은 7번에서 검증한다.
2. **설정 완료:** App ID Apple 로그인 활성화 및 기존 배포 인증서로 앱 프로파일 갱신·권한 검사. 비공개 빌드 13 브랜치 동기화도 완료했다. Mac의 배포 개인 키는 없으므로 현재는 기존 CI 자격으로 서명한다.
3. **설정 완료:** Supabase Apple provider 활성화, Client IDs의 `com.kang88.carcar` 등록. 네이티브 전용 범위로 기존 nonce 검증과 Google 설정을 유지했다. 실제 서명 앱에서 로그인 왕복 검증은 7번에 남아 있다.
4. **서버 배포 완료:** 차자리 전용 Apple 로그인 키·서버 secret 등록과 `apple-disconnect` 배포, 원격 소스 일치 및 입력·인증 거절 검사를 완료했다. 실제 Apple 왕복은 7번에서 검증한다.
5. **앱 배포 완료:** 계정 전환 방어와 Apple 연결 해제/수동 fallback을 TestFlight 빌드 13에 포함했다. 실제 기기에 설치한 뒤 7번의 인증·삭제 검증을 수행한다.
6. **앱 코드 완료:** 문의 UI를 공개 고객지원으로 바꾸고 개인정보 문구에 Apple 재인증·삭제·수동 연결 해제 안내를 반영했다. TestFlight 빌드 13에 포함했다.
7. **일부 확인:** Apple 로그인·저장 성공은 사용자 보고, 로그인된 실기기 화면 탐색과 입력 취소 후 기존 기록 보존은 직접 관찰했다. 설치 빌드 번호 직접 조회·인증 재시도·카메라 OCR·Face ID·두 기기 공유·푸시·계정 삭제/철회는 남았다. 실기기 QA 원본과 84초 정리본의 폰 조작·취소·새로고침 장면 검증은 완료했다. Apple 비공개 이메일을 추측해 Google 계정과 합치지 않는다.
8. **등록 자료 반영 완료:** iPhone/iPad의 홈·입력·가족·이력 각 4장을 업로드·검증했고 연령 등급·저작권·심사용 전 기능 접근 안내도 반영했다. 네이티브 홈 위젯 촬영은 남았다. QA MOV는 App Preview 제출본이 아니며 체험 데이터는 실제 가족 공유 심사용 접근을 대신하지 않는다.
9. **심사 제출 완료:** 개인정보 12개 유형을 게시하고 [최종 제출 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42488929909)에서 빌드 13의 `WAITING_FOR_REVIEW`, `submitted=true`를 확인했다. 무료·대한민국 한정·심사 승인 후 자동 출시 설정을 유지한다.
10. **Apple 심사 결과 대기:** [App Store Connect 앱 심사](https://appstoreconnect.apple.com/apps/6829616379/distribution/reviewsubmissions)에서 결과와 추가 정보 요청을 확인한다. 현재 제출을 다시 실행하지 않는다. Apple의 요청이 있으면 해당 내용을 근거로 대응하고, 승인 후 공개 상태는 별도로 확인한다. 7번의 미검증 실기기 항목은 심사 접수와 별도로 남아 있다.

### 구현한 삭제 흐름의 보안 경계

- 삭제 재인증에서 `signInWithIdToken`으로 Supabase 세션을 교체하지 않는다. 기존 bearer를 유지한 채 native 자격만 얻는다.
- `apple-disconnect` Edge 입력은 `authorizationCode`와 `rawNonce`로 제한한다.
- Edge가 Supabase `/auth/v1/user`로 bearer를 검증하고 서버 identity의 Apple `sub`를 확보한다. 이메일·클라이언트 userId를 권한 근거로 사용하지 않는다.
- 고정 Apple HTTPS `/auth/token` 응답의 ID token을 고정 JWKS의 RS256 공개키로 검증한다. issuer/audience/시간/subject/nonce도 검사하고 현재 사용자와 일치할 때 반환 토큰을 `/auth/revoke`로 철회한다. TLS 검증만으로 서명 검증을 대체하지 않으며 redirect 차단·시간/크기 제한·토큰 로그 금지를 지킨다.
- 배포에 필요한 서버 secret 이름: `APPLE_SIGN_IN_TEAM_ID`, `APPLE_SIGN_IN_KEY_ID`, `APPLE_SIGN_IN_PRIVATE_KEY`, `APPLE_SIGN_IN_CLIENT_ID`. 일반 Supabase URL/anon 설정과 함께 사용하되 키는 앱·Git에 넣지 않는다.
- 철회 또는 별도 수동 해제 확인 뒤 기존 `delete_my_account` RPC를 실행한다. 삭제 시작/각 비동기 경계에서 사용자·세션 변경을 검사하고, 캡처한 access token으로 RPC Authorization을 고정했다. 서버 성공 뒤 같은 세션일 때만 local sign-out을 한다.
- 토큰 부재·일시 장애로 계정 삭제를 영구 차단하면 안 된다. 재시도/취소 또는 명시적인 계정 삭제 후 수동 Apple 접근 철회 안내를 제공한다. identity 불일치·세션 변경은 자동 fallback으로 넘기지 않는다.
- 장기 Apple 토큰을 저장하지 않는 구현이다. 삭제 시 재인증으로 일회용 코드를 얻어 교환·철회하며, 자동 해제 불가 시 명시적인 수동 해제 선택을 제공한다. 실제 Apple 왕복 성공은 별도로 검증한다.

## 비공개 자료와 비용

Windows/WSL 작업 환경에만 있는 다음 자료는 공개 Git에 포함하지 않았다. 맥북에서 기존 개발자 로그인/보안 자격 저장소를 확인하고 필요한 자격은 안전하게 옮긴다. 키를 채팅이나 Git에 복사하지 않는다.

- `/home/kang/.local/share/carcar-release/apple.json`: 기존 API 키 경로 등. 파일 자체나 키 내용을 공개하지 않는다.
- `/home/kang/.local/share/carcar-release/app-store-review-contact.json`: 사용자 제공 심사 연락처, 권한 0600.
- `/home/kang/.local/share/carcar-release/backend-qa.json`: 서버 테스트 자격. 앱에 포함 금지.
- `docs/qa/appstore-readiness-2026-11-06/`: App Store 조회 결과, 사이트 검증·캡처.
- 비공개 빌드 저장소는 `kang88xx/60base-mobile-build`, 앱 경로는 `apps/carcar`다. 공개 앱 소스 `069dd4c`를 비공개 `release/carcar-apple-login-20261106`의 `6b2ea85`로 동기화했다. main은 변경하지 않았다.

GitHub Actions 추가 유료 예산은 $0/Usage blocked를 유지한다. 빌드 13은 18분 timeout 안에 11분 22초로 성공했다. 실행 후 Billing 화면에서 포함 compute $11.54/$12(잔여 $0.46), 저장소 0.3/0.5 GB, Actions 유료 청구 $0을 재확인했다. 추가 비공개 macOS CI 실행 전 잔액·예산을 다시 확인하고 로컬 검증을 우선한다. Supabase Free와 기기 내 OCR을 유지한다.

## 공식 근거

- [App Review 4.8 로그인](https://developer.apple.com/app-store/review/guidelines/#login-services)
- [Supabase Apple 로그인](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)
- [Apple 계정 삭제·토큰 철회 TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [OIDC ID Token 검증](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
- [스토어 버전 정보](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [스크린샷 규격](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
