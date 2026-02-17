# HITL 개발 프로세스

이 프로젝트는 **Human-in-the-Loop (HITL) 개발 루프**를 따른다.
SPEC이 단일 진실 원천이며, 코드와 테스트는 SPEC으로부터 독립적으로 파생된다.
상세 프로세스 정의: `.omc/HITL.md`

---

## 세션 시작 시 반드시 할 것

**`.omc/hitl-state.json`을 읽고, 현재 상태를 사람에게 요약 보고하라.**

```
=== HITL 현황 ===
CP (컴포넌트)  : verified [cycle 1] → 완료. 변경 시 reentry 필요.
CV (캔버스)    : code [cycle 1]     → 다음: 코딩 계속
WR (와이어링)  : test [cycle 2]     → 다음: 테스트 반복 (회귀 포함)
```

이 보고를 먼저 하고, 사람이 어떤 영역/단계를 진행할지 선택하도록 안내한다.

---

## 5-Phase 상태 머신

```
spec ──→ tc ──→ code ──→ test ──→ verified
  ↑       ↑      ↑        ↑          │
  │       │      │        │          │ reentry (cycle++)
  │       └──────┴────────┘          │
  │              backward            │
  └──────────────────────────────────┘
```

| 전환 | 조건 | cycle 변화 |
|------|------|-----------|
| **Forward** | 현재 단계 완료 + 사람 승인 | 유지 |
| **Backward** | 사람이 문제 발견 (같은 cycle 내) | 유지 |
| **Reentry** | `verified`에서 재진입 | cycle++ |

---

## Phase 안내

| Phase | 사람에게 안내할 내용 |
|-------|---------------------|
| `spec` | "SPEC을 작성합니다. `/ears-spec`을 사용하세요." |
| `tc` | "Baseline TC를 생성합니다. `/test-gen-design`을 실행하세요." |
| `code` | "코딩을 계속합니다. 완료되면 `/test-gen-code`로 테스트를 시작합니다." |
| `test` | "테스트 실행 중입니다. 전부 통과하면 최종 검증으로 넘어갑니다." |
| `verified` | "이 영역은 완료되었습니다. 변경이 필요하면 reentry를 시작하세요." |

---

## Reentry 시나리오

`verified` 후 변경이 필요할 때:

| 시나리오 | 진입 phase | 건너뛴 phase | 사용 스킬 |
|---------|-----------|-------------|----------|
| **A. SPEC 변경 필요** (새 기능, SPEC 오류) | `spec` | 없음 | `/ears-spec` → `/test-gen-design` → `/test-gen-code` |
| **B. 코드 버그** (SPEC 정확) | `tc` | `spec` | `/test-gen-design` → `/test-gen-code` |
| **C. 테스트 코드 오류** | `code` | `spec`, `tc` | `/test-gen-code` |

Reentry 시 log 필수 필드: `type`, `reason`, `affected_reqs`. 건너뛰기 시 `skipped_phases`, `skip_reason` 추가.

---

## 불변 규칙

1. **Baseline TC 불변**: `origin: "baseline"`의 given/when/then은 최초 `verified` 이후 절대 수정/삭제 금지. SPEC 변경 시 `status: "obsolete"` 마킹 + 대체 supplementary TC 생성.
2. **Cycle 1 backward 시 baseline TC 재생성 허용**: 아직 verified 전이므로 통째로 재생성 가능.
3. **TC 격리**: `/test-gen-design`은 절대 `src/`를 읽지 않는다.
4. **추적성**: 모든 TC는 REQ ID에 연결.
5. **5회 실패 에스컬레이션**: 같은 TC 5회 실패 시 사람에게 보고.
6. **verified 잠금**: `verified` 상태에서는 src/, .omc/specs/, .omc/test-cases/, tests/ 수정 불가. reentry 필수.
7. **skip_reason 필수**: 단계 건너뛰기 시 정당화 기록 (ISO 26262 Part 8 §8.7).
8. **전체 회귀**: cycle > 1에서 전체 회귀 테스트 필수 (ISO 26262 Part 6 §9.4.6).

---

## Phase 전환 시 반드시

1. `hitl-state.json`의 해당 영역 `phase` 값 변경
2. 관련 하위 상태 갱신 (`spec.status`, `tc.status` 등)
3. Reentry 시: `cycle++`, `cycle_entry`, `cycle_reason` 갱신
4. `log` 배열에 기록 추가

---

## 스킬

| 스킬 | 용도 | 컨텍스트 |
|------|------|----------|
| `/ears-spec` | SPEC 작성 co-pilot | 메인 |
| `/test-gen-design` | Baseline TC 생성 (격리) | fork |
| `/test-gen-code` | 테스트 코드 생성+실행+반복 | 메인 |
| `/traceability` | 추적성 매트릭스 생성 | 메인 |
| `/reset` | 프로세스 상태/산출물 초기화 | 메인 |

cycle > 1일 때 스킬이 자동으로 amendment 모드로 동작한다.

## 훅

| 훅 | 유형 | 역할 |
|----|------|------|
| `check-phase.sh` | PreToolUse | Phase 기반 파일 접근 차단 + 다중 영역 공유 파일 검사 + `.claude/` 자기 보호 |
| `restore-state.sh` | SessionStart | 세션 시작 시 HITL 현황 복원 |
| `checkpoint.sh` | PreCompact | 컨텍스트 압축 전 작업 상태 보존 |

## 핵심 파일

```
.omc/
├── HITL.md                        HITL 프로세스 정의 (상세 참조)
├── hitl-state.json                상태 추적 (모든 스킬이 읽고 씀)
├── specs/SPEC-*.md                요구사항 명세
├── test-cases/TC-*.json           테스트 케이스 명세
└── traceability/                  추적성 매트릭스
src/                               소스 코드
tests/{unit,component,e2e,visual}/ 테스트 코드
```
