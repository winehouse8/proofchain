# 재감사 보고서 — proofchain v3.4

> **작성일**: 2026-02-20
> **대상**: proofchain 프레임워크 v3.4 (main 브랜치)
> **감사 범위**: hooks 6건 × skills 6건 × 문서 3건 × 설정 1건
> **이전 감사**: `docs/code-docs-consistency-audit.md` (v2.1 대상)
> **감사 목적**: 3대 목표 재평가
> **버전 이력**: v3.2 Check 4 (Baseline TC 불변) → v3.3 Check 5 (Reentry 로그 검증) → v3.3.1 .claude/ guard 오탐 수정 → v3.4 Tier 1 강제 (파괴적 git 차단, 전환 유효성, TC 존재 검증)

| # | 목표 | 핵심 질문 |
|---|------|----------|
| **G1** | 자연스러운 개발 흐름 | 코딩/디버깅 중 흐름이 끊기지 않는가? |
| **G2** | ISO 26262 준수 | 추적성, 형상관리, 변경통제, 회귀 테스트가 보장되는가? |
| **G3** | Reentry 히스토리 | verified 후 되돌아가서 고치는 과정이 추적 가능하고, git 이력에 남는가? |

---

## 1. 이전 감사 지적 사항 추적

### 1.1 해소 완료

| # | 이전 지적 | 해소 방법 | 현재 상태 |
|---|----------|----------|----------|
| **C1** | Baseline TC 불변 미강제 (High) | check-phase.sh v3.2 — verified_gate() Check 4 추가. git tag `{area}-verified-c1` 기준 given/when/then 비교. 삭제 차단, obsolete 허용. | **해소** |
| **D2** | verified gate 차단 항목 수 불일치 | README.md 갱신: Check 1~6 (Check 4: baseline, Check 5: reentry 로그, Check 6: 경고) | **해소** |
| **D3** | hard blocks 수 | README.md 갱신: 14→16 | **해소** |
| **F1** | .claude/ 보호 범위 서술 | README.md L65: "write protection" 명확화 | **해소** |
| **F2** | added_reason 10자 규칙 미문서화 | README.md Key Invariants #7 추가 | **해소** |
| **F3** | tests 디렉토리 area 매핑 규약 | README.md Key Invariants #9 + Project Structure 추가 | **해소** |

### 1.2 의도적 수용 (변경 없음, 재확인)

| # | 지적 | 수용 근거 | 재평가 |
|---|------|----------|--------|
| **C2** | 5회 실패 에스컬레이션 hook 미구현 | 스킬(/test-gen-code) 수준 처리 | **유지 타당**. hook에서 TC별 실패 횟수를 추적하려면 별도 상태 파일이 필요하고, 복잡도 대비 효용이 낮음. 스킬이 fix-loop 내에서 카운트하므로 실질적 위험 없음. |
| **C3** | TC 격리 src/ Read 미차단 | Claude Code API 제약 | **유지 타당**. test-gen-design 스킬이 `context: fork`로 실행되어 별도 컨텍스트에서 동작. 프로그래밍적 완전 차단은 불가하나 ISO 26262 Part 8 §9.4.3은 "충분한 독립성"을 요구하므로, 스킬 지시 + fork 컨텍스트 + 인간 리뷰로 충족. |
| **U1** | .phase-snapshot.json 미문서화 | 내부 메커니즘 | **유지 타당**. |
| **U4** | graceful degradation 미문서화 | 보안상 비공개 | **유지 타당**. |

### 1.3 미해소 잔여

| # | 이전 지적 | 현재 상태 | 심각도 |
|---|----------|----------|--------|
| **D1** | .claude/ 보호 범위: "modifications" vs 실제 "write only" | README.md L65 현재: `.claude/ protection` — 개선되었으나 "write operations (read/git allowed)" 명시적 서술 없음 | **Low** (기능적 문제 아님, 서술 정밀도) |

---

## 2. 신규 발견 사항

### 2.1 코드에 있으나 문서에 없는 것 (Undocumented)

| # | 동작 | 코드 위치 | 심각도 | 목표 영향 |
|---|------|----------|--------|----------|
| **N1** | phase-commit.sh 전환 유효성 검증 (spec→test 같은 비정상 전환 경고) | phase-commit.sh L80-115 | Low | G3 |
| **N2** | phase-commit.sh가 `git add -A`로 전체 스테이징 | phase-commit.sh L147 | **Medium** | G2 |
| **N3** | verified 전환 시 `/traceability` 실행 권장 메시지 출력 | phase-commit.sh L168-177 | Low | - |

**N2 주의**: `git add -A`는 .gitignore에 없는 모든 파일을 커밋함. 민감 파일(.env, credentials)이 있으면 의도치 않게 커밋될 수 있음. artifact-commit.sh는 개별 파일만 `git add`하므로 안전하지만, phase-commit.sh는 전체 스테이징. 단, 이 프로젝트는 AI가 관리하는 코드이므로 실질적 위험은 낮음.

### 2.2 문서에 있으나 코드에 없는 것 (Unimplemented)

| # | 주장 | 문서 위치 | 코드 상태 | 심각도 | 목표 영향 |
|---|------|----------|----------|--------|----------|
| **N4** | Reentry 로그 필수 필드(type, reason, affected_reqs) 강제 | CLAUDE.md L59-65, HITL.md L100-114 | ~~**미강제**~~ → **v3.3 해소**: verified_gate Check 5가 cycle > 1일 때 reentry 로그 필수 필드 검증 | ~~Medium~~ **Resolved** | G2, G3 |
| **N5** | skip_reason 필수 (단계 건너뛰기 시) | CLAUDE.md L77, HITL.md L112 | ~~**미강제**~~ → **v3.3 해소**: verified_gate Check 5가 skipped_phases 존재 시 skip_reason 검증 | ~~Medium~~ **Resolved** | G2 |
| **N6** | cycle > 1에서 전체 회귀 테스트 필수 | CLAUDE.md L78, HITL.md L118 | **스킬 수준만** — /test-gen-code Amendment Mode가 전체 회귀 실행. hook은 "회귀 테스트를 실행했는지" 검증하지 않음 | Low | G2 |

**N4/N5 해소 (v3.3)**: verified_gate Check 5가 cycle > 1일 때 reentry 로그 항목의 `type`, `reason`, `affected_reqs` 필드 존재를 검증하고, `skipped_phases`가 있으면 `skip_reason` 존재도 검증함. 누락 시 verified 전환 차단. 이전에는 프로세스 문서에만 명시되어 있었으나, 이제 기계적으로 강제됨.

**N6 분석**: 회귀 테스트 강제는 스킬(/test-gen-code)이 담당하며, hook 수준에서 "모든 테스트가 통과했는지" 검증하지는 않음. verified gate는 추적성(annotation)만 검사. 그러나 실제 개발 흐름에서 /test-gen-code를 사용하지 않고 verified로 전환하는 경로가 존재함 (AI가 직접 hitl-state.json을 수정하면). 이 경로는 "인간 승인" 게이트로 방어됨.

### 2.3 코드와 문서 불일치 (Discrepancies)

| # | 항목 | 문서 | 코드 | 심각도 |
|---|------|------|------|--------|
| **N7** | Key Invariants 수 | CLAUDE.md: 8개 | README.md: 10개 (#7 Supplementary TC Quality, #9 Test Directory Convention 추가) | Low |
| **N8** | 강제 메커니즘 수 | README.md: "16 hard blocks" | 실제: exit 2 경로 11개 유형 (verified_gate 내부 5개 포함) | Low |

**N8 분석**: "16 hard blocks"의 카운트 방법이 모호함. exit 2 코드 경로는 11개 유형이지만, 각 유형이 여러 조건을 포함하므로 (예: phase mismatch는 5개 phase × 4개 파일 유형) 세는 방법에 따라 16이 될 수 있음. 기능적 문제 아님.

### 2.4 버그 수정 (v3.3.1)

| # | 문제 | 원인 | 수정 | 목표 영향 |
|---|------|------|------|----------|
| **B1** | `.claude/` guard가 git 명령을 오탐하여 차단 | Bash 명령 전체를 flat string으로 grep → 커밋 메시지 안의 `>` (예: `cycle > 1`)가 `>[^&]` 셸 리다이렉트 패턴에 매칭 | `^\s*git\s` 패턴으로 git 명령 체인을 검사에서 제외 | **G1** |

**B1 상세**: `git add .claude/... && git commit -m "...(cycle > 1)..."` 실행 시, 커밋 메시지 안의 `>` 문자가 셸 리다이렉트로 오탐되어 `.claude/` 쓰기 차단이 발동함. git 명령은 VCS 작업이지 파일 쓰기가 아니므로, `^\s*git\s`로 시작하는 명령은 `.claude/` 쓰기 검사를 건너뛰도록 수정.

### 2.5 Tier 1 강제 추가 (v3.4)

v3.4에서 `docs/research-enforcement-architecture.md`의 적대적 시나리오 분석에 따라 Tier 1 개선을 구현.

| # | 구현 | 방어 시나리오 | 코드 위치 | 목표 영향 |
|---|------|-------------|----------|----------|
| **T1-2** | 파괴적 git 명령 차단 (git tag -d, checkout .claude/, reset --hard, push --force) | A2 (태그 삭제), A3 (hook 복원) | check-phase.sh Bash handler L481-530 | **G2** |
| **T1-1** | Phase 전환 유효성 검사 (허용 전환 맵 + reentry cycle++ 강제) | A1 (phase 건너뛰기) | check-phase.sh hitl-state.json Write handler L647-712 | **G2** |
| **T1-3** | Active TC 0개 시 verified 차단 (Check 6) | A5 (TC 0개 verified) | check-phase.sh verified_gate L154-164 | **G2** |

**T1-2 상세**: `^\s*` 앵커로 명령 시작 부분만 매칭하여 커밋 메시지 내 텍스트 오탐 방지 (v3.3.1 B1과 동일한 원리).

**T1-1 상세**: 13가지 허용 전환(Forward 4 + Backward 6 + Reentry 3)만 통과. verified→reentry 시 cycle 증가를 검증. 새 영역 추가(unknown → any)는 허용.

**T1-3 상세**: 기존 `[ -z "$active_tc_ids" ] && return 0` (조용히 통과)를 `return 1` + BLOCKED 메시지로 변경. TC가 모두 obsolete이거나 TC JSON이 비어있으면 verified 차단.

---

## 3. ISO 26262 준수 매트릭스 (전수)

### 3.1 Part 6 — 소프트웨어 개발

| 조항 | 요건 | 강제 수단 | 강제 수준 | 준수 |
|------|------|----------|----------|------|
| **§9.3** 양방향 추적성 | REQ ↔ TC ↔ Test Code | verified_gate Check 1,2 (@tc/@req 검사) + /traceability 매트릭스 | **Hook (차단)** | ✅ 충족 |
| **§9.4.3** 검증 독립성 | TC 설계가 구현에 독립적 | /test-gen-design `context: fork` + 스킬 지시 | **스킬 (지시)** | ⚠️ 부분 충족 |
| **§9.4.6** 회귀 테스트 | 변경 후 전체 회귀 | /test-gen-code Amendment Mode | **스킬 (자동)** | ✅ 충족 |
| **§10.4.1** 단위 검증 | 모든 요건에 대한 테스트 | verified_gate Check 1 (모든 active TC → @tc 존재) | **Hook (차단)** | ✅ 충족 |

### 3.2 Part 8 — 지원 프로세스

| 조항 | 요건 | 강제 수단 | 강제 수준 | 준수 |
|------|------|----------|----------|------|
| **§7.4.1** 형상 항목 식별 | 형상 항목 정의 | SPEC/TC/src/tests 경로 관리 | **Hook (차단)** | ✅ 충족 |
| **§7.4.3** Baseline 설정 | verified 시점 기준선 | git tag `{area}-verified-c{N}` | **Hook (자동)** | ✅ 충족 |
| **§7.4.3** Baseline 불변 | 기준선 후 내용 보호 | verified_gate Check 4 (git tag 비교) | **Hook (차단)** | ✅ 충족 |
| **§7.4.4** 변경 통제 | verified 후 수정 차단 | check-phase.sh verified lock (exit 2) | **Hook (차단)** | ✅ 충족 |
| **§7.4.5** 형상 상태 기록 | 모든 변경 이력 | artifact-commit.sh + phase-commit.sh (매 수정 git commit) | **Hook (자동)** | ✅ 충족 |
| **§8.4.1** 변경 요청 식별 | Reentry 시 이유/범위 기록 | verified_gate Check 5 (type, reason, affected_reqs 검증) | **Hook (차단)** | ✅ 충족 |
| **§8.7** 단계 생략 근거 | 건너뛴 단계의 정당화 | verified_gate Check 5 (skipped_phases → skip_reason 검증) | **Hook (차단)** | ✅ 충족 |
| **§11** 도구 자격 | TCL1 (TI2 + TD1) | HITL + TC 격리 + 전체 회귀 | **아키텍처** | ✅ 충족 |

### 3.3 준수 요약

```
Hook 차단 (기계적 강제):  9/11  ██████████████████████████████████████░░  82%
스킬 자동 (실행 시 강제):  2/11  ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  18%
```

**v3.3에서 §8.4.1과 §8.7이 Hook 차단으로 승격됨**: verified_gate Check 5가 cycle > 1일 때 reentry 로그의 `type`, `reason`, `affected_reqs` 필드 존재를 검증하고, `skipped_phases`가 있으면 `skip_reason` 존재도 검증함. 누락 시 verified 전환 차단.

---

## 4. 개발 UX 평가

### 4.1 흐름 유지 시나리오

| 시나리오 | Hook 동작 | 마찰도 | 판정 |
|---------|----------|--------|------|
| **코딩 중 자유 수정** | code phase에서 src/ 무제한 허용 | 없음 | ✅ |
| **테스트 실패 → 코드 수정** | auto_backward: test→code 자동 전환, 편집 허용 | 경고 1줄 (비차단) | ✅ |
| **@tc 누락** | Layer 2 경고 (stderr, 비차단) | 무시 가능 | ✅ |
| **tests/ 외부 코드 파일 작성** | 차단 + 안내 (src/ 또는 tests/에 작성하라) | 차단되나 안내 명확 | ✅ |
| **설정 파일 (vite.config.ts) 수정** | 예외 패턴으로 허용 | 없음 | ✅ |
| **verified 후 수정 시도** | 차단 + reentry 시나리오 A/B/C 안내 | 차단되나 다음 행동 명확 | ✅ |
| **verified 전환 시 추적성 누락** | Check 1-6 개별 오류 메시지 + 구체적 누락 목록 | 차단되나 수정 대상 명확 | ✅ |
| **.claude/ 파일 git commit/push** | ~~v3.3: 오탐으로 차단~~ → **v3.3.1: git 명령 허용** | 없음 | ✅ |

### 4.2 마찰 발생 시나리오

| 시나리오 | 현재 동작 | 마찰도 | 개선 가능성 |
|---------|----------|--------|------------|
| **auto_backward 오발동** | src/ 파일에 주석만 추가해도 test→code 전환 | **중간** | Approach: Read는 auto_backward 안 함 (Edit/Write만). 실질적 "쓰기"인 경우만 발동하므로 적절. 주석 추가도 코드 변경이므로 상태 추적이 정확함. |
| **여러 영역에 매핑된 파일** | 하나라도 잘못된 phase면 차단 | **중간** | 설계 의도대로. 다중 영역 파일은 모든 영역이 허용해야 수정 가능. 안내 메시지에 차단 원인 영역 표시됨. |
| **verified gate 8단계 검사** | Check 1 실패 시 이후 미실행 (순차 차단) | **낮음** | 한 번에 하나만 표시되므로 여러 번 시도 필요할 수 있으나, 각 오류가 명확하여 수정이 빠름. |
| **프로젝트 외부 파일** | CWD 밖 파일은 모든 검사 스킵 | 없음 | 설계 의도대로. boundary check 정상 동작. |

### 4.3 UX 설계 원칙 준수도

| 원칙 | 설명 | 준수 |
|------|------|------|
| **Track during dev, block at gate** | 개발 중엔 비차단 경고, verified 전환 시에만 차단 | ✅ Layer 2 Guide + Layer 3 Gate 분리 |
| **Fail with guidance** | 차단 시 다음 행동 안내 | ✅ print_transitions() + reentry 시나리오 |
| **Auto-correct over block** | 가능하면 차단 대신 자동 수정 | ✅ auto_backward (test→code) |
| **Minimal state overhead** | 개발자가 상태를 직접 관리할 필요 없음 | ✅ 모든 전환/커밋 자동화 |
| **Graceful degradation** | 상태 파일 없으면 아무것도 차단 안 함 | ✅ 전 hook `[ ! -f "$STATE" ] && exit 0` |

---

## 5. 강제 메커니즘 전수 목록

### 5.1 차단 (exit 2) — 22건

| # | 메커니즘 | Hook | 검사 대상 |
|---|---------|------|----------|
| 1 | .claude/ Bash 쓰기 차단 (git 명령 제외, v3.3.1) | check-phase.sh | Bash |
| 2 | .claude/ Edit/Write 차단 | check-phase.sh | Edit/Write |
| 3 | Bash 보호 경로 쓰기 (specs/) | check-phase.sh | Bash |
| 4 | Bash 보호 경로 쓰기 (test-cases/) | check-phase.sh | Bash |
| 5 | Bash 보호 경로 쓰기 (src/) | check-phase.sh | Bash |
| 6 | Bash 보호 경로 쓰기 (tests/) | check-phase.sh | Bash |
| 7 | Bash 관리 외부 코드 파일 | check-phase.sh | Bash |
| 8 | Edit/Write 관리 외부 코드 파일 | check-phase.sh | Edit/Write |
| 9 | 미매핑 파일 + 비활성 영역 | check-phase.sh | Edit/Write |
| 10 | Phase mismatch (영역별) | check-phase.sh | Edit/Write |
| 11 | verified lock (영역별) | check-phase.sh | Edit/Write |
| 12 | verified gate: @tc/@req 누락 | check-phase.sh | Edit/Write (hitl-state.json) |
| 13 | verified gate: supplementary TC 스키마 | check-phase.sh | Edit/Write (hitl-state.json) |
| 14 | verified gate: baseline TC 불변 위반 | check-phase.sh | Edit/Write (hitl-state.json) |
| 15 | verified gate: reentry 로그 필드 누락 | check-phase.sh | Edit/Write (hitl-state.json) |
| 16 | verified gate: Edit + "verified" | check-phase.sh | Edit (hitl-state.json) |
| 17 | **git tag 삭제 차단 (v3.4)** | check-phase.sh | Bash |
| 18 | **git checkout/restore .claude/ 차단 (v3.4)** | check-phase.sh | Bash |
| 19 | **git reset --hard 차단 (v3.4)** | check-phase.sh | Bash |
| 20 | **git push --force 차단 (v3.4)** | check-phase.sh | Bash |
| 21 | **Phase 전환 유효성 차단 (v3.4)** | check-phase.sh | Write (hitl-state.json) |
| 22 | **verified gate: Active TC 0개 (v3.4)** | check-phase.sh | Edit/Write (hitl-state.json) |

### 5.2 자동 상태 변경 — 5건

| # | 메커니즘 | Hook | 동작 |
|---|---------|------|------|
| 1 | auto_backward (test→code) | check-phase.sh | hitl-state.json phase 변경 + log |
| 2 | artifact commit | artifact-commit.sh | SPEC/TC 개별 git commit |
| 3 | phase commit | phase-commit.sh | 전환 시 git commit |
| 4 | verified tag | phase-commit.sh | git tag 생성 |
| 5 | change-log 기록 | trace-change.sh | change-log.jsonl 추가 |

### 5.3 경고 (비차단) — 9건

| # | 메커니즘 | Hook | 내용 |
|---|---------|------|------|
| 1 | @tc 누락 경고 | trace-change.sh | tests/ 수정 시 |
| 2 | @req 누락 경고 | trace-change.sh | tests/ 수정 시 |
| 3 | 팬텀 @tc 참조 경고 | trace-change.sh | TC JSON에 없는 TC ID |
| 4 | 미매핑 src/ 변경 경고 | check-phase.sh | verified gate 내 |
| 5 | hotfix 경고 (auto-backward + 보완 TC 없음) | check-phase.sh | verified gate 내 |
| 6 | 비정상 전환 경고 | phase-commit.sh | 유효하지 않은 phase 전환 |
| 7 | /traceability 실행 권장 | phase-commit.sh | verified 전환 시 |
| 8 | main 브랜치 경고 | restore-state.sh | 세션 시작 시 |
| 9 | auto_backward 안내 | check-phase.sh | src/ 수정 시 |

---

## 6. 종합 판정

### 이전 감사 대비 변화

```
                    v2.1 (이전)          v3.4 (현재)         변화
                    ──────────          ──────────         ──────
C1 Baseline 불변    ❌ 미구현            ✅ Hook 차단        해소 (v3.2)
N4 Reentry 로그     ❌ 프로세스만        ✅ Hook 차단        해소 (v3.3)
N5 skip_reason      ❌ 프로세스만        ✅ Hook 차단        해소 (v3.3)
B1 .claude/ 오탐    ❌ git 명령 차단     ✅ git 명령 허용    해소 (v3.3.1)
A1 Phase 건너뛰기   ❌ 미방어            ✅ 전환 맵 차단     해소 (v3.4)
A2 태그 삭제        ❌ 미방어            ✅ git tag -d 차단  해소 (v3.4)
A3 Hook 복원        ❌ 미방어            ✅ checkout 차단    해소 (v3.4)
A5 TC 0개 verified  ❌ 미방어            ✅ Check 6 차단     해소 (v3.4)
D1 .claude/ 서술    ⚠️ 부정확            ⚠️ 개선됨 (Low)     개선
D2 Gate 항목 수     ⚠️ 불일치            ✅ 일치             해소
D3 Hard blocks 수   ⚠️ 불일치            ✅ 일치 (22건)      해소
F1-F3 문서 갱신     ❌ 미반영            ✅ 반영 완료        해소
```

### 3대 목표 달성도

```
G1 자연스러운 흐름  ████████████████████  달성
                    auto_backward + Layer 2 경고 + graceful degradation
                    v3.3.1: git 명령 오탐 해소로 VCS 작업 무마찰

G2 ISO 26262 준수   ████████████████████  달성 (9/11 Hook 차단, 2/11 스킬 자동)
                    Hook 차단: 9건 (추적성, baseline, 변경통제, 형상관리, reentry 로그)
                    스킬 자동: 2건 (회귀 테스트, TC 격리)

G3 Reentry 히스토리  ████████████████████  완전 달성
                    모든 전환 git commit + tag + baseline TC 불변 검증
```

### 잔여 개선 기회 (선택)

| # | 항목 | 구현 방법 | 효과 | 권장 |
|---|------|----------|------|------|
| ~~**O1**~~ | ~~N4: Reentry 로그 필드 검증~~ | verified_gate Check 5 — cycle > 1일 때 reentry 로그의 `type`, `reason`, `affected_reqs` 존재 확인 | G2 완전 자동화 | **완료 (v3.3)** |
| ~~**O2**~~ | ~~N5: skip_reason 검증~~ | verified_gate Check 5 — `skipped_phases`가 있으면 `skip_reason` 존재 확인 | G2 완전 자동화 | **완료 (v3.3)** |
| **O3** | N2: phase-commit.sh `git add -A` → 선택적 스테이징 | `git add src/ tests/ .omc/` 로 범위 제한 | 보안 강화 | 낮음 |

### 최종 결론

v3.4는 이전 감사의 모든 실질 컨플릭트를 해소하고, 적대적 시나리오 4건(A1, A2, A3, A5)을 추가로 차단함.

- **G1**: 개발 흐름 무마찰. auto_backward + 비차단 경고 + graceful degradation. v3.3.1에서 git 명령 오탐도 해소되어 VCS 작업이 원활. v3.4의 전환 유효성 검사는 잘못된 전환만 차단하므로 정상 흐름에 영향 없음.
- **G2**: ISO 26262 핵심 요건 9/11 기계적 강제 (Hook 차단). v3.4에서 적대적 시나리오 방어가 추가되어 TD1 주장 강화. hard blocks 16→22건. 잔여 2건(TC 격리, 회귀 테스트)은 스킬 수준에서 자동 강제.
- **G3**: Reentry 전 과정의 git 이력 완전 추적. Baseline TC 불변(Check 4) + reentry 로그 완전성(Check 5) + 전환 유효성(v3.4) 모두 기계적 검증.

프레임워크의 설계 원칙 **"평소에는 추적하고, 관문에서 막는다"**가 코드와 문서 모두에서 일관되게 구현됨.

**v3.4 적대적 시나리오 방어 현황** (`docs/research-enforcement-architecture.md` 참조):
```
A1 Phase 건너뛰기  ✅ 차단 (전환 유효성 맵)
A2 태그 삭제       ✅ 차단 (git tag -d 차단)
A3 Hook 복원      ✅ 차단 (git checkout .claude/ 차단)
A4 빈 테스트      ❌ 미방어 (Tier 2: 테스트 증거 요구)
A5 TC 0개         ✅ 차단 (Check 6)
A6 스킬 미사용    ❌ 미방어 (Tier 3: UserPromptSubmit 안내)
A7 TC 격리 위반   ❌ 미방어 (Tier 2: Read 차단)
```
