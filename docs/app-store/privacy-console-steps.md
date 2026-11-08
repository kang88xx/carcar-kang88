# 앱 개인정보 입력 안내 · 2026-11-08

[App Store Connect에서 차자리 열기](https://appstoreconnect.apple.com/apps/6829616379)

브라우저 자동화 연결을 사용할 수 없어 직접 입력할 때 참고하는 안내입니다. TestFlight 1.0.0 (13)의 [개인정보 권장 답변](privacy-answers.md)을 요약했습니다. 이 문서는 입력·게시 완료 기록이 아닙니다. 화면 명칭은 Apple 공식 안내 기준이며 실제 언어·화면에 따라 다를 수 있습니다.

## 입력 순서

1. 앱 개인정보(App Privacy)에서 시작하기(Get Started)를 엽니다. 기존 답변이 있으면 데이터 유형 편집(Edit)을 엽니다.
2. 데이터 수집 여부는 **예(Yes, we collect data from this app)**를 선택합니다.
3. 아래 **12개 유형**을 선택하고 저장(Save)합니다.

| 분류 | 선택할 유형 | 차자리의 해당 정보 |
| --- | --- | --- |
| 연락처 정보(Contact Info) | 이름(Name) | 표시 이름·로그인 이름 |
| 연락처 정보(Contact Info) | 이메일 주소(Email Address) | 로그인·문의 이메일 |
| 위치(Location) | 정확한 위치(Precise Location) | 직접 입력한 아파트와 상세 주차 자리 |
| 위치(Location) | 대략적인 위치(Coarse Location) | 서버 요청 IP에서 유래한 도시·국가·지역 |
| 사용자 콘텐츠(User Content) | 고객 지원(Customer Support) | 이메일 문의 내용·첨부 자료 |
| 사용자 콘텐츠(User Content) | 기타 사용자 콘텐츠(Other User Content) | 차량 별명·번호, 주차 기록·메모 |
| 식별자(Identifiers) | 사용자 ID(User ID) | 로그인 사용자·구성원·작성자 식별자 |
| 식별자(Identifiers) | 기기 ID(Device ID) | 앱 설치 식별자·알림 토큰 |
| 사용 데이터(Usage Data) | 제품 상호 작용(Product Interaction) | 인증·서버 요청 활동 |
| 진단(Diagnostics) | 성능 데이터(Performance Data) | 서버 실행 시간 |
| 진단(Diagnostics) | 기타 진단 데이터(Other Diagnostic Data) | 요청 상태·오류·앱 환경 정보 |
| 기타 데이터(Other Data) | 기타 데이터 유형(Other Data Types) | 보안·운영 IP, 알림 설정·시간대 |

4. 각 유형을 하나씩 열고 **12개 모두 동일하게** 답합니다.

| 질문 | 선택 |
| --- | --- |
| 사용 목적 | **앱 기능(App Functionality)** |
| 사용자 신원에 연결되는가 | **예(Linked to User)** |
| 추적에 사용하는가 | **아니요(Not Used for Tracking)** |

5. 각 유형의 답변을 저장(Save)하고 미완료 항목이 없는지 확인합니다. 미리보기에서 사용자에게 연결된 데이터에 선택 항목이 나타나고, 추적에 사용하는 데이터로 표시되지 않는지 확인합니다.
6. 전체 답변을 검토한 뒤 게시(Publish)를 누르고 확인창 내용을 확인해 게시합니다. **저장만으로는 게시가 완료되지 않습니다.** 앱 제품 페이지가 아직 공개되지 않았다면 개인정보 답변도 제품 페이지가 공개될 때 표시됩니다. [Apple 공식 입력·게시 안내](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

## 헷갈리기 쉬운 항목

- **정확한 위치는 GPS 수집을 뜻하지 않습니다.** 차자리는 GPS를 읽지 않습니다. 사용자가 입력한 아파트와 층·구역·자리의 조합이 실제 위치를 식별할 수 있어 포함하는 보수적 권장 분류입니다.
- **OCR 사진·영상은 수집 유형으로 추가하지 않습니다.** 현재 앱은 기기에서 사진을 읽고 확인한 텍스트만 서버에 저장합니다. 원본 사진·영상은 업로드하지 않습니다.
- 서버 로그 관련 유형은 Supabase 공식 처리 범위를 반영한 권장안입니다. 실제 프로젝트 로그·보관 설정의 상세 확인 범위는 [근거 문서](privacy-answers.md)에 기록했습니다.
