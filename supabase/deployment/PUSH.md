# 가족 알림 서버

이 경로는 주차 저장과 분리된 발송 작업입니다. APNs/FCM 요청 실패가 이미 확정된 주차 기록을 취소하지 않습니다. 발송은 중복될 수 있으며, 공급자 수락과 실제 기기 표시는 서로 다른 결과입니다.

## 앱 RPC

- `get_my_device_settings(p_installation_id uuid)`는 항상 JSON을 반환합니다. 미등록 기기는 기본 OFF, `Asia/Seoul`, 120분입니다. `delivery_available`은 실제 서버 연결 준비 상태입니다.
- `save_device_settings(p_installation_id uuid, p_platform text, p_push_enabled boolean=false, p_live_enabled boolean=false, p_notify_own boolean=false, p_quiet_start time=null, p_quiet_end time=null, p_timezone text='Asia/Seoul', p_preferred_live_minutes integer=120, p_push_provider text=null, p_push_token text=null, p_push_environment text='production')`는 저장된 설정 JSON을 반환합니다. 토큰은 반환하지 않습니다.
- iOS는 `apns`, Android는 `fcm`; Android 환경은 `production`입니다. iOS 환경은 서명 entitlement와 맞춰야 하며 TestFlight는 production입니다.
- 처음 켤 때 플랫폼이 발급한 토큰이 필요합니다. 이후 토큰이 null이면 기존 등록을 유지합니다. 같은 토큰을 다른 계정이 중복 등록할 수 없으며, 토큰 값 변경 시 내부 revision을 교체합니다.
- 서비스가 일시 중단돼 `delivery_available=false`가 되면 새 활성화와 토큰·공급자 등록은 차단합니다. 이미 켜진 기기는 `p_push_token`·`p_push_provider`를 보내지 않고 기존 허용을 유지하면서 차량 찾기·야간 설정을 변경할 수 있습니다. 알림 끄기는 항상 가능합니다.
- `unregister_push_device(p_installation_id uuid)`는 현재 사용자의 토큰을 제거하고 대기·처리 중 작업을 취소합니다. 다른 기기·사용자 및 독립 Live 표시 설정을 변경하지 않습니다. 앱은 Auth 로그아웃 전에 호출하고, 네이티브 알림 등록도 해제합니다.
- 오프라인에서는 서버 등록 철회를 보장할 수 없습니다. 이미 공급자가 받은 알림의 회수도 보장하지 않습니다. 잠금 화면 알림에는 위치·번호판·이름·초대 코드가 없습니다.
- 야간 시간은 검증된 IANA 시간대의 현지 시각으로 계산합니다. 시작 포함, 종료 제외이며 자정을 넘는 구간을 지원합니다. 같은 시작·종료는 거절합니다. 야간에 발생한 기록은 나중에 몰아서 보내지 않습니다.

## 보안·발송 정책

`private.push_devices`와 `private.push_outbox`에는 RLS를 켜고 일반 앱 계정 권한을 부여하지 않습니다. 토큰은 공개 테이블/설정 JSON에 없으며 서버 DB 접근 권한을 가진 운영자만 관리합니다. 앱은 토큰을 서버로 등록할 때만 전송합니다.

주차 insert 트랜잭션의 trigger는 서버 준비 상태, 현재 가족, 명시적 허용, 본인 기록 설정, 야간 정책으로 대상을 정하고 작업만 추가합니다. HTTP 요청은 하지 않습니다. 작업은 기록·기기당 하나입니다. worker는 2분 lease로 최대 10개를 가져오며, 발송 직전에 현재 멤버십·계정·허용·토큰 revision·야간 정책·최신 기록 여부를 다시 검사합니다.

최대 6회, 최대 1시간 동안만 재시도합니다. 30초 이상의 지수 지연과 공급자의 Retry-After(최대 1시간)를 적용합니다. 중단된 lease는 재할당되며 이전 lease의 완료 응답은 거부합니다. 7일 이전 작업은 다음 worker 실행에서 정리합니다. APNs collapse ID와 FCM collapse key로 같은 차량의 중복 표시를 줄이지만 정확히 한 번 전달을 보장하지 않습니다.

FCM은 **data-only** 메시지입니다. 네이티브 서비스가 `kind=parking_updated` 및 로컬 알림 허용을 확인한 뒤 고정 문구를 표시해야 합니다. SDK 자동 표시가 로컬 해제를 우회하지 않도록 `notification` payload를 사용하지 않습니다. APNs는 고정된 일반 문구의 alert이며 잘못된 token 응답은 해당 revision의 토큰만 제거합니다.

worker는 `x-carcar-worker-secret`을 SHA-256 고정 길이 비교로 검증한 뒤에만 DB에 접근합니다. 공개 키·사용자 JWT만으로 호출할 수 없습니다. Edge의 `verify_jwt=false`는 이 전용 인증을 사용하기 위한 설정이며 인증 생략이 아닙니다. 응답은 집계 수치만 반환하며 원본 공급자 오류·토큰·개인키는 로그에 쓰지 않습니다.

## 배포 연결 순서

1. 최신 migration을 적용합니다. `private.push_configuration.delivery_available`은 기본 false입니다.
2. Edge secret에 `CARCAR_PUSH_WORKER_SECRET`(암호학적 랜덤 32자 이상), `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC=com.kang88.carcar`, `FCM_SERVICE_ACCOUNT_JSON`을 안전하게 설정합니다. Supabase의 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`는 worker에서만 사용합니다. 키를 앱·Git·명령 출력에 넣지 않습니다.
3. `parking-push` Edge Function을 배포합니다. Entry는 `supabase/functions/parking-push/index.ts`, 의존 코드는 같은 폴더의 `core.mjs`이며 외부 패키지가 없습니다.
4. 인증 없는 요청이 401이고, 올바른 전용 secret의 빈 큐 요청이 집계 JSON으로 응답하는지 확인합니다. 실제 APNs HTTP/2 및 FCM 서비스 계정 권한은 공급자 smoke test로 추가 확인합니다.
5. Vault에 `carcar_project_url`, `carcar_push_worker_secret`을 안전하게 저장합니다. `supabase/deployment/schedule_parking_push.sql`을 적용합니다. 이름이 같은 cron job만 갱신하며, due 작업이 있을 때만 Edge를 호출합니다. 사용자 기기별 polling은 없습니다. `pg_net` 요청 대기 헤더에도 secret이 잠시 저장될 수 있으므로 DB 관리 접근을 제한합니다.
6. 필요한 플랫폼의 자격·scheduler·기기 등록 경로 검증 후에만 서비스 역할로 `set_push_delivery_available(true)`를 호출합니다. 일반 앱 사용자는 이 값을 바꿀 수 없습니다. 실제 기기에서 A 저장 → B 백그라운드 수신을 확인합니다.

알림 발송 자체는 FCM Spark/APNs 및 Supabase Free 한도 안에서 구성합니다. Firebase Cloud Functions·Blaze·유료 서버를 활성화하지 않습니다. Free 일시정지와 사용 한도는 별도로 점검해야 합니다.

## 로컬 검증

```bash
PG_BIN=/tmp/carcar-pg-root/usr/lib/postgresql/16/bin \
LD_LIBRARY_PATH=/tmp/carcar-pg-root/usr/lib/x86_64-linux-gnu \
bash scripts/push_backend_test.sh
node --test supabase/tests/push_worker.test.mjs
npx deno check supabase/functions/parking-push/index.ts
npx deno lint supabase/functions/parking-push
```

SQL 검사는 별도 임시 PostgreSQL만 사용하고 종료 시 삭제합니다. worker 테스트의 APNs/FCM transport는 모의 HTTP 응답이며, 실제 공급자 수락 또는 기기 수신의 증거가 아닙니다.

공식 참고: [Supabase 예약 함수](https://supabase.com/docs/guides/functions/schedule-functions), [함수 인증](https://supabase.com/docs/guides/functions/auth), [APNs 요청](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns), [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api).
