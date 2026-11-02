# 차곡 · 우리 차의 자리

가족이 함께 쓰는 차량의 마지막 주차 위치를 기록하는 한국어 Flutter 앱입니다. Android·iOS 네이티브 프로젝트와 화면 확인용 웹 미리보기를 포함합니다.

소스 기준 저장소는 [kang88xx/carcar-kang88](https://github.com/kang88xx/carcar-kang88)입니다. TestFlight 서명과 배포는 기존 비공개 CI에서 실행하며 인증서·서버 비밀키·계정별 QA 기록은 공개 저장소에 포함하지 않습니다.

## 실행

Flutter 3.35.4 / Dart 3.9.2 기준입니다. iOS 앱은 15.0 이상, 위젯·차량 찾기는 iOS 17 이상을 지원합니다. Android 최소 버전은 API 24입니다. iOS 빌드와 Simulator 실행에는 Mac/Xcode가 필요합니다.

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

서버 secret/service_role·APNs·FCM 서버 자격은 앱·위젯에 넣지 않습니다. `android/app/src/main/res/values/firebase.xml`은 차곡 앱의 공개 Firebase 클라이언트 설정이며 서버 인증 키가 아닙니다. 별도 앱으로 운영할 때에는 해당 앱의 Firebase 클라이언트 설정으로 교체하세요.

## 구현한 기능

- 이메일 로그인·가입 확인 재요청·비밀번호 복구·표시 이름 편집·계정 삭제
- 차량 선택·가족 공유 차량 색상·아파트 층과 구역 설정
- 소유자/구성원 권한·만료형 일회용 초대·구성원 제거와 탈퇴
- 서버 확인 후 주차 저장·중복 요청 방지·검색 가능한 이력·Realtime
- Android ML Kit·iOS Vision 사진 인식과 편집 가능한 후보; 원본 사진은 서버에 업로드하지 않음
- 네이티브 위젯의 위치 표시·층과 구역 선택·서버 저장
- 기기별 가족 알림·야간 시간대·독립적인 차량 찾기 표시
- iOS Live Activity와 기기별 대체 런처 아이콘 8종

## 검증

Flutter 자동 검사 123개와 분석, 기본 브라우저 조작 12개, 연결 인증 화면 19개를 통과했습니다. iOS Simulator에서는 저장·이력·Vision OCR·아이콘 조회·설정과 취소 상태 유지·네이티브 패키징을 확인했습니다. iOS 최소 버전은 실제 컴파일된 앱과 위젯에서도 검사하며, 배포 전에는 각각 15.0과 17.0이어야 합니다.

```bash
flutter pub get
bash scripts/check.sh
python3 fastlane/test_prepare_signing.py
node --test supabase/tests/push_worker.test.mjs
# Mac/Xcode에서 실행
bash scripts/ios_qa.sh
```

소스 저장소의 `Verify app` CI는 포맷·분석·테스트·웹 빌드를 실행합니다. TestFlight 배포와 실제 휴대폰 검증은 별도입니다. 개인 배포 정보가 있는 상세 로그는 로컬 및 비공개 빌드 저장소에서 보존합니다.

**남은 검증:** 가입 확인·비밀번호 복구 메일용 발신 도메인/SMTP 연결, TestFlight 실제 설치, 두 기기 푸시 수신, 홈 위젯 배치·앱 종료 후 저장, 카메라 권한·실제 표지판 사진, Live Activity. Android 소프트웨어 에뮬레이터는 시스템 ANR로 전체 통합 검사를 완료하지 못했습니다. Live Activity의 최대 8시간은 활동 시작 기준이며 앱 중단 시 선택한 1/2/4시간의 정확한 종료를 보장하지 않습니다.

## 빌드

```bash
flutter build apk --debug --dart-define-from-file=config/local.json
flutter build web --release
bash scripts/preview.sh
```

Android 개발용 APK는 `build/app/outputs/flutter-apk/app-debug.apk`에 생성됩니다. Play 출시용 서명키는 포함하지 않습니다. 웹 미리보기는 카메라·위젯·푸시의 실제 휴대폰 검증을 대신하지 않습니다.

독립 iOS 서명 환경을 구성할 경우 수동 `Upload TestFlight build` workflow가 요구하는 환경 변수와 GitHub Secrets를 설정해야 합니다. 현재 차곡 배포에는 기존 비공개 CI를 사용합니다. 비밀키를 공개 workflow 파일에 직접 넣지 않습니다.

## 설계와 서버

[제품 요구사항](docs/PRD.md), [아키텍처](docs/ARCHITECTURE.md), [디자인 기준](DESIGN.md), [보안과 비용](docs/SECURITY_AND_COST.md), [결정 기록](docs/DECISIONS.md), [QA 수용 기준](docs/ROADMAP_AND_QA.md), [푸시 배포 계약](supabase/deployment/PUSH.md)을 참고하세요.

Supabase migration은 `supabase/migrations/`에 순서대로 보존합니다. 새 개발 프로젝트에 적용하며 기존 운영 DB에는 검토 없이 재적용하지 않습니다. 월 서버비 $0을 목표로 Supabase Free와 기기 내 OCR을 사용합니다.
