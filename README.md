# 차자리

가족이 함께 쓰는 차량의 마지막 주차 위치를 기록하는 한국어 Flutter 앱입니다. Android·iOS 네이티브 프로젝트와 화면 확인용 웹 미리보기를 포함합니다.

2026-11-03 앱 이름을 **차곡 → 차자리**로 확정하고 앱·위젯·웹·사이트 표시명에 반영했습니다. 패키지명·Bundle ID·App Group·딥링크 식별자는 호환성을 위해 유지합니다. 자세한 내용은 [결정 기록](docs/DECISIONS.md)을 참고하세요.

소스 기준 저장소는 [kang88xx/carcar-kang88](https://github.com/kang88xx/carcar-kang88)입니다. TestFlight 서명과 배포는 기존 비공개 CI에서 실행하며 인증서·서버 비밀키·계정별 QA 기록은 공개 저장소에 포함하지 않습니다.

최신 TestFlight는 **1.0.0 (12)**입니다. 2026-11-06 네 탭의 헤더 고정과 작은 화면의 기록 버튼 문구 개선을 배포했고 Apple 처리 및 내부 테스트 그룹 연결을 확인했습니다. 이전 정사각형 위젯·홈·주차 입력·하단 메뉴 개선도 포함합니다. 실제 기기 동작 확인은 별도로 진행합니다.

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

- Google 로그인·표시 이름 편집·계정 삭제
- 계정당 차량 한 대·차량 번호 중복 확인·아파트 층과 구역 설정
- 소유자/구성원 권한·초대 링크 또는 코드로 가족 참여·24시간 일회용 초대·구성원 제거와 탈퇴
- 서버 확인 후 주차 저장·중복 요청 방지·검색 가능한 이력·Realtime
- Android ML Kit·iOS Vision 사진 인식과 편집 가능한 후보; 원본 사진은 서버에 업로드하지 않음
- 정사각형 네이티브 위젯의 기록 시각·위치 표시와 앱의 주차 입력 화면 바로 가기(앱 이름 없는 고대비 위젯)
- 기기별 가족 알림·야간 시간대·독립적인 차량 찾기 표시
- 얇은 iOS Live Activity와 표시 종료 버튼·Dynamic Island의 자동차/층수 묶음
- 주차 층수만 표시하는 앱 아이콘 11종(F1–F5, B1–B6)·홈 화면 위젯 추가 안내

## 검증

Flutter 자동 검사와 분석, 브라우저 조작, DB 보안·동시성 검사를 수행합니다. iOS 최소 버전은 실제 컴파일된 앱과 위젯에서도 각각 15.0과 17.0으로 검사합니다. 최신 변경의 iOS 배포와 실기기 결과는 별도 확인이 필요합니다.

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

**실기기 검증:** TestFlight 설치와 기존 Live Activity 표시를 사용자 화면으로 확인했습니다. 최신 Google 로그인 왕복, 두 기기 가족 공유·푸시, 홈 위젯 배치·앱 종료 후 저장, 새 Live Activity 종료 버튼과 층수 아이콘은 각 빌드에서 검증해야 합니다. iOS 앱 아이콘 변경에는 시스템 안내가 표시될 수 있으며, 앱이 닫힌 동안 다른 가족이 변경한 층은 다음 실행에서 반영합니다. 홈 화면 위젯은 운영체제의 추가 화면에서 사용자가 직접 배치합니다. Live Activity의 최대 8시간은 활동 시작 기준이며 앱 중단 시 선택한 1/2/4시간의 정확한 종료를 보장하지 않습니다.


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

가족 초대 링크는 GitHub Pages의 `site/invite/`를 사용합니다. 코드는 URL fragment에 두어 웹 서버 요청에 포함하지 않으며, 페이지에서 사용자가 앱 열기를 눌러 전달합니다. 앱 미설치 시 코드를 복사해 설치·로그인 후 사용할 수 있습니다. 번호 중복 확인은 차량 소유권 인증이 아니며 가족 접근 권한은 유효한 초대로만 부여합니다.
