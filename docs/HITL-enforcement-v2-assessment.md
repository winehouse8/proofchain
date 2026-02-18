# HITL 추적성 강제 시스템 v2.1 — 현황 평가 보고서

> **작성일**: 2026-02-18 (v2.1 갱신)
> **대상**: `.claude/hooks/` 6-Hook 강제 시스템 (check-phase.sh v3.1, phase-commit.sh v2.2, trace-change.sh v2.0, artifact-commit.sh v1.0)
> **기준 문서**: `docs/HITL-traceability-enforcement-report.md` (v1 갭 분석)
> **평가 기준**: (1) v1 갭 해소 여부, (2) ISO 26262 준수, (3) 개발/디버깅 UX
> **변경 이력**: v2.0 → v2.1: artifact-commit.sh 추가, CLAUDE.md 문서 정합성 수정 (N3 해소, 불변규칙 #3 근거 추가)

---

## 1. 요약 (Executive Summary)

### 1.1 전체 점수

| 평가 기준 | v2.0 | **v2.1** | 변화 |
|-----------|------|----------|------|
| **v1 갭 해소** | 13/16 (81%) | **13/16 (81%)** | 동일 (v1 갭 자체는 변동 없음) |
| **ISO 26262 준수** | 17/19 (89%) | **17/19 (89%)** | 동일 (부분 충족 2개는 기술적 한계) |
| **개발 UX** | 우수 | **우수** | artifact-commit이 투명 동작하므로 UX 영향 없음 |
| **형상 관리 커버리지** | phase 전환 시점만 | **산출물 단위 + phase 전환** | **신규 축: git 이력 공백 해소** |
| **신규 갭 (v2 발견)** | 5개 (N1-N5) | **4개 (N1,N2,N4,N5)** | N3 해소 |

### 1.2 아키텍처 현황

```
Layer 3: [Gate]   ← check-phase.sh verified_gate()
                     @tc/@req 매핑 검증 + supplementary TC 스키마 + change-log 커버리지
                     → 미충족 시 exit 2 차단

Layer 2: [Guide]  ← trace-change.sh (PostToolUse, non-blocking)
                     change-log.jsonl 기록 + @tc/@req 누락 경고 + 팬텀 참조 경고
                     → stderr 안내만, 차단 없음

Layer 1: [Guard]  ← check-phase.sh auto_backward() + phase-based access control
                     test→code 자동 전환 + verified 잠금 + .claude/ 자기 보호
                     → 상태 자동 전환 또는 exit 2 차단

        [Auto]    ← phase-commit.sh (PostToolUse): 전환 감지 → git commit + tag
                  ← artifact-commit.sh (PostToolUse): SPEC/TC 수정 → 개별 git commit
                     → non-blocking 자동화
```

### 1.3 v2.0 → v2.1 변경 요약

| 변경 | 내용 | 영향 |
|------|------|------|
| **artifact-commit.sh 추가** | SPEC-*.md, TC-*.json 수정마다 개별 git commit | ISO §7.4.5 형상 이력 강화 — phase 내부 변경도 git 추적 |
| **CLAUDE.md N3 해소** | 훅 테이블에 trace-change.sh + artifact-commit.sh 추가 | 문서-실제 정합성 회복 |
| **CLAUDE.md 불변규칙 #3** | G5/G11 미해결 근거 (운영 요건) 명시 | ISO §9.4.3 대응 문서화 |

---

## 2. v1 갭 해소 상태 (Gap Resolution)

### 2.1 치명적 갭 (High) — **5/5 해소**

| # | 갭 | v2 해결 방법 | 위치 | 상태 |
|---|---|-------------|------|------|
| **G1** | test phase에서 src/ 수정이 backward 전환 없이 허용 | `auto_backward()`: test→code 자동 전환 + 로그 + supplementary TC 안내 | check-phase.sh L71-121 | **해소** |
| **G2** | src/ 파일의 area 매핑 불가 | `change-log.jsonl` 접근법: 매 수정마다 파일-area JSONL 기록. verified gate에서 unmapped 경고 | trace-change.sh L26-44 | **해소** |
| **G8** | phase 전환 유효성 미검증 | `validate_transition()`: 5-phase 허용 전환 맵. 위반 시 stderr 경고 | phase-commit.sh L80-115 | **해소** |
| **G14** | @tc/@req 어노테이션 강제 없음 | 2중 검증: (1) trace-change.sh 실시간 경고, (2) verified gate 전수 차단 | trace-change.sh + check-phase.sh | **해소** |
| **G15** | TC JSON 없는 테스트 작성 가능 | 2중 검증: (1) 팬텀 @tc 경고, (2) verified gate 역방향 TC↔test 매핑 차단 | trace-change.sh + check-phase.sh | **해소** |

### 2.2 중간 갭 (Medium) — **4/5 해소**

| # | 갭 | v2 상태 | 판정 |
|---|---|---------|------|
| **G3** | tests/ area 매핑이 디렉토리명 의존 | 2글자 대문자 area 코드 추출. 공유 유틸은 unmapped 허용 | **해소** (허용된 제약) |
| **G5** | test-gen-design src/ 격리가 텍스트 지시만 | Claude Code API가 Read 차단 미지원. **v2.1에서 CLAUDE.md 불변규칙 #3에 근거 명시** | **미해소** (기술적 불가, 문서화 완료) |
| **G11** | test-gen-design 격리가 LLM 준수에 의존 | G5와 동일 근인 | **미해소** (기술적 불가, 문서화 완료) |
| **G12** | supplementary TC JSON 스키마 없음 | verified gate: 10필드 필수 + origin/added_reason 검증 | **해소** |
| **G13** | supplementary TC 구조 검증 없음 | G12와 동일 메커니즘 | **해소** |

### 2.3 경미 갭 (Low) — **4/4 수용**

| # | 갭 | 판정 | 비고 |
|---|---|------|------|
| **G4** | Bash 쓰기 감지 패턴 불완전 | **수용** | Layer 3 gate에서 사후 보완 |
| **G6** | git add -A로 코드/상태 혼재 커밋 | **수용** | 의도적 설계 — 원자적 phase 커밋. **v2.1의 artifact-commit.sh가 보완**: SPEC/TC는 개별 커밋으로 분리됨 |
| **G7** | --no-verify로 git hook 우회 | **수용** | 의도적 — 자동 커밋 안정성 우선 |
| **G9** | main 브랜치 개발 차단 불가 | **수용** | 경고 + CLAUDE.md 규칙 |
| **G10** | checkpoint.sh가 첫 area만 상세 보고 | **수용** | 의도적 — 가장 관련 높은 정보 우선 |
| **G16** | retry 카운트가 컨텍스트에만 존재 | **수용** | hitl-state.json + checkpoint.sh로 해결 |

### 2.4 갭 해소 요약

```
치명적 (High):    ████████████████████ 5/5 (100%)
중간 (Medium):    ████████████████░░░░ 4/5 (80%)  — G5/G11: Read 차단 기술적 불가
경미 (Low):       ████████████████████ 4/4 (100%) — 전부 의도적 수용
────────────────────────────────────────────────────
전체:             ████████████████░░░░ 13/16 (81%)
```

v2.0과 동일하나, G5/G11의 미해결 근거가 CLAUDE.md에 명시되어 **문서적 대응이 강화**됨.

---

## 3. ISO 26262 준수 평가

### 3.1 Part 6 — 소프트웨어 개발

| ISO 조항 | 요구사항 | HITL 메커니즘 | 준수 |
|----------|---------|--------------|------|
| **§6.4.7** | 기술 안전 요구사항 ↔ SW 안전 요구사항 양방향 추적성 | verified gate: REQ↔TC 전수 검사 | **충족** |
| **§7.4.5** | SW 컴포넌트 → 안전 요구사항 추적성 | hitl-state.json + change-log.jsonl | **충족** |
| **§8.4.5** | SW 아키텍처 ↔ SW 유닛 양방향 추적성 | @tc/@req 어노테이션 + /traceability 매트릭스 | **충족** |
| **§9.3** | SW 유닛 TC ↔ 설계 명세 양방향 추적성 | 3중 검증: trace-change 경고 + verified gate 차단 + /traceability | **충족** |
| **§9.4.2** | 구조적 커버리지 (statement, branch, MC/DC) | 프레임워크 외부 (Vitest/Playwright coverage) | **부분 충족** |
| **§9.4.5** | 테스트 결과 일관성 검증 | hitl-state.json pass/fail/retries 기록 | **충족** |
| **§9.4.6** | 변경 후 회귀 테스트 | cycle > 1 전체 회귀 필수 (Amendment Mode) | **충족** |

### 3.2 Part 8 — 지원 프로세스

| ISO 조항 | 요구사항 | HITL 메커니즘 | v2.0 | **v2.1** | 변화 |
|----------|---------|--------------|------|----------|------|
| **§7.4.2** | 형상 항목 고유 식별 | REQ-ID, TC-ID, area 코드 | 충족 | **충족** | - |
| **§7.4.3** | Baseline 설정 | verified 시 git tag `{AREA}-verified-c{cycle}` | 충족 | **충족** | - |
| **§7.4.4** | Baseline 이후 변경 통제 | verified 잠금 + reentry 필수 | 충족 | **충족** | - |
| **§7.4.5** | 형상 상태 기록 | hitl-state.json + log 배열 | 충족 | **강화** | **+artifact-commit.sh: SPEC/TC 매 수정마다 개별 git commit. phase 내부 변경 이력도 VCS에 보존** |
| **§7.4.6** | 형상 감사 | verified gate 전수 검사 | 충족 | **충족** | - |
| **§8.4.1** | 변경 요청 식별 | reentry 로그: type, reason, affected_reqs | 충족 | **충족** | - |
| **§8.4.2** | 영향 분석 | affected_reqs → TC/코드 식별 | 충족 | **충족** | - |
| **§8.4.4** | 변경 후 재검증 | Amendment Mode 전체 회귀 | 충족 | **충족** | - |
| **§8.4.7** | 산출물 생략 시 근거 | skip_reason 필수 | 충족 | **충족** | - |
| **§9.4.3** | 충분한 독립성으로 검증 | TC 격리 (운영 요건) | 부분 충족 | **부분 충족** | +CLAUDE.md에 미해결 근거 명시 |
| **§11.4.9** | 도구 운영 제약 문서화 | HITL.md + CLAUDE.md | 충족 | **충족** | - |

### 3.3 §7.4.5 강화 상세 — git 커밋 커버리지 매트릭스

v2.1에서 artifact-commit.sh가 추가되면서, 모든 형상 항목의 변경이 git에 기록되는 시점:

| 형상 항목 | 커밋 트리거 | 커밋 hook | 커밋 빈도 | 메시지 형식 |
|-----------|-----------|----------|----------|------------|
| **SPEC-*.md** | 매 Write/Edit | **artifact-commit.sh** | 낮음 (SPEC 수정마다) | `[artifact] CP(name): SPEC-CP-*.md [spec, cycle 1]` |
| **TC-*.json** | 매 Write/Edit | **artifact-commit.sh** | 낮음 (TC 수정마다) | `[artifact] CP(name): TC-CP.json [tc, cycle 1]` |
| **src/** | phase 전환 시 | phase-commit.sh (git add -A) | 전환마다 | `[proofchain] CP(name): code → test (cycle 1)` |
| **tests/** | phase 전환 시 | phase-commit.sh (git add -A) | 전환마다 | `[proofchain] CP(name): code → test (cycle 1)` |
| **hitl-state.json** | phase 전환 시 | phase-commit.sh | 전환마다 | `[proofchain] CP(name): spec → tc (cycle 1)` |

**v2.0 대비 개선**: SPEC과 TC의 **phase 내부 수정 이력**이 git에 개별 보존됨.

```
v2.0: ────[phase전환]─────[phase전환]─────[phase전환]──── (전환 시점만)
v2.1: ─●──●──[phase전환]──●──[phase전환]──●──●──[phase전환]── (산출물+전환)
      SPEC   SPEC         TC              TC  TC
      작성   수정         생성            수정 추가
```

### 3.4 도구 자격 (Tool Qualification)

| 항목 | 분류 | 근거 |
|------|------|------|
| Tool Impact (TI) | TI2 | AI가 코드/TC 생성 → 오류 주입 가능 |
| Tool Error Detection (TD) | **TD1** | TC 격리 + 인간 승인 + 전체 회귀 |
| Tool Confidence Level (TCL) | **TCL1** | TI2 + TD1 = TCL1 → 정식 도구 자격 불필요 |

### 3.5 ISO 준수 요약

```
Part 6 (SW 개발):     ██████████████████░░ 6/7 충족 (86%)  — §9.4.2 구조적 커버리지 부분
Part 8 (지원 프로세스): ██████████████████░░ 10/11 충족 (91%) — §9.4.3 독립성 부분
도구 자격:            ████████████████████ TCL1 달성 (100%)
─────────────────────────────────────────────────────────
전체:                 ██████████████████░░ 17/19 (89%)
```

부분 충족 2개:
1. **§9.4.2 구조적 커버리지**: 프레임워크 외부 도구 영역. CI에서 보완 가능.
2. **§9.4.3 검증 독립성**: Read 차단 기술적 불가. 운영적 통제 + CLAUDE.md 문서화.

---

## 4. 개발/디버깅 UX 평가

### 4.1 UX 매트릭스

| 시나리오 | 차단? | 안내? | git 커밋? |
|---------|------|------|----------|
| spec phase에서 SPEC 작성 | N | N | **Y (artifact-commit)** |
| tc phase에서 TC 생성 | N | N | **Y (artifact-commit)** |
| code phase에서 코딩 | N | N | N (전환 시 일괄) |
| test phase에서 테스트 실행 | N | N | N (전환 시 일괄) |
| test phase에서 src/ 수정 | N | Y (auto_backward) | Y (phase-commit) |
| tests/ 저장 시 @tc 누락 | N | Y | N |
| verified phase에서 수정 시도 | **Y** | Y | N |
| test→verified 시 추적성 미충족 | **Y** | Y | N |
| phase 전환 발생 | N | Y | Y (phase-commit) |
| **SPEC/TC 수정** (v2.1 신규) | **N** | **N** | **Y (artifact-commit, 투명)** |

**artifact-commit.sh의 UX 영향**: **제로**. PostToolUse에서 자동 실행, stderr에 1줄 확인 메시지만 출력. 개발 흐름 무방해.

### 4.2 UX 강점

1. **Fix loop 무마찰**: code/test phase에서 자유 수정. 경고는 non-blocking.
2. **자동 backward 투명성**: test→code 자동 전환, 수정 자체는 미차단.
3. **Gate 패턴**: "나중에 verified에서 정리하면 된다"는 안정감.
4. **컨텍스트 연속성**: restore-state.sh + checkpoint.sh로 세션/압축 시 상태 유지.
5. **산출물 자동 버전 관리** (v2.1): SPEC/TC 수정이 자동으로 git에 기록. 개발자 추가 행동 불필요.

### 4.3 UX 마찰점

| 마찰점 | 원인 | 경감 |
|--------|------|------|
| `.claude/` 자기 보호 | 보안 필수 | `/tmp/` → 수동 복사 |
| Bash 휴리스틱 false positive | G4 | deny 후 재시도 가능 |
| verified gate 대량 수정 | @tc/@req 누적 누락 | Layer 2 경고 따르면 누적 안 됨 |

### 4.4 OMC 대비 차별점

| 차원 | OMC | HITL v2.1 |
|------|-----|-----------|
| 차단 빈도 | 거의 없음 | 낮음 (verified gate + lock) |
| 상태 추적 | 세션별 분산 | 단일 중앙 (hitl-state.json) |
| 자동 커밋 | 없음 | **2단 자동 커밋** (산출물 + phase 전환) |
| change-log | 실행 흐름 추적 | 파일 변경 추적 |
| Graceful degradation | try-catch + fallback | hitl-state.json 부재 시 전 hook 스킵 |

---

## 5. 잔여 갭 및 개선 권고

### 5.1 미해소 v1 갭 (기술적 한계)

| # | 갭 | 근거 | 대응 |
|---|---|------|------|
| **G5/G11** | TC 격리 Read 차단 불가 | Claude Code API 제약 | 운영적 통제 + CLAUDE.md 문서화 (v2.1에서 강화) |

### 5.2 신규 발견 갭 (v2 평가에서 식별)

| # | 갭 | 심각도 | v2.0 | **v2.1** |
|---|---|--------|------|----------|
| **N1** | Baseline TC 내용 불변이 기계적으로 미강제 | Medium | 미해소 | **미해소** — verified gate에 checksum 검증 추가로 해소 가능 |
| **N2** | 5회 실패 에스컬레이션이 hook 미강제 | Low | 미해소 | **미해소** — 스킬 수준 처리로 충분 |
| ~~**N3**~~ | ~~CLAUDE.md hook 테이블 미기재~~ | ~~Low~~ | ~~미해소~~ | **해소** — trace-change.sh + artifact-commit.sh 추가 완료 |
| **N4** | .phase-snapshot.json 보호 없음 | Low | 미해소 | **미해소** — 자동 복구되므로 영향 미미 |
| **N5** | main 브랜치 경고 조건 불완전 | Low | 미해소 | **미해소** — CLAUDE.md 규칙으로 운영적 통제 |

### 5.3 개선 우선순위

| 순위 | 항목 | 난이도 | 효과 | 상태 |
|------|------|--------|------|------|
| ~~**즉시**~~ | ~~N3: CLAUDE.md 문서 정합성~~ | ~~1줄~~ | ~~문서 일관성~~ | **v2.1에서 완료** |
| **선택** | N1: Baseline TC checksum | 중간 | 불변성 기계적 강제 | 미착수 |
| **보류** | G5/G11: Read 차단 | Claude Code API 의존 | TC 격리 완전 자동화 | 외부 의존 |
| **보류** | N2: 5회 실패 hook 강제 | 높음 | 이미 스킬에서 처리 | 불필요 |

---

## 6. 강제 메커니즘 전수 목록 (v2.1)

### 6.1 차단 (Hard Block, exit 2) — 14건

| # | 조건 | 위치 |
|---|------|------|
| 1 | Bash에서 `.claude/` 참조 | check-phase.sh L319-323 |
| 2 | Edit/Write로 `.claude/` 수정 | check-phase.sh L424-430 |
| 3 | spec phase 아닌데 `.omc/specs/` 수정 | check-phase.sh L346-349 |
| 4 | tc/code/test phase 아닌데 `.omc/test-cases/` 수정 | check-phase.sh L350-353 |
| 5 | code/test phase 아닌데 `src/` 수정 | check-phase.sh L354-358 |
| 6 | code/test phase 아닌데 `tests/` 수정 | check-phase.sh L358-361 |
| 7 | verified phase에서 보호 경로 수정 | check-phase.sh L656-669 |
| 8 | area 없는데 매핑 불가 파일 수정 | check-phase.sh L577-587 |
| 9 | 코드 파일이 src/tests/ 외부 (Edit/Write) | check-phase.sh L507-519 |
| 10 | 코드 파일이 src/tests/ 외부 (Bash) | check-phase.sh L391-398 |
| 11 | verified gate: @tc 매핑 누락 | check-phase.sh L202-223 |
| 12 | verified gate: @req 매핑 누락 | check-phase.sh L202-223 |
| 13 | verified gate: supplementary TC 스키마 위반 | check-phase.sh L263-272 |
| 14 | verified gate: added_reason < 10자 | check-phase.sh L263-272 |

### 6.2 자동 상태 변경 (Auto-mutation) — 5건

| # | 동작 | 위치 | v2.1 |
|---|------|------|------|
| 15 | test→code auto_backward (src/ 쓰기 시) | check-phase.sh L71-121 | 기존 |
| 16 | phase 전환 → git 자동 커밋 | phase-commit.sh L146-159 | 기존 |
| 17 | verified → git tag 생성 | phase-commit.sh L161-166 | 기존 |
| 18 | src/tests/ 수정 → change-log JSONL 추가 | trace-change.sh L42-58 | 기존 |
| **19** | **SPEC/TC 수정 → 개별 git 커밋** | **artifact-commit.sh L56-67** | **신규** |

### 6.3 경고 (Warning, stderr) — 9건

| # | 경고 내용 | 위치 |
|---|----------|------|
| 20 | 불법 phase 전환 | phase-commit.sh L101-114 |
| 21 | @tc 어노테이션 개수 부족 | trace-change.sh L72-79 |
| 22 | @req 어노테이션 개수 부족 | trace-change.sh L72-79 |
| 23 | phantom @tc 참조 | trace-change.sh L111-116 |
| 24 | change-log unmapped 파일 | check-phase.sh L283-291 |
| 25 | auto-backward 이력 but supplementary TC 0개 | check-phase.sh L299-307 |
| 26 | verified 시 /traceability 실행 권장 | phase-commit.sh L172-175 |
| 27 | main 브랜치 개발 경고 | restore-state.sh L16-20 |
| 28 | auto_backward 발동 시 supplementary TC 안내 | check-phase.sh L102-118 |

### 6.4 인식 주입 (Awareness) — 3건

| # | 내용 | 위치 | v2.1 |
|---|------|------|------|
| 29 | SessionStart 상태 요약 | restore-state.sh L23-54 | 기존 |
| 30 | PreCompact 체크포인트 | checkpoint.sh L23-49 | 기존 |
| **31** | **artifact-commit 확인 메시지** | **artifact-commit.sh L69** | **신규** |

**v2.1 총계**: 차단 14 + 자동변경 5 + 경고 9 + 인식 3 = **31건** (v2.0: 29건)

---

## 7. 종합 평가

### 7.1 v1 → v2.0 → v2.1 개선 흐름

```
v1 (단일 레이어):
  ┌──────────────────────────────────────────────────┐
  │  spec: HARD  │  code/test: SOFT   │  veri: HARD  │
  │              │  (git 이력 없음)    │              │
  └──────────────────────────────────────────────────┘
  "양 끝은 단단하고, 중간은 느슨하다"

v2.0 (3-Layer):
  ┌──────────────────────────────────────────────────┐
  │  spec: HARD  │  code/test: GUIDED │  veri: GATED │
  │  (전환 시    │  (전환 시 커밋)     │  (전환+tag)  │
  │   커밋만)    │                     │              │
  └──────────────────────────────────────────────────┘
  "안내하고 출구에서 잡되, phase 내부 이력은 소실"

v2.1 (3-Layer + Artifact Commit):
  ┌──────────────────────────────────────────────────┐
  │  spec: HARD  │  code/test: GUIDED │  veri: GATED │
  │  (매 수정    │  (전환 시 커밋)     │  (전환+tag)  │
  │   개별 커밋) │                     │              │
  └──────────────────────────────────────────────────┘
  "핵심 산출물은 매번 기록, 코드는 전환 시 일괄, 출구에서 검증"
```

### 7.2 git 이력 커버리지 비교

| 형상 항목 | v1 | v2.0 | **v2.1** |
|-----------|-----|------|----------|
| SPEC-*.md | 미추적 | 전환 시 일괄 | **매 수정 개별 커밋** |
| TC-*.json | 미추적 | 전환 시 일괄 | **매 수정 개별 커밋** |
| src/ | 미추적 | 전환 시 일괄 | 전환 시 일괄 (동일) |
| tests/ | 미추적 | 전환 시 일괄 | 전환 시 일괄 (동일) |
| hitl-state.json | 미추적 | 전환 시 커밋 | 전환 시 커밋 (동일) |
| verified milestone | 미추적 | git tag | git tag (동일) |

**결론**: SPEC과 TC는 ISO 26262에서 "진실 원천"과 "검증 근거"에 해당하는 최고 중요도 산출물. 이들의 모든 변경이 개별 git commit으로 추적되는 것은 §7.4.5 준수에 실질적 강화.

### 7.3 결론

| 질문 | v2.1 답변 |
|------|----------|
| **(1) v1 문제 해결** | 치명적 5개 전수 해소. 미해소 2개(G5/G11)는 기술적 한계, CLAUDE.md에 근거 문서화 완료. |
| **(2) ISO 26262 준수** | 17/19 (89%). §7.4.5 형상 이력이 artifact-commit으로 실질 강화. TCL1 유지. |
| **(3) 개발 UX** | artifact-commit은 투명 동작 — UX 영향 제로. fix loop 무마찰 유지. |
| **(4) git 이력 공백** (신규) | SPEC/TC: 공백 해소. src/tests: 전환 시점 커밋으로 충분 (fix-loop에서 auto_backward가 전환을 유발하므로 사실상 매 수정 사이클마다 커밋 발생). |

### 7.4 다음 권고

| 순위 | 항목 | 비고 |
|------|------|------|
| **1** | 실전 프로젝트로 풀 사이클 검증 | 이론적 분석의 한계 — 실제 돌려봐야 진짜 문제 발견 |
| **2** | N1: Baseline TC checksum | △ → O 전환. verified gate에서 기계적 불변성 강제 |
| **3** | 커버리지 gate | §9.4.2 X → O 전환. verified gate에 coverage 임계치 추가 |

---

## 부록 A: 파일별 기능 인벤토리

### check-phase.sh (v3.1, 693줄)

| 기능 | 줄 | Layer | 차단? |
|------|-----|-------|------|
| .claude/ 자기 보호 (Bash) | L319-323 | Guard | Y |
| .claude/ 자기 보호 (Edit/Write) | L424-430 | Guard | Y |
| auto_backward (test→code) | L71-121 | Guard | N (상태 전환) |
| verified_gate: @tc/@req 매핑 | L136-223 | Gate | Y |
| verified_gate: supplementary TC 스키마 | L225-272 | Gate | Y |
| verified_gate: change-log 커버리지 | L274-307 | Gate | N (경고) |
| verified 전환 감지 (Write) | L441-460 | Gate | Y (gate 실패 시) |
| verified 전환 감지 (Edit) | L462-473 | Gate | Y (gate 실패 시) |
| phase 기반 파일 접근 제어 | L479-692 | Guard | Y |
| Approach A: 관리 외 코드 파일 차단 | L492-524 | Guard | Y |
| Bash 휴리스틱 쓰기 감지 | L325-400 | Guard | Y |
| print_transitions() 안내 | L32-66 | Guide | N |

### phase-commit.sh (v2.2, 187줄)

| 기능 | 줄 | Layer | 차단? |
|------|-----|-------|------|
| 전환 감지 (snapshot 대조) | L56-75 | Auto | N |
| validate_transition() | L80-97 | Guide | N (경고) |
| 자동 git commit | L146-159 | Auto | N |
| verified git tag 생성 | L161-166 | Auto | N |
| /traceability 안내 | L168-177 | Guide | N |

### trace-change.sh (v2.0, 124줄)

| 기능 | 줄 | Layer | 차단? |
|------|-----|-------|------|
| src/ 변경 → change-log.jsonl | L26-44 | Guide | N |
| tests/ 변경 → change-log.jsonl | L46-58 | Guide | N |
| @tc/@req 어노테이션 개수 경고 | L60-79 | Guide | N |
| @tc 팬텀 참조 경고 | L82-119 | Guide | N |

### artifact-commit.sh (v1.0, 72줄) — v2.1 신규

| 기능 | 줄 | Layer | 차단? |
|------|-----|-------|------|
| SPEC-*.md 수정 감지 + 개별 git commit | L24-67 | Auto | N |
| TC-*.json 수정 감지 + 개별 git commit | L24-67 | Auto | N |
| area/phase/cycle 메타데이터 커밋 메시지 | L65 | Auto | N |
| stderr 확인 메시지 | L69 | Awareness | N |

### restore-state.sh (57줄) + checkpoint.sh (51줄)

| 기능 | Layer | 차단? |
|------|-------|------|
| main 브랜치 경고 | Guide | N |
| 세션 시작 상태 주입 | Awareness | N |
| 컨텍스트 압축 전 상태 보존 | Awareness | N |

---

## 부록 B: ISO 26262 Programmatic Checks 매핑

| Check ID | ISO 조항 | HITL 메커니즘 | 자동화 수준 | v2.1 변화 |
|----------|---------|--------------|-----------|----------|
| TRACE-001 | §9.3 | verified gate: REQ→TC 연결 | Hook (자동) | - |
| TRACE-002 | §9.3 | verified gate: TC→REQ 연결 | Hook (자동) | - |
| TRACE-003 | §8.4.5 | change-log + code.files REQ→src | 부분 자동 | - |
| TRACE-004 | §6.4.7 | /traceability 매트릭스 | 스킬 (수동) | - |
| BASE-001 | §7.4.3 | 불변규칙 #1 + 스킬 준수 | 운영적 | - |
| BASE-002 | §7.4.3 | phase-commit.sh: verified tag | Hook (자동) | - |
| **CFG-001** | **§7.4.5** | **artifact-commit.sh: SPEC/TC 개별 커밋** | **Hook (자동)** | **신규** |
| CFG-002 | §7.4.5 | phase-commit.sh: phase 전환 커밋 | Hook (자동) | - |
| CHG-001 | §8.4.1 | reentry 로그: type/reason/affected_reqs | 스킬 (자동) | - |
| CHG-002 | §8.7 | skip_reason 필수 | 스킬 (수동) | - |
| CHG-003 | §9.4.6 | Amendment Mode 전체 회귀 | 스킬 (자동) | - |
| VER-001 | §9.4.3 | TC 격리 운영 요건 | 운영적 | +CLAUDE.md 근거 명시 |
| VER-002 | §9.4.1 | Phase gate 인간 승인 | 프로세스 | - |
| VER-003 | §7.4.4 | verified lock | Hook (자동) | - |
| TOOL-001 | §11.4.9 | HITL phase gate + 인간 리뷰 | 프로세스 | - |
| TOOL-002 | §11.4.2 | TC 격리 + CLAUDE.md 규칙 | 운영적 | +CLAUDE.md 근거 명시 |
| COV-001 | §9.4.2 | (미포함 — 외부 도구 영역) | 미구현 | - |
| REG-001 | §9.4.6 | 전체 회귀 + pass/fail 기록 | 스킬 (자동) | - |
| FAIL-001 | §9.4.5 | 5회 실패 에스컬레이션 | 스킬 (자동) | - |

**범례**: Hook (자동) = 기계적 강제, 스킬 = LLM 준수 의존, 운영적 = 문서/프로세스 통제, 미구현 = 프레임워크 범위 밖
