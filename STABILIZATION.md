# 1.4.3 안정화 결과

2026-10-29 · build 8 · Apple Silicon / macOS 27.0.1

사용자 요청대로 **Claude Code 검증을 먼저** 실행했습니다. 로컬 `omx ask claude`를 사용했고, 첫 검토가 끝나기 전 제품 코드를 수정하지 않았습니다. 이후 확인된 문제에 실패하는 회귀 검사를 추가하고 최소 수정했습니다. 새 외부 라이브러리는 없습니다.

## Claude Code 지적과 처리

| 항목 | 확인과 처리 |
| --- | --- |
| 저장 직후 연속 입력의 변경 상태 누락 | 기존 코드에서 회귀 검사 실패를 재현. 수동·자동 저장 전에 `breakUndoCoalescing()`을 호출하며 두 경우 모두 통과. 실제 종료 저장 확인과 디스크 내용까지 확인 |
| 손상 설정을 기본값으로 덮어씀 | 읽기는 그대로 두고 저장 직전에 손상 원본을 호스트 `.recovery` 키에 보존. 기존 백업과 다른 원본이면 둘 다 보존하고 저장 거부. 손상 중 생성은 명확한 안내로 중단 |
| 외부에서 작업 URL 임의 호출 | Finder 확인 토큰을 검증한 뒤 기존 엄격한 URL 파서로 전달. 인증 없는 URL의 실제 거부·경고 후 종료 확인. 클립보드 저장 위치와 전송 원본 정보를 대화창에 표시 |
| 앱·문서 패키지 내부 생성 | 실제 `.app`·`.rtfd`·`.key`에서 확인. 일반 폴더만 내부로, 패키지는 부모로 대상 결정. 경로 복사 의미 유지 |
| 기존 설치 폴더 병합·실패 후 앱 손상 | 새 staging 검증 → 잠금 아래 교체 → 실패 시 원본·등록 복원. rename 직후 시그널·동시 실행·대상 충돌 시 백업 보존 검사 포함 |
| 최소화한 설정 초안 소실 | 2차 검토에서 제기, 실제 최소화 후 생성으로 재현. 설정 창이 열려 있거나 창이 최소화돼 있으면 단발 작업이 호스트를 종료하지 않도록 수정. 초안 유지 재확인 뒤 취소 |
| 오류 후 창 없는 호스트 잔존 | 오류 경고가 닫히면 유휴 종료를 다시 예약. 실제 미인증 요청 거부 후 종료 확인 |
| 빠른 URL 요청·종료 경합 | 취소 가능한 단발 0.75초 유예 추가. 최종 빌드에서 배경 요청 10개씩 3회, 총 30/30 생성과 매회 호스트 종료 확인. 초기 짧은 샘플은 macOS 전달 지연을 포함하므로 확정 요청 소실로 단정하지 않음 |
| 외장·네트워크 드라이브 | 이번 환경에서는 실기 미검증. 같은 볼륨의 배타적 이동과 다른 볼륨 원본 보존 원칙 유지. 안전하지 않은 복사 후 삭제 대안은 추가하지 않음 |
| 미리보기 일시 메모리 급증 | 진단 실행 파일로 분리 실험했으나 안전한 개선 미확정. 실험 옵션은 제품에 넣지 않았고, 설치본 최대 133.1MiB를 그대로 기록 |
| 배포 서명·다른 CPU | 유효 Developer ID 인증서 없음. 공증·Intel·다른 macOS 검증은 완료로 표시하지 않음 |

저장 시 실행 취소 그룹을 끊는 처리는 [Apple의 NSTextView 안내](https://developer.apple.com/documentation/appkit/nstextview/breakundocoalescing())와도 일치합니다.

## 변경 파일과 단순화

- `Sources/App/PlainTextDocument.swift`, `Tests/DocumentTests.swift`: 저장 경계만 보완하고 기존 NSDocument 저장·실행 취소를 재사용했습니다.
- `Sources/Core/Settings.swift`, `Sources/App/SettingsWindowController.swift`, `Tests/CoreTests.swift`: 원본 복구 백업·생성 오류 안내. Finder 메뉴와 템플릿 도메인 분리를 유지합니다.
- `Sources/Core/FinderTarget.swift`, `Tests/FinderTargetTests.swift`, `Sources/FinderExtension/FinderSync.swift`: 기존 메뉴 대상 분기를 작은 테스트 가능한 함수로 이동했습니다.
- `Sources/Core/RequestAuthorization.swift`, `Tests/RequestAuthorizationTests.swift`, `Sources/App/Main.swift`, `Sources/App/UtilityActions.swift`: 확인 토큰·대화창 문맥·유휴 종료 보완. 기존 요청 파서를 재사용하며 별도 감시 서비스를 만들지 않았습니다.
- `scripts/install.sh`, `scripts/test-install.sh`, `scripts/test.sh`: 안전한 교체와 회귀 검사. 비표준 `rg` 런타임 의존성 제거.
- 버전 plist 2개, README·CHANGELOG·VERIFICATION·PERFORMANCE: 1.4.3 동작과 검증 범위를 반영했습니다.

## 증거

- Swift 자동 검사 580개, 설치 시나리오 10개 통과.
- strict lint, 최적화 warnings-as-errors 빌드, plist·shell 구문, 설치본 strict 서명 및 빌드본과 실행 파일 일치 확인.
- 실제 Finder 생성·선택·경로 복사·저장 직후 입력·미저장 설정 최소화·미인증 요청 거부·Markdown 렌더링 확인.
- `.omx/artifacts/stabilization-after-tests.txt`, `stabilization-build.txt`, `burst-background-after.json`, `burst-final.json`, `minimized-settings-after.json`.
- 메모리 원본 `build/verification/memory-v1.4.3-*.json`, 분리 실험 `.omx/artifacts/MemoryInvestigation.md`.
- Claude 원문 검토는 `.omx/artifacts/claude-*.md`에 보관했습니다. 최종 후속 검토는 확정 P1/P2 또는 새 회귀를 찾지 못했다고 보고했습니다(코드 읽기 범위). Claude가 실행하지 못한 검사를 통과한 것처럼 합산하지 않았습니다.

## 남은 한계

첫 미리보기 순간 최대 메모리는 남아 있습니다. 현재 수치만으로 최대 사용량이 낮다고 판단하지 않습니다. 다른 Mac·Intel·macOS 13–26·외장/네트워크 볼륨·한글 IME 조합 중 자동 저장의 실기 스트레스는 미검증입니다. 실제 디스크 고장에 의한 CFPreferences 동기화 실패는 주입하지 않았습니다.

설정 백업은 하나만 영구 보관합니다. 서로 다른 손상이 반복되면 기존 백업과 새 원본을 별도로 보관·수리해야 하며 자동 삭제하지 않습니다. CFPreferences는 여러 프로세스의 원자적 비교·교환을 제공하지 않습니다. 확인 토큰은 웹의 추측 호출을 막는 장치이며 같은 macOS 사용자 권한의 악성 로컬 앱을 격리하지 않습니다.

설치 중 SIGKILL·전원 차단에는 shell 복원 트랩을 실행할 수 없습니다. 남은 `.newmemo-install.*` 백업과 `새 메모.app.install-lock`을 확인한 뒤 복구해야 합니다. 현재 앱은 개발용 ad-hoc 서명이며 Developer ID 공증 전입니다. Terminal UI 검증의 이전 도구 차단도 우회하지 않았습니다.
