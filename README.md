# 차자리

**2026-11-13 · 1.0.2 (16) 심사 제출 완료.** 위젯·아이콘 비교를 첫 장, 주차 등록을 두 번째로 배치한 iPhone·iPad 각 5장과 새 부제·소개 문구를 반영했습니다. Apple 응답은 `WAITING_FOR_REVIEW`, 승인 후 자동 출시입니다. 공개 버전은 1.0.1이며 아래 이전 심사 대기 기록보다 이 내용을 우선합니다. [제출 결과와 검증](docs/app-store/PUBLISH_1.0.2.md).

가족이 함께 쓰는 차량의 마지막 주차 위치를 기록하는 한국어 Flutter 앱입니다. Android·iOS 네이티브 프로젝트와 화면 확인용 웹 미리보기를 포함합니다.

2026-11-03 앱 이름을 **차곡 → 차자리**로 확정하고 앱·위젯·웹·사이트 표시명에 반영했습니다. 패키지명·Bundle ID·App Group·딥링크 식별자는 호환성을 위해 유지합니다. 자세한 내용은 [결정 기록](docs/DECISIONS.md)을 참고하세요.

소스 기준 저장소는 [kang88xx/carcar-kang88](https://github.com/kang88xx/carcar-kang88)입니다. TestFlight 서명과 배포는 기존 비공개 CI에서 실행하며 인증서·서버 비밀키·계정별 QA 기록은 공개 저장소에 포함하지 않습니다.

**2026-11-11 · App Store 업데이트 1.0.1 (15) 심사 제출.** 버전 1.0 (13)은 2026-11-08 승인되어 한국 App Store에 공개 중입니다(공개 조회와 App Store Connect `READY_FOR_DISTRIBUTION` 확인). 같은 날 반영한 쉬운 사용 우선 정리(앱 소스 `0c90de1`)를 [빌드 15 비공개 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/43024120354)로 서명·업로드했고(Apple 처리 `VALID`, 내부 테스트 그룹 연결), 새 버전 1.0.1에 새 기능 문구·심사 안내·새 스크린샷 8장·빌드 15를 연결해 [심사에 제출](https://github.com/kang88xx/60base-mobile-build/actions/runs/43026432850)했습니다. 제출·버전 상태는 `WAITING_FOR_REVIEW`, 출시 방식은 승인 후 자동 출시입니다. 이 빌드의 실기기 확인은 아직입니다. 자세한 기록은 [인계 문서](docs/APP_STORE_HANDOFF.md) 맨 위를 따릅니다.

이전 TestFlight는 **1.0.1 (14)**입니다. 2026-11-10 자리 핀 앱 아이콘·층수 핀 아이콘·저장 층을 따라가는 홈 헤더 핀·브랜드 블루 톤을 담았으며, [빌드 14 비공개 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42659222423) 성공과 Apple 처리 `VALID`, 내부 테스트 그룹 연결을 확인했습니다. App Store에 승인된 1.0.0 트레인은 닫혀 있어 마케팅 버전을 1.0.1로 올렸습니다. 앱 소스는 `ac54e4d`, 비공개 빌드 소스는 `b8bebc0`(`release/carcar-pin-icon-20261110`)입니다. 실기기 설치·아이콘 전환 확인은 아직입니다.

이전 TestFlight **1.0.0 (13)**은 Apple 로그인·안전한 계정 삭제·UIScene 전환·공개 고객지원 UI를 포함하며, [비공개 배포 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42215777783) 성공과 Apple 처리 `VALID`, 기존 내부 테스트 그룹 연결을 확인했습니다. 앱 소스는 `069dd4c`, 비공개 빌드 소스는 `6b2ea85`(`release/carcar-apple-login-20261106`)입니다. 2026-11-08 사용자가 Apple 로그인·주차 저장 성공을 보고했습니다. 에이전트는 실기기 미러링으로 로그인 상태·화면 탐색·입력 취소 후 기존 기록 보존을 확인했으며, 설치 빌드 번호 직접 조회와 실제 인증 왕복·계정 삭제 검증은 별도입니다.

## App Store 등록 진행 · 2026-11-08

[등록 준비 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42486691651)가 성공했습니다. 설명·부제·카테고리·지원/개인정보 링크·저작권·심사 연락처와 한/영 심사 안내, 무료·대한민국 배포, 연령 등급을 반영·재조회했습니다. 기존 스토어 버전 1.0에 빌드 1.0.0 (13)을 연결했고 iPhone/iPad 스크린샷 각 4장도 업로드 완료·checksum 일치를 확인했습니다. 출시 옵션은 심사 승인 후 출시(`AFTER_APPROVAL`)입니다.

**App Store 심사 제출을 완료했습니다.** 개인정보 12개 유형의 답변을 Chrome에서 입력하고 사용자 동의를 받아 게시했습니다. [최종 제출 CI](https://github.com/kang88xx/60base-mobile-build/actions/runs/42488929909)는 2026-11-08 23:16 KST에 성공했고, Apple 재조회에서 버전과 제출 상태 모두 **`WAITING_FOR_REVIEW`(심사 대기 중)**, `submitted=true`, 차단 항목 없음이 확인됐습니다. 심사 승인·공개가 완료된 상태는 아니며, 승인되면 대한민국 App Store에 무료로 자동 출시됩니다. 지금은 Apple 심사 결과를 기다리며 중복 제출하지 않습니다. 게시 내용과 남은 실기기 검증은 [인계 문서](docs/APP_STORE_HANDOFF.md)를 따릅니다.

## 실행

Flutter 3.47.9 / Dart 3.13.7 기준이며 공개 저장소의 세 CI workflow도 Flutter 3.47.9를 사용합니다. iOS 앱은 15.0 이상, 위젯·차량 찾기는 iOS 17 이상을 지원합니다. Android 최소 버전은 API 24입니다. iOS 빌드와 Simulator 실행에는 Mac/Xcode가 필요합니다.

현재 맥북에는 새 SDK를 `~/development/flutter-3.47.9`에 설치했고 이전 `~/development/flutter`의 3.35.4는 보존했습니다. 이 맥북에서 작업할 때는 다음 환경을 사용합니다.

```bash
export PATH="$HOME/development/flutter-3.47.9/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Xcode 27.2의 iOS 27 실행 요구에 맞춰 UIScene 생명주기로 전환했습니다. Swift Package Manager 통합을 사용하며, 아직 이를 지원하지 않는 `flutter_secure_storage` 9.2.4는 CocoaPods로 연결하므로 CocoaPods도 필요합니다. 로컬 Simulator 빌드는 성공했고, 실행·인증·배포 검증 결과는 [인계 문서](docs/APP_STORE_HANDOFF.md)를 따릅니다.

```bash
flutter pub get
flutter run
```

설정 없이 실행하면 기기 안에만 기록하는 체험 모드로 시작합니다. 실제 가족 공유에는 별도로 설정한 Supabase 프로젝트가 필요합니다.

```bash
cp config/example.json config/local.json
# local.json에 프로젝트 URL과 공개 publishable/anon 키만 입력
flutter run --dart-define-from-file=config/local.json
```

서버 secret/service_role·APNs·FCM 서버 자격은 앱·위젯에 넣지 않습니다. `android/app/src/main/res/values/firebase.xml`은 차자리 앱의 공개 Firebase 클라이언트 설정이며 서버 인증 키가 아닙니다. 별도 앱으로 운영할 때에는 해당 앱의 Firebase 클라이언트 설정으로 교체하세요.

## 구현한 기능

아래는 현재 소스 기준입니다. 2026-11-11 정리(차량 등록 간소화·iPhone 층수 아이콘 스위치·받은 초대 한 번 탭 참여 등, [결정 기록](docs/DECISIONS.md))는 TestFlight 1.0.1 (15)에 담겨 App Store 업데이트 심사 대기 중이며, 공개된 1.0 (13)과 TestFlight 1.0.1 (14)에는 포함되지 않았습니다.

- Google·iOS Apple 로그인, 표시 이름 편집, 계정 전환을 방어하는 삭제와 Apple 연결 해제
- 설정의 공개 고객지원·개인정보 안내
- 계정당 차량 한 대·차량 번호 중복 등록 차단(등록 시 서버 확인)·아파트 층과 구역 설정
- 소유자/구성원 권한·초대 링크를 받은 가족은 로그인 후 버튼 한 번으로 참여(코드 직접 입력도 가능)·한 사람용 24시간 초대·구성원 제거와 탈퇴
- 서버 확인 후 주차 저장·중복 요청 방지·검색 가능한 이력·Realtime
- Android ML Kit·iOS Vision 사진 인식과 편집 가능한 후보; 원본 사진은 서버에 업로드하지 않음
- 정사각형 네이티브 위젯의 기록 시각·위치 표시와 앱의 주차 입력 화면 바로 가기(앱 이름 없는 고대비 위젯)
- 기기별 가족 알림·야간 시간대·독립적인 차량 찾기 표시
- 얇은 iOS Live Activity와 표시 종료 버튼·Dynamic Island의 자동차/층수 묶음
- 자리 핀 앱 아이콘과 주차 층수를 핀 안에 표시하는 층수 아이콘 11종(F1–F5, B1–B6; iPhone은 설정에서 켠 기기만 적용·기본 꺼짐, Android는 자동), 저장 층에 맞춰 함께 바뀌는 홈 헤더 핀·홈 화면 위젯 추가 안내

## 검증

현재 배포 대상 소스는 Flutter **268개 통과 / 4개 선택 검사 건너뜀**, Python **19개**, Node **70개** 검사를 통과했고 분석·포맷 검사도 성공했습니다. 2026-11-08 등록·배포·제출 도구의 별도 Node 검사 **57/57개**와 Dart 포맷 **46개 파일·변경 0개**, `flutter analyze --no-pub` **문제 0개**를 확인했습니다. 제품 코드는 `069dd4c` 그대로입니다. Flutter 자동 검사와 분석, 브라우저 조작, DB 보안·동시성 검사를 수행합니다. iOS 최소 버전은 실제 컴파일된 앱과 위젯에서도 각각 15.0과 17.0으로 검사합니다. 최신 변경의 iOS 배포와 실기기 결과는 별도 확인이 필요합니다.

```bash
flutter pub get
bash scripts/check.sh
python3 fastlane/test_prepare_signing.py
node --test supabase/tests/push_worker.test.mjs
# Mac/Xcode에서 실행 (QA용 XCTest 생성기에 기존 fastlane 의존성 사용)
BUNDLE_GEMFILE=fastlane/Gemfile bundle install
bash scripts/ios_qa.sh
```

소스 저장소의 `Verify app` CI는 포맷·분석·테스트·웹 빌드를 실행합니다. TestFlight 배포와 실제 휴대폰 검증은 별도입니다. 개인 배포 정보가 있는 상세 로그는 로컬 및 비공개 빌드 저장소에서 보존합니다.

2026-11-06 홈·주차 입력 수정은 iOS 화면을 우선 검증합니다. 다음 명령은 실제 Flutter 화면을 iOS 테마·안전 영역·그림자로 렌더링해 `docs/qa/ios-fixed-header/`에 캡처합니다. 홈·이력·가족·설정의 초기/스크롤 후 화면과 입력창을 320/393px, 기본/1.3배 글자로 확인합니다. 이전 캡처는 `docs/qa/ios-ui-cleanup/`과 `docs/qa/ios-footer-review/`에 보존합니다. Xcode·iOS 실기기 검증을 대신하지 않으며, Android 검증은 별도입니다.

```bash
flutter test --no-pub test/ios_ui_capture_test.dart --dart-define=CAPTURE_IOS_UI=true
```

**실기기 검증:** 2026-11-08 Apple 로그인·주차 저장 성공은 사용자 보고입니다. 직접 미러링으로 로그인된 홈·이력·가족·설정과 입력 취소 후 기존 기록 보존을 확인했습니다. 실제 설치 빌드 번호는 직접 확인하지 못했습니다. 실기기 QA 원본 영상은 약 90초로 저장했고, 디코딩한 장면에서 가족·설정·입력·취소·기존 홈 복귀를 확인했습니다. 폰 영역만 남기고 끝의 대기 구간을 정리한 84초 MP4도 최종 장면 검증을 통과했습니다. 실제 개인정보가 있어 원본과 정리본 모두 비공개로 보관합니다. 이 영상은 새 로그인·운영 저장·OCR·가족 공유·삭제 성공을 검증하지 않습니다. 카메라 OCR·Face ID·두 기기 공유·푸시·Apple 철회·계정 삭제와 홈 위젯은 추가 실기기 검증이 필요합니다. iOS 앱 아이콘 변경에는 시스템 안내가 표시될 수 있으며(빌드 13·14는 자동 변경, 2026-11-11 이후 소스는 설정에서 켠 iPhone에서만 변경), 앱이 닫힌 동안 다른 가족이 변경한 층은 다음 실행에서 반영합니다. 홈 화면 위젯은 사용자가 직접 배치합니다. Live Activity의 최대 8시간은 활동 시작 기준이며 앱 중단 시 선택한 1/2/4시간의 정확한 종료를 보장하지 않습니다.

**스토어 촬영 자료:** `build/app-store-media-20261108/delivery/index.html`에서 시뮬레이터 체험 데이터의 홈·입력·가족·이력 JPEG 8장을 볼 수 있습니다(iPhone 1320×2868, iPad 2064×2752, 각 4장). alpha 없음·시각 검토를 통과했고 네이티브 홈 위젯은 아직 촬영하지 않았습니다. MOV 2개는 28.25/29.42초 QA 영상이며 App Preview 제출본이 아닙니다. 같은 상위 폴더의 `차자리-스토어-촬영자료.zip`은 13개 파일·7.99 MB로 검증했습니다. 실기기 개인정보 자료는 별도로 보호합니다. JPEG 8장은 App Store 업로드 완료를 확인했으며 심사 제출 결과는 위 등록 진행 상태를 따릅니다.


## 빌드

```bash
flutter build apk --debug --dart-define-from-file=config/local.json
flutter build web --release
bash scripts/preview.sh
```

Android 개발용 APK는 `build/app/outputs/flutter-apk/app-debug.apk`에 생성됩니다. Play 출시용 서명키는 포함하지 않습니다. 웹 미리보기는 카메라·위젯·푸시의 실제 휴대폰 검증을 대신하지 않습니다.

독립 iOS 서명 환경을 구성할 경우 수동 `Upload TestFlight build` workflow가 요구하는 환경 변수와 GitHub Secrets를 설정해야 합니다. 현재 차자리 배포에는 기존 비공개 CI를 사용합니다. 비밀키를 공개 workflow 파일에 직접 넣지 않습니다.

## 설계와 서버

[제품 요구사항](docs/PRD.md), [아키텍처](docs/ARCHITECTURE.md), [디자인 기준](DESIGN.md), [보안과 비용](docs/SECURITY_AND_COST.md), [결정 기록](docs/DECISIONS.md), [QA 수용 기준](docs/ROADMAP_AND_QA.md), [푸시 배포 계약](supabase/deployment/PUSH.md)을 참고하세요.

Supabase migration은 `supabase/migrations/`에 순서대로 보존합니다. 새 개발 프로젝트에 적용하며 기존 운영 DB에는 검토 없이 재적용하지 않습니다. 월 서버비 $0을 목표로 Supabase Free와 기기 내 OCR을 사용합니다.

새 주차 기본값(F1~F5/B1~B5, A~F/가~바)은 `20261106034310_parking_option_defaults.sql`에 포함합니다. 2026-11-06 서버에 적용하고 기본값·기존 이력·접근 권한 유지까지 확인했습니다. 사용자 지정 설정과 주차 이력은 보존합니다.

## Google 로그인과 초대 링크

Supabase Google provider에 Web OAuth 클라이언트를 연결하고, Google의 승인된 redirect URI에는 해당 Supabase 프로젝트의 `/auth/v1/callback`을 등록합니다. 클라이언트 비밀키는 Supabase 설정에만 보관합니다. Supabase 추가 redirect URL에는 `com.kang88.carcar://login-callback`을 등록합니다.

가족 초대 링크는 GitHub Pages의 `site/invite/`를 사용합니다. 코드는 URL fragment에 두어 웹 서버 요청에 포함하지 않으며, 페이지에서 사용자가 앱 열기를 눌러 전달합니다. 앱 미설치 시 코드를 복사해 설치·로그인 후 사용할 수 있습니다. 차량 번호는 소유권 인증이 아니며 가족 접근 권한은 유효한 초대로만 부여합니다.
