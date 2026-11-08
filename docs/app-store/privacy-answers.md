# App Privacy 게시 답변·근거 · 2026-11-08

대상은 TestFlight **1.0.0 (13)**의 제품 소스 `069dd4c`다. 아래는 코드·스키마와 공급자 공식 문서에 근거해 App Store Connect에 게시한 답변이다. **실제 프로젝트 로그와 보관 설정은 직접 확인하지 않았으며 별도 점검이 필요하다.** 심사 연락처·개인 계정·인증키는 이 문서에 넣지 않는다.

## 게시 확인

2026-11-08 UTC에 Chrome 화면 제어로 아래 12개 유형을 저장·게시했다. 모든 유형은 **App Functionality / 사용자 연결 예 / 추적 아니요**로 입력했고, 화면에서 앱 기능 목적과 사용자 연결 표시가 각각 12개임을 확인했다. 사용자가 게시 확인창의 답변 정확성·관련 법 준수·변경 시 갱신 동의에 승인한 뒤 실행했으며, App Store Connect의 **‘몇 초 전에 게시함’** 표시로 완료를 확인했다. 이후 [최종 제출](https://github.com/kang88xx/60base-mobile-build/actions/runs/42488929909)이 수락돼 **WAITING_FOR_REVIEW**를 확인했다.

## 기본 답변

- **데이터 수집 여부: 예.** 로그인·가족 공유를 위해 계정과 주차 기록을 Supabase에 저장한다. 로그인 없이 쓰는 로컬 체험 모드만으로 앱 전체를 ‘수집 안 함’으로 신고할 수 없다.
- **권장 목적: 앱 기능 / App Functionality.** 인증, 소유자·구성원 권한, 주차 위치 공유·이력, 기기별 알림에 사용한다. 광고·마케팅·데이터 판매·분석 SDK 용도는 현재 제품 코드에서 발견하지 못했다.
- **사용자 연결: 예.** 서버 데이터가 인증 사용자 ID 또는 그 사용자의 차량·설치 ID와 연결된다. Apple 비공개 이메일을 사용해도 익명 데이터로 분류하지 않는다.
- **추적 / Tracking: 아니요.** `PrivacyInfo.xcprivacy`는 `NSPrivacyTracking=false`, 추적 도메인은 빈 배열이다. 앱 의존성에서 광고·교차 앱 추적 SDK를 발견하지 못했다. 공급자 설정과 실제 운영의 미확인 범위는 아래 남은 운영 확인 항목에 기록했다.

Apple은 앱 기능을 위한 서버 수집도 신고하도록 설명한다. 데이터 유형·사용 목적·사용자 연결·추적은 별도 질문이다. [Apple App Privacy 공식 안내](https://developer.apple.com/app-store/app-privacy-details/)

## 수집 항목과 권장 분류

| 실제 데이터 | App Store Connect 권장 유형 | 목적 / 사용자 연결 / 추적 | 코드 근거·남은 확인 |
| --- | --- | --- | --- |
| 가족에게 표시하는 이름, 로그인 공급자가 반환하는 이름 | Contact Info → Name | App Functionality / 연결됨 / 추적 안 함 | `profiles.nickname`; Google `openid email profile`, Apple name/email 요청. Apple 최초 이름이 기존 프로필을 자동 덮어쓰지는 않는다. |
| 로그인 이메일, Apple 비공개 릴레이 이메일 | Contact Info → Email Address | App Functionality / 연결됨 / 추적 안 함 | Supabase Auth 계정·공급자 identity로 인증. 이메일은 가족 차량 접근 권한이 아니다. |
| Supabase 사용자 ID, 공급자 identity, 차량 멤버십·작성자 ID | Identifiers → User ID | App Functionality / 연결됨 / 추적 안 함 | `auth.users`, `profiles.id`, `vehicle_members.user_id`, `parking_records.created_by`. |
| 앱 설치 UUID, 알림을 켠 기기의 APNs/FCM 토큰 | Identifiers → Device ID | App Functionality / 연결됨 / 추적 안 함 | `device_settings.installation_id`, `private.push_devices.token`. 플랫폼·알림 설정과 연결된다. IDFA 수집 경로는 발견하지 못했다. |
| 차량 별명·번호, 아파트 이름, 주차 층·구역·번호, 기존 메모 | User Content → Other User Content | App Functionality / 연결됨 / 추적 안 함 | 사용자가 입력·확인한 텍스트를 서버에 저장한다. 위치를 식별하는 입력은 아래 Precise Location에도 포함하는 것을 권장한다. |
| 아파트 이름과 층·구역·자리 번호의 조합 | Location → Precise Location | App Functionality / 연결됨 / 추적 안 함 | 실제 건물 내부 위치를 식별할 수 있어 보수적으로 포함. **Apple 정의를 적용한 추론**이며 GPS 수집을 뜻하지 않는다. |
| 서버 요청 IP에서 유래한 도시·국가·지역 | Location → Coarse Location | App Functionality / 연결됨 / 추적 안 함 | Supabase API Edge 로그의 `request.cf.*` 공식 문서 기준. 실제 프로젝트 로그 내용은 미조회. |
| 로그인·가입 등 인증 활동, 서버 요청 활동 | Usage Data → Product Interaction | App Functionality / 연결됨 / 추적 안 함 | Supabase Auth 감사 로그와 API 요청 로그. 별도 사용자 행동 분석 SDK 사용을 의미하지 않는다. |
| 서버 실행 시간 | Diagnostics → Performance Data | App Functionality / 연결됨 / 추적 안 함 | Supabase Edge 함수 호출 로그에 실행 시간이 포함된다. |
| 요청 상태·오류, 앱/브라우저 환경 정보 | Diagnostics → Other Diagnostic Data | App Functionality / 연결됨 / 추적 안 함 | Supabase API·함수 로그의 문제 진단 정보. |
| 보안·운영 요청 IP, 기기별 알림 설정·시간대 등 기능 메타데이터 | Other Data → Other Data Types | App Functionality / 연결됨 / 추적 안 함 | IP를 기기 식별자로 사용하는 코드 근거는 없어 IP 자체를 Device ID로 분류하지 않는다. 기록 시각은 해당 콘텐츠, 발송 결과·재시도 상태는 진단 맥락으로 함께 검토한다. |
| 사용자가 이메일로 보낸 문의 내용·첨부 자료 | User Content → Customer Support | App Functionality / 연결됨 / 추적 안 함 | 이메일 문의를 선택한 경우 처리. 발신 이메일은 Email Address에도 포함한다. |

근거 파일:

- [초기 데이터 모델](../../supabase/migrations/0001_initial.sql), [푸시 모델·RPC](../../supabase/migrations/20261102065349_family_push_delivery.sql)
- [로그인 화면](../../lib/features/auth_screen.dart), [iOS Apple 인증 요청](../../ios/Runner/AppDelegate.swift)
- [저장소 읽기·쓰기](../../lib/core/repository.dart), [기기 알림 설정](../../lib/core/device_notifications.dart)
- [개인정보 manifest](../../ios/Shared/PrivacyInfo.xcprivacy), [앱 의존성](../../pubspec.yaml)

## 위치·로그·문의 분류 근거

- **수동 주차 위치:** GPS·Core Location 좌표 조회나 위치 권한 요청은 발견하지 못했다. 아파트 이름과 상세 주차 자리는 실제 위치를 식별할 수 있으므로 Precise Location을 포함하는 보수적 권장안이다. 이는 Apple의 위치 정밀도 정의를 입력 조합에 적용한 추론이며, Apple이 주차 앱을 명시적으로 분류한 사례는 아니다. 아파트 이름만 수집하는 현재 입력을 우편 주소와 같다고 단정해 Physical Address를 추가하지는 않는다.
- **서버 로그:** Supabase 공식 문서는 API 로그의 요청 IP·도시·국가·지역·환경 정보, Auth의 인증 이벤트, 함수의 상태·오류·실행 시간을 설명한다. 위 표는 이 기본 처리 범위를 반영한다. 실제 프로젝트 로그를 직접 열람해 모든 필드가 존재한다고 확인한 것은 아니다. 콘솔에서 조회 가능한 기간은 공급자 전체 사본의 삭제 기한과 같지 않으므로 ‘1일 후 모두 삭제’라고 안내하지 않는다. [API 로그](https://supabase.com/kb/troubleshooting/discovering-and-interpreting-api-errors-in-the-logs-7xREI9), [Auth 감사 로그](https://supabase.com/docs/guides/auth/audit-logs), [함수 로그](https://supabase.com/docs/guides/functions/logging)
- **지원 문의:** 이메일 문의가 선택 사항이라는 이유만으로 신고에서 제외하지 않는다. Apple의 선택적 신고 면제 조건을 모두 충족했다는 근거가 없어 Customer Support 포함을 권장한다. 앱에는 문의 전송 폼이 없으며 이메일 주소·링크 복사 경로를 제공한다. [Apple의 데이터 유형·선택적 신고 조건](https://developer.apple.com/app-store/app-privacy-details/)

서버 로그도 사용자 ID·요청 IP 등과 연결될 수 있으므로 연결됨으로 권장한다. 별도로 비식별 처리된 로그라는 검증 없이 연결 안 됨으로 낮추지 않는다. 여기서 ‘추적 안 함’은 교차 앱·웹 광고 추적에 관한 답변이며 보안·운영 로그가 없다는 뜻이 아니다.

## 현재 서버로 보내지 않는 데이터

- **사진·영상:** 카메라/앨범 사진은 `image_picker`로 받은 기기 경로를 iOS Vision OCR에 전달한다. 사용자가 확인한 텍스트만 주차 기록으로 저장하며 현재 앱 흐름에 원본 사진 업로드는 없다. 초기 스키마의 `image_path` 열만으로 사진 수집을 선언하지 않는다. [주차 입력](../../lib/features/parking_form.dart), [기기 OCR](../../ios/Runner/AppDelegate.swift)
- **생체정보:** Apple 인증의 OS 확인 화면을 사용하며 앱이 Face ID 원본·생체 템플릿을 받는 구현은 없다.
- **주소록·결제·건강 데이터:** 해당 입력·권한·SDK 처리 경로를 현재 제품 코드에서 발견하지 못했다. 가족 구성원 관계는 앱에 저장하지만 기기 주소록을 읽지는 않는다.
- **검색어·화면 동작 분석:** 주차 이력 검색은 앱 내부 표시 필터이며 별도 검색어 업로드·행동 분석 SDK는 발견하지 못했다. 서비스 제공자의 접속·오류 로그까지 없다고 단정하지 않는다.

카메라·사진 접근 권한과 App Privacy의 서버 수집 신고는 같은 질문이 아니다. 기기 안에서만 처리하는 데이터와 외부에 보관되는 데이터를 구분한다. [Apple App Privacy 공식 안내](https://developer.apple.com/app-store/app-privacy-details/)

## 처리·공유·삭제 범위

- Supabase가 인증과 DB를 처리한다. 같은 차량의 승인된 구성원이 주차 위치·이력을 읽는다. 차량번호만 알아서는 참여할 수 없다.
- iOS 알림은 APNs, Android 알림은 FCM을 사용한다. 기기 토큰은 공개 테이블에 노출하지 않는다. 주차 알림 본문에 상세 위치·번호판·이름을 넣지 않는다.
- Apple 연결 해제 Edge 함수는 인증 코드·교환 토큰을 요청 처리 중 사용하고 장기 저장하지 않는다. 계정 삭제는 별도 서버 RPC가 수행한다. [Apple 연결 해제 계약](../../supabase/deployment/APPLE_SIGN_IN.md)
- 소유자 계정 삭제 시 소유 차량·공유 기록을 삭제하며, 다른 차량에 남긴 기록은 작성자 식별을 제거해 보존한다. 알림 토큰 등록 해제는 네트워크 상황에 따라 실패할 수 있어 앱에서 안내한다. [계정 삭제 RPC](../../supabase/migrations/20261102102648_single_vehicle_registration.sql), [계정·알림 안내](../../lib/features/management.dart)

## 남은 운영 확인 항목

1. 실제 Supabase 로그·보관 설정, APNs 및 포함 SDK의 처리 범위를 대조한다. 수집된 로그를 확인할 때 개인정보·인증 정보를 공개 문서나 저장소에 복사하지 않는다.
2. 지원 이메일의 실제 처리·보관 운영과 위 권장 분류를 대조한다. 확인되지 않은 보관 기간을 약속하지 않는다.
3. 현재 앱·[공개 개인정보 페이지 원본](../../site/privacy/index.html)·App Store Connect 응답을 맞춘다. 수동 주차 위치의 Precise Location 분류가 공식 사례가 아닌 보수적 추론임을 제출 담당자가 확인한다.
4. 향후 답변을 수정하면 저장 후 게시 상태를 다시 확인한다. 이번 게시 완료 근거는 위의 App Store Connect 화면 확인 기록이며, 문서 수정만으로 원격 상태가 변경되지는 않는다.
