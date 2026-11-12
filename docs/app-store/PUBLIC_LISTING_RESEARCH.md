# 차자리 공개 소개 개선 · 2026-11-13

새 문구는 [public-listing-ko.json](public-listing-ko.json)에 보관한다. 기존 제출·승인 기록을 수정하지 않는 로컬 초안이다. 현재 소스의 iPhone 층수 아이콘 설정을 소개하므로 최소 기준은 `0c90de1`, 빌드 `1.0.1 (15)`다. README의 과거 기록은 1.0.1 심사 대기였으나, 2026-11-13 리더가 [Apple 공개 lookup](https://itunes.apple.com/lookup?id=6829616379&country=kr)으로 앱 ID·판매자와 공개 버전 1.0.1(출시 시각 2026-11-11T21:42:50Z)을 재확인했다. 현재 App Store Connect의 편집 가능한 버전은 아직 확인하지 않았다. 새 스크린샷은 다음 편집 가능한 버전에 연결해야 한다.

## 조사와 적용

Apple은 첫 1~3장의 스크린샷에 핵심 가치를 담고 각 화면을 주요 편익에 집중시키도록 안내한다. 그래서 기능 설정 화면 자체보다 홈 화면에서 주차 층을 확인하는 결과를 먼저 보여준다. 두 번째는 기록 과정, 이후 홈·가족·이력의 기존 상대 순서를 유지한다. [Apple 제품 페이지 가이드](https://developer.apple.com/app-store/product-page/)

Apple은 실제 기능과 관련 있는 화면과 검증 가능한 표현을 요구한다. ‘3초 완료’, 자동 위치 추적, 모든 기기 즉시 동기화 같은 근거 없는 약속은 사용하지 않는다. [Apple 에셋 모범 사례](https://developer.apple.com/app-store/asset-best-practices/)

공식 경쟁 앱 소개는 자동 기록·GPS·층 추정이나 사진 입력·위젯을 강조한다. 차자리는 ‘집 아파트의 층과 구역’과 ‘한 차를 번갈아 타는 가족’이라는 상황을 앞세운다. 경쟁 앱의 문구는 개발자의 설명이며 기능 품질을 독립 검증한 결과가 아니다. [내차는 어디에](https://apps.apple.com/kr/app/내차는-어디에/id6755907889), [어디댔지](https://apps.apple.com/kr/app/어디댔지-자동-주차-위치-기록/id6822791383)

이 구성은 조사에 근거한 포지셔닝 제안이며, 다운로드 전환율 향상이 측정된 결과는 아니다. 게시 후 같은 기간의 제품 페이지 조회 대비 다운로드 비율을 비교하되 유입 경로 변화도 함께 확인한다.

## 문구 방향

가족 초대를 받아야만 쓸 수 있다는 인상을 줄이고, 혼자 기록한 뒤 필요할 때 가족을 초대할 수 있음을 설명한다. ‘차 어디 뒀어?’라는 실제 상황으로 시작하고, 기능 목록보다 층·구역 확인, 입력, 함께 확인의 흐름을 전달한다. 다운로드 전 필요한 조건은 설명 마지막에 모은다.

| 순서 | 화면 | 전달할 편익 |
| --- | --- | --- |
| 1 | 위젯·아이콘 | 앱을 열기 전 주차 층 확인 |
| 2 | 주차 등록 | 층·구역 선택과 선택 사항인 자리 번호 |
| 3 | 홈 | 마지막 위치·기록자·시각 확인 |
| 4 | 가족 | 초대받은 구성원과 같은 기록 확인 |
| 5 | 이력 | 이전 위치와 시각 다시 찾기 |

첫 장은 기본 아이콘+B2 위젯 → 층수 아이콘 켬+B2 위젯 → B3 기록 후 아이콘·위젯의 세 상태를 비교한다. 스위치는 아이콘에만 영향을 주며, 위젯은 저장한 기록을 보여준다. 위젯 테마 설정이 있는 것처럼 표현하지 않는다. 첫 장은 제품의 SwiftUI 위젯 코드를 별도 Simulator 호스트에서 렌더링한 구성요소와 실제 앱 아이콘 자산을 조합한다. OS 홈 화면 촬영이 아니며 실기기 갱신 검증을 뜻하지 않는다. 나머지 화면은 기존 빌드 15의 네이티브 Simulator 촬영본을 사용하고 체험 데이터 표시를 보존한다.

## 사실 확인 기준

- `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`: 계정당 차량 한 대·집 아파트 한 곳·수동 기록·iPhone 아이콘 기본 꺼짐.
- `docs/SECURITY_AND_COST.md`: 차량번호는 접근 권한이 아니며 초대받은 구성원만 공유. 원본 사진은 기기에서 처리하고 서버로 업로드하지 않음.
- `README.md`, `docs/ROADMAP_AND_QA.md`: iOS 15 이상 앱, iOS 17 이상 위젯·차량 찾기. 실제 기기 검증과 소스 구현 구분.
- 다른 가족의 아이콘 변경은 앱 재실행 때 반영되며 위젯 즉시 갱신은 보장하지 않음. Live Activity 최대 8시간은 시작 기준.
- Google Play 공개를 주장하지 않음. 다운로드 대상 앱 ID는 `6829616379`이며 동명 타사 앱과 구별.

## 검증

JSON 파싱, 필드 길이, 키워드 UTF-8 바이트 수, 다섯 화면 순서와 세 가지 첫 화면 상태를 확인한다. 앱 코드·서버·배포 설정 변경이 없는 문서 전용 변경이다. 게시 완료나 새 빌드 배포를 의미하지 않는다.

## 제작 결과와 검증

- 검토 갤러리: `build/app-store-refresh-20261113/gallery-final/index.html`. 같은 폴더의 `listing-ko.txt`에서 설명을 복사할 수 있다.
- 전달 묶음: `build/app-store-refresh-20261113/chajari-store-review.zip` (약 3.6 MB). iPhone 1320×2868, iPad 2064×2752 JPEG 각 5장과 소개 문구를 포함한다.
- 10장 모두 크기·불투명 JPEG·출처 및 결과 SHA-256 검증 성공. 제목·설명·이미지의 캔버스 경계 검사 통과. 첫 장과 주차 등록 화면을 시각 확인했다.
- `dart format --output=none --set-exit-if-changed lib test integration_test`: 51개 파일, 변경 0개.
- `flutter analyze --no-pub`: 문제 없음.
- `flutter test --no-pub test/floor_icon_sync_test.dart test/widget_access_test.dart`: 21개 통과.
- `node --test scripts/store_gallery.test.mjs test/site_invite.test.mjs`: 10개 통과. `node --check scripts/build_store_gallery.mjs`, `git diff --check` 성공.
- 보조 공개 소개 페이지는 TestFlight 안내를 App Store 다운로드로 바꾸고 사용 상황·시작 방법·FAQ를 보강했다. 320/390/768/1280px에서 가로 넘침·브라우저 오류 없음, 다운로드 앱 ID 확인.

첫 장은 홈 화면 실촬영이 아닌 구성요소 렌더다. `review-manifest.json`에는 `complete: true`, `reviewRequired: true`, `submissionReady: false`를 기록하며 자동 제출용 manifest는 만들지 않는다. 현재 공개 버전의 스크린샷을 원격 교체하거나 새 버전을 만들지 않았다. 이번 결과는 정적 스크린샷 자료이며 App Preview 동영상 제출본은 아니다.

재생성은 기존 촬영 자료와 `native/manifest.json`이 있는 로컬 환경에서 `PLAYWRIGHT_MODULE`을 설치된 Playwright의 `index.mjs` 경로로 지정한 뒤 실행한다. 새 의존성을 추가하지 않는다.

```sh
node scripts/build_store_gallery.mjs \
  --source-root build/app-store-media-20261111 \
  --native-root build/app-store-refresh-20261113/native \
  --output build/app-store-refresh-20261113/gallery-new
```
