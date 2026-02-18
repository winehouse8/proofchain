# HITL 추적성 강제 시스템 개선 보고서

> **작성일**: 2026-02-18
> **대상**: `.omc/` HITL 프레임워크 v1
> **동기**: test phase에서 MUX 버그 수정 + 적대적 테스트 27개 작성 시 SPEC → TC → code → test 순서 및 추적성 체인 이탈 발생

---

## 1. 사건 분석: 무엇이 깨졌는가

### 1.1 타임라인

```
[verified] ──reentry──→ [code] ──→ [test] ──→ ??? ──→ [verified]
                          ✓          ✗✗✗        ✗         ✓
```

| 시점 | 행위 | HITL 준수 | 위반 내용 |
|------|------|----------|----------|
| Reentry 시작 | verified → code, cycle++ | O | 정상 |
| 주파수 컬러링 구현 | src/ 수정 during code phase | O | 정상 |
| 기존 테스트 통과 → test phase | code → test 전환 | O | 정상 |
| 유저 "같은 Hz인데 색이 달라" | test phase에서 src/ 수정 | **X** | backward 전환 없이 코드 수정 |
| 유저 "input 비우기가 안돼" | test phase에서 src/ + tests/ 수정 | **X** | SPEC에 없는 동작, TC 없는 테스트 |
| 유저 "MUX input 추가가 안돼" | test phase에서 src/ 수정 | **X** | SPEC 갭 — REQ 없음 |
| 적대적 테스트 27개 작성 | TC JSON 없이 직접 작성 | **X** | @tc/@req 미부착, TC JSON 미등록 |
| useUpdateNodeInternals 추가 | test phase에서 src/ 수정 | **X** | 로그 미기록, 상태 전환 없음 |
| 유저 "잘된다" → verified | test → verified | O | 정상 (결과적으로) |

### 1.2 깨진 추적성 체인

```
정상 체인:
  REQ-CN-016 (MUX 동적 포트)
    → TC-CN-016a (inputCount 축소 시 엣지 정리)
    → TC-CN-016b (새 포트 연결 가능)
    → adversarial-mux.test.ts::test_016a()  // @tc TC-CN-016a @req REQ-CN-016
    → src/store/useClockStore.ts (edge cleanup)
    → src/components/nodes/ClockNode.tsx (useUpdateNodeInternals)

실제:
  (유저 버그 리포트)
    → (REQ 없음)
    → (TC 없음)
    → adversarial-mux.test.ts::7개 테스트  // @tc 없음 @req 없음
    → src/ 수정 2건
```

---

## 2. 현재 시스템 갭 분석 (16개)

### 2.1 치명적 갭 (High)

| # | 갭 | 현재 동작 | 기대 동작 |
|---|---|----------|----------|
| G1 | `test` phase에서 `src/` 수정 허용 | check-phase.sh가 code/test 모두에서 src/ 쓰기 허용 | test → code backward 전환 후에만 허용 |
| G2 | `src/` 파일의 area 매핑 불가 | hitl-state.json에 `code.files` 필드 없음 | 파일→area 매핑으로 교차 area 오염 방지 |
| G8 | phase 전환 유효성 미검증 | phase-commit.sh가 전환 발생만 감지 | 허용된 전환인지 상태 머신 규칙 검증 |
| G14 | @tc/@req 어노테이션 강제 없음 | 규칙은 있으나 검사 없음 | 테스트 파일 저장 시 어노테이션 존재 검증 |
| G15 | TC JSON 없는 테스트 작성 가능 | check-phase.sh가 tests/ 쓰기만 확인 | TC JSON에 대응 항목 없으면 차단 |

### 2.2 중간 갭 (Medium)

| # | 갭 | 설명 |
|---|---|------|
| G3 | tests/ area 매핑이 디렉토리명 의존 | 공유 유틸은 area 매핑 안 됨 |
| G5 | test-gen-design의 src/ 격리가 텍스트 지시만 | hook이 Read를 차단하지 않음 |
| G11 | test-gen-design 격리가 LLM 준수에 의존 | 프로그래밍적 강제 없음 |
| G12 | supplementary TC JSON 스키마 없음 | 구조 검증 불가 |
| G13 | supplementary TC 구조 검증 없음 | 필수 필드 누락 시 무방비 |

### 2.3 경미 갭 (Low)

| # | 갭 | 설명 |
|---|---|------|
| G4 | Bash 쓰기 감지 패턴 불완전 | dd, patch, python -c 등 미감지 |
| G6 | phase-commit.sh의 git add -A | 코드 변경과 상태 변경이 혼재 |
| G7 | --no-verify로 git hook 우회 | 외부 품질 게이트 무시 |
| G9 | restore-state.sh가 정보 제공만 | main 브랜치 개발 차단 불가 |
| G10 | checkpoint.sh가 첫 active area만 상세 보고 | 다중 area 작업 시 정보 손실 |
| G16 | fix loop 중 retry 카운트가 컨텍스트에만 존재 | compaction 시 손실 가능 |

---

## 3. oh-my-claudecode(OMC) 참조 분석

### 3.1 OMC 아키텍처 요약

OMC는 **생산성 극대화**를 위한 멀티 에이전트 오케스트레이션 시스템:
- 28개 전문 에이전트 (3-tier 모델 라우팅)
- 37개 스킬 (워크플로우 자동화)
- 31개 라이프사이클 훅 (이벤트 기반)
- 7개 실행 모드 (autopilot, ralph, ultrawork 등)

### 3.2 OMC에서 배울 수 있는 패턴

#### 패턴 A: 트랜잭션 전환 (Transactional Transitions)

OMC의 `team-pipeline/transitions.ts`는 phase 전환을 트랜잭셔널하게 처리:

```typescript
// OMC 패턴: 전환 단계마다 execute/rollback 쌍
const steps = [
  { name: "save progress", execute: ..., rollback: ... },
  { name: "clear old state", execute: ..., rollback: ... },
  { name: "start new mode", execute: ..., rollback: ... },
];
await executeTransition(steps); // 실패 시 자동 롤백
```

**HITL 적용**: hitl-state.json의 phase 변경을 트랜잭셔널하게 만들면, 유효하지 않은 전환(test→verified 사이에 code 거치지 않음)을 원자적으로 거부할 수 있다.

#### 패턴 B: 전환 규칙 하드코딩 (Allowed Transitions Map)

OMC의 `team-pipeline`은 허용된 전환을 명시적으로 정의:

```typescript
const ALLOWED: Record<Phase, Phase[]> = {
  'team-plan': ['team-prd'],
  'team-prd': ['team-exec'],
  'team-exec': ['team-verify'],
  'team-verify': ['team-fix', 'complete', 'failed'],
  'team-fix': ['team-exec', 'team-verify'],
};
```

**HITL 적용**: `check-phase.sh`에 전환 맵을 넣어, Write 시점에 이전 phase와 새 phase를 비교하여 유효하지 않은 전환을 차단.

#### 패턴 C: Pre-Tool Enforcer (도구 호출 전 컨텍스트 주입)

OMC의 `pre-tool-enforcer.mjs`는 모든 도구 호출 전에 컨텍스트를 주입:
- pending TODO 개수를 세서 리마인더 출력
- 에이전트 메타데이터 주입
- 현재 모드에 따른 지침 삽입

**HITL 적용**: `check-phase.sh`가 차단뿐 아니라, test phase에서 src/ 수정 시도를 감지하면 "backward 전환을 먼저 수행하세요"라는 안내 메시지를 stderr로 반환. LLM이 이를 읽고 행동을 수정.

#### 패턴 D: 실행 흐름 추적 (Agent Flow Trace)

OMC의 `trace-tools.ts`는 모든 에이전트/도구 호출을 JSONL로 기록:

```jsonl
{"ts":..., "event":"tool_start", "tool":"Edit", "target":"src/foo.ts"}
{"ts":..., "event":"tool_end", "tool":"Edit", "result":"success"}
```

**HITL 적용**: 도구 호출을 추적하면, test phase에서 발생한 모든 src/ 수정을 사후 감사(audit)할 수 있다. 실시간 차단이 아니더라도, verified 전환 전에 감사 보고서를 생성하여 미추적 변경을 식별.

#### 패턴 E: 아티팩트 전제 조건 (Artifact Prerequisites)

OMC의 team-pipeline은 전환 전에 아티팩트 존재를 검증:
- `team-exec` 진입 시 `plan_path` 또는 `prd_path` 필수
- `team-verify` 진입 시 `tasks_completed >= tasks_total` 필수

**HITL 적용**: `test → verified` 전환 시, 모든 테스트 파일에 @tc 어노테이션이 있고, 모든 TC가 테스트에 매핑되어 있는지 검증.

### 3.3 OMC에 없는 것 (HITL 고유 강점)

| HITL 기능 | OMC 대응 | 비고 |
|-----------|---------|------|
| Baseline TC 불변 | 없음 | OMC는 TC 개념 자체가 없음 |
| REQ → TC → code 추적 | 에이전트 흐름 추적만 | OMC는 "무엇이 실행됐는가"만 추적 |
| verified 잠금 | 없음 | OMC는 파일 접근 제어가 없음 |
| ISO 26262 정렬 | 없음 | OMC는 규정 준수 프레임워크 없음 |
| 5회 실패 에스컬레이션 | ralph max_iterations | 유사하지만 덜 세분화 |

---

## 4. 핵심 문제: "부드러운 중간" (The Soft Middle)

현재 시스템의 가장 큰 구조적 문제는 **양 끝은 단단하고 중간이 느슨하다**는 것:

```
  [spec]          [code / test]           [verified]
  ┌──────┐    ┌────────────────────┐    ┌──────────┐
  │ HARD │    │      S O F T       │    │   HARD   │
  │      │    │                    │    │          │
  │ spec/ │   │ src/ 자유 수정     │    │ 모든 쓰기│
  │ 만 쓰 │   │ tests/ 자유 수정   │    │ 차단     │
  │ 기 가 │   │ TC 없이 테스트 가능│    │ reentry  │
  │ 능    │   │ @tc/@req 미검증   │    │ 필수     │
  │       │   │ backward 미강제   │    │          │
  └──────┘    └────────────────────┘    └──────────┘
```

code/test phase에서의 유연성은 **의도적 설계**다 — fix loop가 빠르게 돌아야 하므로. 하지만 이 유연성이 **추적성을 파괴**한다.

### 4.1 근본 원인

**대화형 개발과 형식적 프로세스 사이의 마찰을 해소하는 메커니즘이 없다.**

유저가 "이거 고쳐줘"라고 하면:
1. LLM은 가장 효율적인 경로(바로 고치기)를 선택
2. hook은 code/test phase에서 이를 허용
3. 추적성은 사후에도 복구되지 않음
4. 결과적으로 "코드는 고쳐졌지만 왜 고쳤는지" 기록이 없음

---

## 5. 제안: 3-Layer 강제 아키텍처

현재의 단일 레이어(hook 차단) 대신, 3개 레이어로 강제력을 분산:

```
Layer 3: [Gate]     — verified 전환 전 전수 검사
Layer 2: [Guide]    — 도구 호출 시 컨텍스트 주입으로 행동 유도
Layer 1: [Guard]    — 위반 시 차단 (현재 check-phase.sh 역할)
```

### Layer 1: Guard (차단) — check-phase.sh 강화

#### 5.1.1 `test` phase에서 `src/` 수정 시 자동 backward 전환

```bash
# check-phase.sh 개선안

# test phase에서 src/ 수정 감지 시
if $IS_SRC && [ "$AREA_PHASE" = "test" ]; then
    # 자동으로 test → code backward 전환
    jq --arg area "$TARGET_AREA" \
       '.areas[$area].phase = "code"' \
       "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

    # 로그 기록
    jq --arg area "$TARGET_AREA" \
       '.log += [{"timestamp":"'$(date -u +%FT%TZ)'",
                  "area":$area, "from":"test", "to":"code",
                  "actor":"hook", "type":"auto-backward",
                  "note":"src/ modification detected during test phase"}]' \
       "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

    # 경고 메시지 (LLM이 읽음)
    echo "⚠ Auto-backward: test → code (src/ 수정 감지)" >&2
    echo "코드 수정 완료 후 테스트를 재실행하여 code → test로 복귀하세요." >&2
    exit 0  # 허용하되 상태는 변경
fi
```

**효과**: src/ 수정 자체는 허용하되, 상태가 자동으로 `code`로 전환되어 기록이 남는다. LLM이 테스트를 재실행해야 `test`로 돌아올 수 있다.

#### 5.1.2 phase 전환 유효성 검증

```bash
# phase-commit.sh에 전환 맵 추가
VALID_TRANSITIONS='{
  "spec":     ["tc"],
  "tc":       ["code", "spec"],
  "code":     ["test", "tc"],
  "test":     ["verified", "code"],
  "verified": ["spec", "tc", "code"]
}'

OLD_PHASE=$(jq -r ".areas[\"$AREA\"].phase" "$OLD_STATE")
NEW_PHASE=$(jq -r ".areas[\"$AREA\"].phase" "$NEW_STATE")

IS_VALID=$(echo "$VALID_TRANSITIONS" | jq --arg old "$OLD_PHASE" --arg new "$NEW_PHASE" \
  '.[$old] // [] | index($new) != null')

if [ "$IS_VALID" != "true" ]; then
    echo "ERROR: Invalid transition $OLD_PHASE → $NEW_PHASE" >&2
    # 롤백
    cp "$OLD_STATE" "$STATE"
    exit 1
fi
```

### Layer 2: Guide (유도) — 새 hook: `trace-change.sh`

차단하지 않되, 추적성에 필요한 정보를 자동으로 수집하고 LLM에 안내:

```bash
#!/bin/bash
# hooks/trace-change.sh (PostToolUse, matcher: Edit|Write)
# 목적: src/tests/ 변경 시 변경 사유와 연결 정보를 자동 수집

TOOL="$1"
FILE_PATH="..."  # 도구 결과에서 추출

# src/ 수정 시
if [[ "$FILE_PATH" == src/* ]]; then
    CHANGE_LOG=".omc/change-log.jsonl"
    echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"file\":\"$FILE_PATH\",\"phase\":\"$PHASE\",\"area\":\"$AREA\"}" \
        >> "$CHANGE_LOG"
fi

# tests/ 수정 시 — @tc/@req 검증
if [[ "$FILE_PATH" == tests/* ]]; then
    # 새로 추가/수정된 테스트 함수에서 @tc 어노테이션 확인
    MISSING=$(grep -c "^\s*it(" "$FILE_PATH" 2>/dev/null || echo 0)
    ANNOTATED=$(grep -c "@tc" "$FILE_PATH" 2>/dev/null || echo 0)

    if [ "$MISSING" -gt "$ANNOTATED" ]; then
        echo "⚠ 추적성 경고: $FILE_PATH 에 @tc 어노테이션 없는 테스트 $(($MISSING - $ANNOTATED))개" >&2
        echo "  → 각 테스트에 // @tc TC-XX-NNNx, // @req REQ-XX-NNN 추가 필요" >&2
    fi
fi
```

**효과**: 차단은 안 하지만, LLM이 stderr에서 경고를 읽고 어노테이션을 추가하도록 유도. 자연스러운 대화 흐름을 깨지 않으면서 추적성 정보를 축적.

### Layer 3: Gate (게이트) — verified 전환 전 전수 검사

`test → verified` 전환은 가장 중요한 품질 관문. 이 시점에서 전수 검사:

```bash
#!/bin/bash
# check-phase.sh 내 verified 전환 시 추가 검증

if [ "$NEW_PHASE" = "verified" ] && [ "$OLD_PHASE" = "test" ]; then
    ERRORS=()

    # 1. 모든 테스트 파일에 @tc 어노테이션 존재 확인
    for TEST_FILE in tests/unit/$AREA/*.test.* tests/component/$AREA/*.test.*; do
        [ -f "$TEST_FILE" ] || continue
        IT_COUNT=$(grep -c "^\s*it(" "$TEST_FILE" || echo 0)
        TC_COUNT=$(grep -c "@tc" "$TEST_FILE" || echo 0)
        if [ "$IT_COUNT" -gt "$TC_COUNT" ]; then
            ERRORS+=("$TEST_FILE: $((IT_COUNT - TC_COUNT))개 테스트에 @tc 없음")
        fi
    done

    # 2. TC JSON의 모든 active TC가 테스트 코드에 매핑 확인
    TC_FILE=$(jq -r ".areas[\"$AREA\"].tc.file" "$STATE")
    if [ -f "$TC_FILE" ]; then
        ALL_TC_IDS=$(jq -r '
            [.baseline_tcs[]? | select(.status != "obsolete") | .tc_id] +
            [.supplementary_tcs[]? | .tc_id] | .[]' "$TC_FILE")
        for TC_ID in $ALL_TC_IDS; do
            FOUND=$(grep -rl "@tc $TC_ID" tests/ 2>/dev/null | head -1)
            if [ -z "$FOUND" ]; then
                ERRORS+=("TC $TC_ID: 테스트 코드에서 찾을 수 없음")
            fi
        done
    fi

    # 3. change-log에 기록된 src/ 변경이 모두 TC로 커버되는지
    # (변경된 파일에 대한 테스트 존재 확인)

    if [ ${#ERRORS[@]} -gt 0 ]; then
        echo "ERROR: verified 전환 차단 — 추적성 미충족:" >&2
        for E in "${ERRORS[@]}"; do
            echo "  - $E" >&2
        done
        echo "→ 누락된 @tc 어노테이션을 추가하거나, /traceability로 갭 분석 후 보완하세요." >&2
        exit 1  # 차단
    fi
fi
```

**효과**: code/test phase에서 아무리 자유롭게 작업해도, verified로 가려면 추적성 체인이 완성되어야 한다. "출구에서 잡는" 전략.

---

## 6. 구체적 개선안

### 6.1 "Hotfix 모드": 대화형 버그 수정의 정규화

현재 가장 큰 마찰은 유저가 "이거 고쳐줘"라고 할 때 SPEC → TC → code → test 풀 루프를 돌기엔 너무 무겁다는 것. OMC의 "execution mode" 개념을 차용하여 **hotfix 모드**를 도입:

```
유저: "MUX input 추가가 안돼"
  ↓
시스템 자동 감지: verified/test phase에서 코드 수정 필요
  ↓
[hotfix 모드 자동 진입]
  1. phase를 code로 자동 backward (hook이 처리)
  2. 임시 REQ 생성: REQ-XX-HOTFIX-001 "MUX inputCount 변경 시 handle 재등록"
  3. src/ 수정 허용
  4. 수정 완료 후 → 테스트 실행
  5. 통과 → test phase 복귀
  6. verified 전환 시 → Gate가 hotfix REQ를 정식 REQ로 승격 요구
```

**장점**:
- 대화 흐름을 깨지 않음 (유저는 자연스럽게 "고쳐줘" 가능)
- 모든 변경에 최소한의 REQ가 부여됨 (추적성 유지)
- verified 전환 시 정식 SPEC 반영을 강제함 (품질 보장)

### 6.2 hitl-state.json 확장: `code.files` 필드

```json
{
  "CN": {
    "code": {
      "status": "implemented",
      "files": [
        "src/components/nodes/ClockNode.tsx",
        "src/components/PropertyPanel/PropertyPanel.tsx"
      ]
    }
  }
}
```

**효과**: check-phase.sh가 파일별 area 매핑을 수행하여 교차 area 오염 방지. CN이 verified인데 WR이 code일 때, ClockNode.tsx 수정을 차단할 수 있음.

### 6.3 supplementary TC 스키마 + 자동 생성

```json
// tc-schema-supplementary.json
{
  "required": ["tc_id", "origin", "req_id", "type", "level", "title",
               "given", "when", "then", "added_reason"],
  "properties": {
    "origin": { "const": "supplementary" },
    "added_reason": { "minLength": 10 }
  }
}
```

test-gen-code 스킬에서 `src/` 버그 수정 후 supplementary TC를 자동 생성하도록 강화:

```
코드 수정 감지 → "이 수정에 대한 TC를 생성하시겠습니까?" → 자동 TC JSON 추가 + 테스트 코드에 @tc 부착
```

### 6.4 verified 전환 전 `/traceability` 자동 실행

```bash
# phase-commit.sh에서 verified 전환 감지 시
if [ "$NEW_PHASE" = "verified" ]; then
    # Gate 검증은 check-phase.sh가 수행
    # 여기서는 추적성 매트릭스를 자동 생성하여 커밋에 포함
    echo "⚠ verified 전환: /traceability 실행을 권장합니다." >&2
fi
```

---

## 7. 구현 우선순위

| 순위 | 개선안 | 효과 | 난이도 | 설명 |
|------|--------|------|--------|------|
| **P0** | test→code 자동 backward (§5.1.1) | src/ 수정이 항상 code phase로 기록됨 | 낮음 | check-phase.sh에 15줄 추가 |
| **P0** | phase 전환 유효성 검증 (§5.1.2) | 불법 전환 원천 차단 | 낮음 | phase-commit.sh에 20줄 추가 |
| **P1** | @tc 경고 hook (§5 Layer 2) | LLM이 어노테이션을 잊지 않음 | 낮음 | 새 hook 50줄 |
| **P1** | verified Gate 검사 (§5 Layer 3) | 추적성 미충족 시 verified 차단 | 중간 | check-phase.sh에 40줄 추가 |
| **P2** | hotfix 모드 (§6.1) | 자연스러운 대화 + 추적성 양립 | 높음 | 스킬 + hook + 상태 확장 필요 |
| **P2** | code.files 필드 (§6.2) | area간 격리 강화 | 중간 | 상태 스키마 + hook 수정 |
| **P3** | supplementary TC 스키마 (§6.3) | TC 데이터 무결성 | 낮음 | JSON 스키마 + 검증 로직 |
| **P3** | change-log 추적 (§5 Layer 2) | 사후 감사 가능 | 낮음 | PostToolUse hook |

---

## 8. OMC vs HITL: 철학적 차이와 수렴점

```
OMC:  "빠르게 만들고, 빠르게 검증하고, 빠르게 반복"
HITL: "정확하게 명세하고, 정확하게 구현하고, 정확하게 추적"
```

| 차원 | OMC | HITL | 수렴 방향 |
|------|-----|------|----------|
| 인간 개입 | 최소, 선택적 | 매 단계 필수 | HITL이 "자동 승인 가능한 전환"을 정의하면 마찰 감소 |
| 상태 관리 | 모드별 분산 | 단일 중앙 집중 | HITL의 중앙 집중이 감사에 유리 |
| 강제 방식 | 위임 모델 (누가 쓰는가) | 단계 모델 (언제 쓰는가) | **두 축을 결합**: "이 단계에서 이 에이전트만 이 파일을 수정 가능" |
| 추적성 | 실행 흐름 (what happened) | 요구사항 체인 (why it exists) | HITL에 실행 흐름 추적 추가 → 사후 감사 강화 |
| 검증 | 빌드/테스트/린트 자동 | 테스트 + 인간 승인 | Gate 패턴으로 자동 검증 + 인간 승인 결합 |

### 핵심 인사이트

> **OMC는 "막지 않되 추적한다", HITL은 "추적하되 막는다."**
> 최적 해는 **"평소에는 추적하고, 관문에서 막는다"** — 즉, Layer 2(Guide) + Layer 3(Gate) 조합.

code/test phase의 유연성을 유지하면서(OMC식 생산성), verified 전환 시 추적성 완전성을 강제하면(HITL식 엄밀성), 자연스러운 대화형 개발과 ISO 26262 준수를 양립할 수 있다.

---

## 9. 결론

현재 시스템은 **양 끝(spec, verified)은 단단하지만 중간(code, test)이 느슨하다.** 이 느슨함은 fix loop의 효율성을 위해 의도된 것이나, 추적성 체인을 파괴하는 부작용이 있다.

제안하는 3-Layer 아키텍처로:
1. **Guard**: src/ 수정 시 자동 backward 전환 → 상태 머신 정합성 유지
2. **Guide**: @tc 경고 + change-log → LLM 행동 유도 + 사후 감사
3. **Gate**: verified 전환 시 전수 검사 → 추적성 미충족 시 차단

이 세 레이어를 P0/P1 우선순위로 구현하면, **기존 대화 흐름을 깨지 않으면서** ISO 26262 Part 6 §9.4의 요구사항 추적성과 Part 8 §8.7의 변경 관리를 충족할 수 있다.
