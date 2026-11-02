# 보안 / 개인정보 / 비용 및 배포

## 보안 필수 사항
1. 차량번호는 비밀 키가 아니다. 동일 번호 입력만으로 기존 가족 차량에 자동 가입시키지 않는다.
2. 초대 코드는 충분히 랜덤한 고엔트로피 값, 만료 및 사용 횟수 제한, 해시 저장, 발급·교환 rate limit.
3. 모든 테이블에 RLS; 차량 소속 사용자만 위치/기록 조회. 구성원 초대·제거·차량 번호·공유 아이콘 수정은 소유자 정책.
4. Supabase `service_role`/FCM 서버 자격증명/APNs 키는 Flutter 앱과 위젯에 포함하지 않는다.
5. 사진은 기본적으로 기기 내 OCR만 수행. 원본 업로드 OFF, 선택 업로드 시 비공개 버킷, 차량 멤버 자격 확인 후 짧은 signed URL 발급.
6. 로그/분석에 번호판, 가족 이름, 초대 원문, 촬영 사진, 액세스 토큰을 남기지 않는다.
7. 계정 탈퇴 및 가족 그룹 탈퇴 시 접근 철회, 사진·기록의 보관·삭제 정책을 앱에 명시.
8. 실시간 구독과 알림 전송에서도 차량 멤버십 및 기기별 설정을 서버에서 검증.
9. 데모/개발 데이터와 실제 가족 데이터 분리.

## 예상 비용 (2026-11-02 기준, 변동 가능)
| 구분 | 초기 비용 |
| --- | --- |
| Flutter, 기기 내 OCR, 위젯 코드 | 별도 사용료 없음 |
| Supabase Free | $0/월, 한도 내 |
| Apple Developer Program | $99/년(정식 배포 및 TestFlight) |
| Google Play Console | 최초 $25/계정, 연간 등록비 없음 |
| Supabase Pro | 필요 시 $25/월부터 + 추가 사용량 |
| Mac/Xcode 환경 | iOS 빌드·서명·검증에 필요(보유 여부에 따라 비용) |

무료 Supabase 주요 한도는 가격표 확인: DB 500MB, 파일 저장 1GB, 무료 프로젝트 비활성 시 일시정지될 수 있음. 사용량/정책은 수시 변경 가능.

## 비용 통제
- 주차 기록 텍스트 우선, 사진 서버 저장은 기본 비활성.
- 무료 사용량 대시보드 주기 점검(스토리지, egress, DB, Realtime, Edge Functions).
- 외부 유료 AI/OCR API 사용 금지(사전 동의 없이는 추가하지 않음).
- 푸시는 중복 발송 최소화, 모든 기기에 분 단위 폴링 금지.
- Supabase Free는 사용량이 적으면 프로젝트가 잠시 정지될 수 있어, 상용 수준 가용성을 보장할 수 없음.

## OS/배포 주의
- Windows: Flutter 앱 구조, Android 에뮬레이터 및 Android 빌드 가능.
- iOS: Mac+Xcode+Apple 서명 필요. Mac에서 실제 위젯/ActivityKit 테스트.
- 새 개인 Google Play 계정에는 추가 테스트·신원확인 요건이 적용될 수 있어 출시 직전 공식 콘솔 확인.

## 공식 참고
- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/free-project-pausing
- https://developer.apple.com/programs/
- https://support.google.com/googleplay/android-developer/answer/6112435
