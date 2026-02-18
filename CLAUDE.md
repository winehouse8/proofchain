# proofchain — HITL 개발 프로세스

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
3. **TC 격리**: `/test-gen-design`은 절대 `src/`를 읽지 않는다. (운영 요건 — Claude Code API가 Read 차단을 지원하지 않아 프로그래밍적 강제 불가. ISO 26262 Part 8 §9.4.3 "충분한 독립성"은 스킬 지시 + 인간 리뷰로 충족.)
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
| `/ears-spec` | SPEC 작성 co-pilot (EARS 패턴) | 메인 |
| `/test-gen-design` | Baseline TC 생성 (src/ 격리) | fork |
| `/test-gen-code` | 테스트 코드 생성 + 실행 + fix loop | 메인 |
| `/traceability` | 추적성 매트릭스 생성 (REQ↔TC↔Test) | 메인 |
| `/frontend-design` | 프론트엔드 UI 디자인 | 메인 |
| `/reset` | 프로세스 상태/산출물 초기화 | 메인 |

cycle > 1일 때 스킬이 자동으로 amendment 모드로 동작한다.

---

## 훅 — 3-Layer + Auto 강제 시스템

```
Layer 3 [Gate]   ← check-phase.sh verified_gate()
                    verified 전환 시 전수 검사: @tc/@req 매핑 + supplementary TC 스키마
                    → 미충족 시 차단 (exit 2)

Layer 2 [Guide]  ← trace-change.sh (PostToolUse)
                    change-log.jsonl 기록 + @tc/@req 누락 경고 + 팬텀 TC 참조 경고
                    → 차단 없음, 안내만

Layer 1 [Guard]  ← check-phase.sh (PreToolUse)
                    phase별 파일 접근 차단 + auto_backward + .claude/ 쓰기 보호
                    → 위반 시 차단 또는 자동 상태 전환

        [Auto]   ← artifact-commit.sh: SPEC/TC 수정 → 개별 git commit
                 ← phase-commit.sh: phase 전환 → git commit + verified tag
```

| 훅 | 유형 | 역할 |
|----|------|------|
| `check-phase.sh` | PreToolUse | Layer 1 Guard + Layer 3 Gate: phase별 파일 접근 차단, auto_backward (test→code), verified gate 전수 검사, `.claude/` 쓰기 보호 |
| `trace-change.sh` | PostToolUse | Layer 2 Guide: src/tests/ 변경 → change-log.jsonl 기록, @tc/@req 누락 경고, 팬텀 TC 참조 경고 |
| `artifact-commit.sh` | PostToolUse | Auto: SPEC-*.md/TC-*.json 수정 시 개별 git commit (ISO 26262 §7.4.5 형상 이력) |
| `phase-commit.sh` | PostToolUse | Auto: phase 전환 감지 → git commit + verified 시 git tag, 전환 유효성 경고 |
| `restore-state.sh` | SessionStart | 세션 시작 시 HITL 현황 보고 + main 브랜치 경고 |
| `checkpoint.sh` | PreCompact | 컨텍스트 압축 전 현재 area/phase/cycle 상태 보존 |

### 자동 git 커밋 전략

| 형상 항목 | 커밋 시점 | 커밋 hook | 메시지 형식 |
|-----------|----------|----------|------------|
| SPEC-*.md | 매 수정마다 | artifact-commit.sh | `[artifact] CP(name): SPEC-CP-*.md [spec, cycle 1]` |
| TC-*.json | 매 수정마다 | artifact-commit.sh | `[artifact] CP(name): TC-CP.json [tc, cycle 1]` |
| src/, tests/ | phase 전환 시 | phase-commit.sh | `[proofchain] CP(name): code → test (cycle 1)` |
| verified milestone | verified 전환 시 | phase-commit.sh | git tag `CP-verified-c1` |

---

## 브랜치 전략

| 브랜치 | 용도 | 내용 |
|--------|------|------|
| `main` | 프레임워크 템플릿 | HITL 엔진만 (hooks, skills, CLAUDE.md, HITL.md) — 프로젝트 코드 없음 |
| `project/<name>` | 개별 프로젝트 | main에서 분기, SPEC + TC + src + tests 포함 |

**규칙:**
1. **main에서 직접 개발 금지** — `hitl-state.json`의 `project.code`가 비어있으면 프로젝트 미설정 상태. 반드시 `project/<name>` 브랜치를 만들고 시작한다.
2. **새 프로젝트 시작 시**: `git checkout -b project/<name>` → 프로젝트 설정 → `/ears-spec`
3. **프레임워크 업데이트**: main에서 수정 후 각 project 브랜치에 merge

세션 시작 시 main 브랜치에 있으면 경고가 표시된다.

---

## 핵심 파일

```
.claude/
├── hooks/
│   ├── check-phase.sh          Layer 1 Guard + Layer 3 Gate
│   ├── trace-change.sh         Layer 2 Guide
│   ├── artifact-commit.sh      SPEC/TC 개별 커밋
│   ├── phase-commit.sh         전환 커밋 + tag
│   ├── restore-state.sh        세션 시작 보고
│   └── checkpoint.sh           압축 전 상태 보존
├── skills/
│   ├── ears-spec/              SPEC 작성 co-pilot
│   ├── test-gen-design/        Baseline TC 생성 (격리)
│   ├── test-gen-code/          테스트 코드 생성 + 실행
│   ├── traceability/           추적성 매트릭스
│   ├── frontend-design/        프론트엔드 UI 디자인
│   └── reset/                  프로세스 초기화
└── settings.json               Hook 등록

.omc/
├── HITL.md                     HITL 프로세스 정의 (상세 참조)
├── hitl-state.json             상태 추적 (모든 스킬이 읽고 씀)
├── change-log.jsonl            파일 변경 감사 로그
├── specs/SPEC-*.md             요구사항 명세
├── test-cases/TC-*.json        테스트 케이스 명세
└── traceability/               추적성 매트릭스

src/                            소스 코드
tests/{unit,component,e2e,visual}/  테스트 코드
docs/                           평가 보고서
```
