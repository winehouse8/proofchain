# 연구 보고서: proofchain 강제 아키텍처 개선 방안

> **작성일**: 2026-02-20
> **목적**: 현재 프레임워크의 구조적 한계를 식별하고, oh-my-claudecode 등 외부 참조 + Claude Code API 역량을 기반으로 개선 방안을 제시
> **조사 범위**: oh-my-claudecode v4.2.15, Claude Code Hooks/MCP/Skills 공식 문서, ISO 26262 Part 8 도구 자격 요건

---

## 1. 현재 프레임워크는 어떻게 동작하는가

### 1.1 강제 아키텍처 요약

proofchain의 전체 강제 메커니즘은 **단 하나의 PreToolUse hook** (`check-phase.sh`)에 의존한다.

```
                    차단 가능?    역할
                    ─────────    ────
check-phase.sh      ✅ YES      유일한 차단자. Phase별 파일 접근 + verified gate
trace-change.sh     ❌ NO       PostToolUse. 경고 + 로그만
artifact-commit.sh  ❌ NO       PostToolUse. git commit만
phase-commit.sh     ❌ NO       PostToolUse. git commit + tag만
restore-state.sh    ❌ NO       SessionStart. 보고만
checkpoint.sh       ❌ NO       PreCompact. 상태 보존만
```

**핵심 사실**: PostToolUse hook은 도구가 이미 실행된 후에 발동하므로, 절대로 차단할 수 없다. "경고"와 "기록"만 가능하다.

### 1.2 무엇이 기계적으로 강제되는가

| 강제 항목 | 메커니즘 | 우회 가능? |
|-----------|---------|-----------|
| Phase별 파일 접근 (src/, specs/, tests/) | check-phase.sh PreToolUse | 직접 우회 어려움 |
| .claude/ 자기 보호 (Edit/Write) | check-phase.sh PreToolUse | 직접 우회 어려움 |
| Verified gate (@tc/@req, TC 스키마, baseline 불변, reentry 로그) | check-phase.sh PreToolUse | 직접 우회 어려움 |
| 자동 git commit | artifact-commit.sh, phase-commit.sh PostToolUse | 우회 불필요 (기록일 뿐) |

### 1.3 무엇이 강제되지 않는가 (적대적 시나리오)

| # | 시나리오 | 현재 방어 | 위험도 |
|---|---------|----------|--------|
| **A1** | AI가 hitl-state.json 자유 수정 → phase 건너뛰기 (spec→code) | phase-commit.sh 경고만 (차단 불가) | **High** |
| **A2** | `git tag -d CP-verified-c1` → Check 4 baseline 불변 무력화 | 방어 없음 | **High** |
| **A3** | `git checkout HEAD~5 -- .claude/hooks/check-phase.sh` → 자기 보호 우회 | v3.3.1 git 허용으로 통과 | **Critical** |
| **A4** | 빈 테스트에 @tc/@req 어노테이션만 → verified gate 통과 | 방어 없음 (어노테이션 존재만 확인) | **High** |
| **A5** | TC 0개 상태에서 verified 전환 | `active_tc_ids` 빈 문자열 → gate 즉시 return 0 | **Medium** |
| **A6** | 스킬 미사용 → TC 격리, 회귀 테스트 등 전부 우회 | 방어 없음 (스킬은 사용자가 호출) | **Medium** |
| **A7** | tc phase에서 src/ Read → TC 격리 위반 | Read 도구가 hook matcher에 없음 | **Medium** |

---

## 2. Claude Code API가 실제로 할 수 있는 것

### 2.1 PreToolUse가 차단할 수 있는 도구 (현재 미활용)

현재 `check-phase.sh`의 matcher는 `Edit|Write|Bash`만 대상으로 한다. 하지만 Claude Code PreToolUse는 **모든 내장 도구**를 차단할 수 있다:

```
현재 차단 대상:     Edit, Write, Bash
추가 가능:          Read, Glob, Grep, Task, WebFetch, WebSearch, NotebookEdit
MCP 도구:           mcp__<server>__<tool> 패턴으로 매칭 가능
```

**TC 격리(A7)는 기술적으로 강제 가능하다.** matcher를 `Edit|Write|Bash|Read|Glob|Grep`으로 확장하고, tc phase에서 src/ Read를 차단하면 된다. 이전 감사에서 "Claude Code API가 Read 차단을 지원하지 않아" 라고 했지만, 이는 **사실과 다르다**.

### 2.2 PreToolUse의 추가 기능

| 기능 | 설명 | 활용 가능성 |
|------|------|------------|
| **permissionDecision: "deny"** | JSON으로 구조화된 차단 + 사유 전달 | 현재 exit 2 대신 사용 가능 |
| **updatedInput** | 도구 입력을 실행 전에 수정 | 파일 경로 정규화, 안전 플래그 추가 |
| **additionalContext** | Claude 컨텍스트에 추가 정보 주입 | 차단 시 다음 행동 가이드 |
| **도구 매칭 패턴** | 정규식으로 MCP 도구까지 매칭 | `mcp__.*` 로 MCP 도구 제어 가능 |

### 2.3 Stop 훅 (미활용)

`Stop` 훅은 Claude가 응답을 마칠 때 발동한다. exit 2를 반환하면 **Claude가 계속 작업하도록 강제**할 수 있다. 이를 활용하면:

- 테스트 실행 여부를 확인하고, 미실행 시 계속 작업 지시
- Todo 리스트의 미완료 항목 확인
- Verified 전환 전 최종 검증 강제

### 2.4 Hook 스냅샷 보안

Claude Code는 세션 시작 시 hook 설정을 스냅샷하여 세션 내내 사용한다. 세션 중 hook이 수정되면 사용자에게 경고하고 `/hooks` 메뉴에서 검토를 요구한다. 이는 A3(hook 복원)에 대한 **부분적 방어**가 된다 — 현재 세션에서는 적용되지 않지만, 다음 세션에서 변경된 hook이 활성화될 수 있다.

### 2.5 알려진 제약

- **Hook 자기 수정 방지 불가**: Claude Code GitHub Issue #11226. Edit/Write로 `.claude/` 파일을 수정하는 것을 `permissions.deny`로 막으려 해도 작동하지 않음. "Not Planned"으로 닫힘.
- **context:fork 불안정**: Issue #17283. Skill 도구로 호출 시 fork가 무시되고 메인 컨텍스트에서 실행될 수 있음.
- **Bash 이스케이프**: 변수 확장, 인코딩, 다단계 명령으로 패턴 매칭 우회 가능.

---

## 3. oh-my-claudecode에서 배울 것

### 3.1 OMC 아키텍처 개요

oh-my-claudecode (OMC)는 **멀티 에이전트 오케스트레이션 시스템**이다. 30개 특화 에이전트를 지휘하는 conductor 패턴으로, proofchain과는 목적이 다르다 (생산성 vs 안전 준수). 하지만 여러 설계 패턴이 참고할 만하다.

### 3.2 차용 가능한 패턴

#### 패턴 1: Verification Protocol (검증 프로토콜)

OMC는 완료 판정 전에 7가지 증거를 요구한다:

```
BUILD         → build_success (빌드 통과)
TEST          → test_pass (테스트 통과)
LINT          → lint_clean (린트 통과)
FUNCTIONALITY → functionality_verified (기능 검증)
ARCHITECT     → architect_approval (아키텍트 승인)
TODO          → todo_complete (할 일 완료)
ERROR_FREE    → error_free (에러 없음)
```

각 증거는 **5분 이내의 신선한(fresh) 명령 출력**이어야 한다. 오래된 캐시된 결과는 무효.

**proofchain에 적용**: verified gate에서 "테스트 통과 증거"를 요구할 수 있다. 예를 들어:
- `.omc/test-results/{area}-latest.json`에 최근 테스트 결과를 기록
- verified gate에서 이 파일의 타임스탬프와 결과를 검증
- 이것으로 A4(빈 테스트) 시나리오를 부분적으로 방어

#### 패턴 2: Orchestrator Enforcement (오케스트레이터 제한)

OMC에서 오케스트레이터(지휘자)는 **직접 코드를 수정할 수 없다**. 코드 수정은 반드시 하위 에이전트에 위임해야 한다. 이를 PreToolUse hook으로 강제한다.

**proofchain에 적용**: 직접적으로는 해당 없음 (proofchain은 단일 에이전트). 하지만 "특정 작업은 특정 스킬을 통해서만" 패턴으로 변환할 수 있다.

#### 패턴 3: Agent Tool Restrictions (에이전트 도구 제한)

OMC 에이전트는 YAML frontmatter로 `disallowedTools`를 선언한다:

```yaml
# architect 에이전트: Write/Edit 금지 (읽기 전용)
disallowedTools: Write, Edit
```

**proofchain에 적용**: 스킬 frontmatter에 도구 제한을 선언하고, 스킬별 scoped hook으로 강제할 수 있다. 예: `/test-gen-design` 스킬에 `Read` 도구의 src/ 접근 차단 hook 부착.

#### 패턴 4: Stop Hook 기반 완료 검증

OMC의 `Stop` hook은 미완료 todo가 있으면 Claude를 계속 작업시킨다.

**proofchain에 적용**: `Stop` hook에서 현재 영역의 phase와 테스트 상태를 확인하고, "테스트 미실행 시 안내" 또는 "verified 전환 전 체크리스트 출력" 등에 활용 가능.

#### 패턴 5: Compaction-Resilient Memory (압축 내성 메모리)

OMC의 notepad 시스템은 컨텍스트 압축을 살아남는 우선순위 메모리를 제공한다.

**proofchain에 적용**: 현재 `checkpoint.sh`가 이 역할을 부분적으로 하지만, 더 구조화된 형태로 개선 가능. 현재 area/phase/cycle 정보만 보존하는데, 진행 중인 작업의 핵심 컨텍스트도 보존하면 압축 후 워크플로우 연속성이 향상됨.

### 3.3 차용하지 않을 것

| OMC 기능 | 이유 |
|----------|------|
| 멀티 에이전트 오케스트레이션 | proofchain은 단일 에이전트 + 인간 루프. 복잡도 대비 효용 낮음 |
| MCP 기반 외부 AI (Codex, Gemini) | ISO 26262 준수에서 외부 AI 의존은 도구 자격 문제를 복잡하게 만듦 |
| 자동 스킬 학습 | 안전 프로세스에서 학습된 행동은 검증이 필요하여 자동 적용 부적합 |
| HUD 상태 표시줄 | 좋은 UX이지만 핵심 강제와 무관 |
| npm 패키지 배포 | proofchain은 git 기반 템플릿 배포로 충분 |

---

## 4. ISO 26262가 실제로 요구하는 것

### 4.1 도구 자격의 현실

ISO 26262 Part 8 clause 11은 **도구 신뢰 수준(TCL)**을 TI(Tool Impact) × TD(Tool error Detection) 매트릭스로 결정한다:

```
         TD1 (높음)    TD2 (중간)    TD3 (낮음)
TI1      TCL1          TCL1          TCL1
TI2      TCL1          TCL2          TCL3
```

- **TCL1**: 자격 불요. 추가 조치 없음.
- **TCL2**: 자격 필요. 방법 1b(개발 프로세스 평가) 또는 1c(검증).
- **TCL3**: 자격 필요. 더 엄격한 검증.

**proofchain + Claude Code의 분류:**
- **TI**: TI2 (AI가 오류를 도입하거나 탐지 실패할 수 있음) — 논쟁의 여지 없음
- **TD**: 인간 리뷰(phase 전환 승인) + 자동 테스트(verified gate) + git 감사 = **TD1~TD2 주장 가능**
- **결과**: TI2 + TD1 = **TCL1** (자격 불요) — **인간 리뷰가 충분히 신뢰할 수 있다면**

### 4.2 우리가 과도하게 해석한 것

| 주장 | 실제 요건 | 차이 |
|------|----------|------|
| "cycle > 1에서 전체 회귀 필수 (§9.4.6)" | 변경 영향 분석 기반 **선택적** 회귀도 허용 | 전체 회귀는 보수적 선택이지 의무 아님 |
| "TC 격리 = §9.4.3 충분한 독립성" | §9.4.3은 **I1 (다른 사람의 리뷰)** 만 요구 | TC 격리는 요구 수준을 초과하는 설계 선택 |
| "도구가 tamper-proof이어야" | ISO 26262는 **어디에서도** tamper-proof을 요구하지 않음 | 정확한 작동에 대한 "신뢰"를 요구할 뿐 |
| "per-artifact git commit (§7.4.5)" | §7.4는 형상관리를 요구하지만 커밋 단위를 지정하지 않음 | 좋은 실천이나 ISO 의무 아님 |

### 4.3 우리가 놓치고 있는 것

| 누락 | ISO 요건 | 권고 |
|------|----------|------|
| **도구 분류 문서** | Part 8 §11.4.3 — TI, TD, TCL을 문서화한 공식 보고서 | 작성 필요 |
| **자격 증거** | TCL2/3이면 방법 1a~1d 중 하나의 증거 | TD1 주장이 통하면 TCL1이라 불요 |
| **대상 ASIL 미정의** | ASIL에 따라 자격 요건 강도가 달라짐 | 명시 필요 |

### 4.4 현실적 위치 평가

```
ISO 26262 도구 자격 스펙트럼:

[전혀 미준수] ─────────────── [proofchain 현재] ─── [완전 준수]
                                     ↑
                    기계적 강제 다수 + 인간 게이트
                    하지만 공식 문서(TI/TD 분류) 부재
                    + 적대적 시나리오 방어 일부 부재
```

핵심 인사이트: **proofchain의 엔지니어링은 실질적으로 훌륭하다.** 하지만 ISO 26262 "준수"를 주장하려면 엔지니어링 외에 **공식 문서**가 필요하고, 현재의 적대적 시나리오(A1~A7)는 TD1 주장을 약화시킬 수 있다.

---

## 5. 개선 제안

### Tier 1: 즉시 수정 (적대적 시나리오 차단)

#### T1-1: Phase 전환 유효성 검증 (A1 방어)

**문제**: hitl-state.json을 수정하여 spec→code 같은 비정상 전환이 가능하다. phase-commit.sh가 경고하지만 차단 불가.

**해결**: check-phase.sh에서 hitl-state.json Write/Edit 시 **전환 유효성을 검증**한다.

```
허용 전환 맵:
  spec     → tc (forward)
  tc       → code (forward), spec (backward)
  code     → test (forward), spec/tc (backward)
  test     → verified (forward+gate), spec/tc/code (backward)
  verified → spec/tc/code (reentry, cycle++)

맵에 없는 전환 → BLOCK
```

**효과**: AI가 phase를 임의로 건너뛸 수 없음. G2 강화.

#### T1-2: 파괴적 git 명령 차단 (A2, A3 방어)

**문제**: `git tag -d`로 baseline 태그 삭제, `git checkout -- .claude/`로 hook 복원 가능.

**해결**: check-phase.sh Bash 핸들러에서 **특정 파괴적 git 명령을 차단**:

```bash
# 파괴적 git 명령 차단
if echo "$CMD" | grep -qE '^\s*git\s' && \
    echo "$CMD" | grep -qE '\b(tag\s+-d|tag\s+--delete|checkout\s+.*\.claude/|reset\s+--hard|push\s+--force)\b'; then
  echo "BLOCKED: 파괴적 git 명령이 차단되었습니다." >&2
  exit 2
fi
```

**효과**: A2(태그 삭제)와 A3(hook 복원) 차단. 일반 git 명령(add, commit, push, status, log, diff)은 허용 유지.

#### T1-3: TC 존재 검증 강화 (A5 방어)

**문제**: active TC가 0개이면 verified gate가 즉시 통과 (`return 0`).

**해결**: TC가 없으면 차단:

```bash
[ -z "$active_tc_ids" ] && {
  echo "BLOCKED: ${area} — active TC가 0개입니다. TC를 먼저 작성하세요." >&2
  return 1
}
```

**효과**: 빈 TC로 verified 도달 불가. G2 강화.

### Tier 2: 중기 개선 (TC 격리 + 테스트 검증)

#### T2-1: Read/Glob/Grep 차단으로 TC 격리 강제 (A7 방어)

**문제**: tc phase에서 AI가 src/를 Read할 수 있어 TC 격리가 프로세스에만 의존.

**해결**: settings.json의 matcher를 `Edit|Write|Bash|Read|Glob|Grep`으로 확장. check-phase.sh에 Read/Glob/Grep 핸들러 추가:

```bash
if [ "$TOOL" = "Read" ] || [ "$TOOL" = "Glob" ] || [ "$TOOL" = "Grep" ]; then
  # tc phase에서 src/ Read 차단
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // empty')
  case "$FILE_PATH" in
    */src/*|src/*)
      # 이 영역이 tc phase인지 확인
      # tc phase이면 차단
      ;;
  esac
fi
```

**주의사항**: Read 차단은 모든 Read 호출에 hook이 발동하므로 **성능 영향**이 있다. tc phase에서만 src/ 접근을 차단하는 최소 범위로 구현.

**효과**: TC 격리가 기계적으로 강제됨. ISO 26262 §9.4.3 독립성이 프로세스 의존에서 기계적 강제로 승격. TD1 주장 강화.

#### T2-2: 테스트 실행 증거 요구 (A4 부분 방어)

**문제**: 빈 테스트도 @tc/@req만 있으면 verified gate 통과.

**해결**: OMC의 Verification Protocol에서 착안. 테스트 실행 결과 파일을 verified gate에서 검증:

```
1. /test-gen-code 스킬이 테스트 실행 후 .omc/test-results/{area}.json 생성
   { "timestamp": "...", "passed": 12, "failed": 0, "area": "CP" }

2. verified gate에서:
   - 결과 파일 존재 확인
   - timestamp가 현재로부터 30분 이내인지 확인
   - failed == 0 인지 확인
   - passed > 0 인지 확인
```

**한계**: AI가 결과 파일을 직접 생성하면 우회 가능. 하지만 이는 "실수 방지"이지 "악의적 우회 방지"가 아니다. ISO 26262는 tamper-proof을 요구하지 않으므로, 이 수준이면 TD1 주장에 충분.

### Tier 3: 장기 개선 (아키텍처 수준)

#### T3-1: Stop 훅 활용 — 완료 전 검증

현재 미사용인 `Stop` 훅을 추가하여, Claude가 응답을 마칠 때 체크리스트를 확인:

```
Stop hook 발동:
  → 현재 영역의 phase가 test이고 모든 테스트 통과?
    → "verified 전환을 사람에게 제안하세요" 안내 주입
  → hitl-state.json이 수정되었지만 log 항목이 없다면?
    → "log 기록을 추가하세요" 안내 주입
```

#### T3-2: UserPromptSubmit 훅 — 워크플로우 가이드

세션 중 사용자 입력을 가로채서 현재 phase에 맞는 스킬을 안내:

```
사용자: "테스트 짜줘"
  → 현재 phase가 spec이면:
    → "현재 spec phase입니다. 먼저 /ears-spec으로 SPEC을 완성하세요." 주입
```

#### T3-3: 스킬 scoped hook — TC 격리 강화

`/test-gen-design` 스킬에 scoped hook을 부착하여, 스킬 실행 중에만 추가적인 src/ Read 차단을 적용:

```yaml
# test-gen-design 스킬 frontmatter
hooks:
  PreToolUse:
    - matcher: "Read|Glob|Grep"
      hooks:
        - type: command
          command: ".claude/hooks/tc-isolation.sh"
```

**주의**: `context: fork`에 알려진 버그(#17283)가 있어 fork가 무시될 수 있다. scoped hook은 fork와 독립적으로 동작하므로 더 신뢰할 수 있는 격리 수단.

---

## 6. 개선 후 예상 상태

### 적대적 시나리오 방어 매트릭스

```
            현재        Tier 1 후     Tier 2 후     Tier 3 후
            ────        ─────────     ─────────     ─────────
A1 Phase 건너뛰기  ❌ 미방어     ✅ 차단        ✅ 차단        ✅ 차단
A2 태그 삭제       ❌ 미방어     ✅ 차단        ✅ 차단        ✅ 차단
A3 Hook 복원      ❌ 미방어     ✅ 차단        ✅ 차단        ✅ 차단
A4 빈 테스트      ❌ 미방어     ❌ 미방어      ⚠️ 부분 방어    ⚠️ 부분 방어
A5 TC 0개         ❌ 미방어     ✅ 차단        ✅ 차단        ✅ 차단
A6 스킬 미사용    ❌ 미방어     ❌ 미방어      ❌ 미방어      ⚠️ 안내
A7 TC 격리 위반   ❌ 미방어     ❌ 미방어      ✅ 차단        ✅ 차단
```

### ISO 26262 TD 평가

```
                현재              Tier 1 후          Tier 2 후
                ────              ─────────          ─────────
TI              TI2               TI2                TI2
TD              TD2 (약한 주장)    TD1~TD2            TD1 (강한 주장)
TCL             TCL2              TCL1~TCL2          TCL1
자격 필요?       아마도            아마도 아닌         아니오
```

### 프레임워크 설계 원칙 준수

```
"평소에는 추적하고, 관문에서 막는다"

현재:    추적 ✅ + 관문 부분 차단 ⚠️ (적대적 시나리오 존재)
Tier 1:  추적 ✅ + 관문 강화 ✅ (주요 적대적 시나리오 차단)
Tier 2:  추적 ✅ + 관문 강화 ✅ + 격리 강제 ✅ (TC 격리 + 테스트 증거)
```

---

## 7. 구현 우선순위 권고

| 순위 | 항목 | 수정 파일 | 효과 | 난이도 |
|------|------|----------|------|--------|
| **1** | T1-2: 파괴적 git 차단 | check-phase.sh | A2+A3 차단 (critical 해소) | 낮음 |
| **2** | T1-1: Phase 전환 유효성 | check-phase.sh | A1 차단 | 중간 |
| **3** | T1-3: TC 존재 검증 | check-phase.sh | A5 차단 | 낮음 |
| **4** | T2-1: TC 격리 Read 차단 | check-phase.sh + settings.json | A7 차단, TD1 강화 | 중간 |
| **5** | T2-2: 테스트 증거 요구 | check-phase.sh + /test-gen-code | A4 부분 방어 | 중간 |
| **6** | T3-1: Stop 훅 | 신규 hook | UX 향상 | 중간 |
| **7** | T3-2: UserPromptSubmit | 신규 hook | UX 향상 | 중간 |

Tier 1 (1~3번)은 check-phase.sh 한 파일 수정으로 완료 가능. 가장 높은 ROI.

---

## 8. 결론

### 현재 프레임워크는 완벽한 ISO 26262 준수를 보장하는가?

**아니다.** 3가지 이유:

1. **적대적 시나리오 방어 부재**: hitl-state.json 자유 수정, git 태그 삭제, hook 복원 등으로 모든 강제 메커니즘을 우회할 수 있다.
2. **공식 문서 부재**: ISO 26262는 도구 분류 보고서(TI/TD/TCL)를 요구하지만, proofchain에는 없다.
3. **테스트 실행 검증 부재**: 어노테이션 존재만 확인하고, 실제 테스트 실행/통과를 검증하지 않는다.

### 그러면 불가능한가?

**아니다.** ISO 26262는 도구가 tamper-proof일 것을 요구하지 않는다. "충분한 신뢰"를 요구할 뿐이다. HITL 모델에서 인간이 모든 전환을 승인하고, 기계적 가드레일이 실수를 잡아주면, **TD1 (높은 탐지 신뢰)** 를 주장할 수 있다.

Tier 1 수정만으로도 주요 적대적 시나리오가 차단되어 TD1 주장이 크게 강화된다. Tier 2까지 가면 TC 격리와 테스트 증거까지 기계적으로 강제되어, 프로세스 의존 항목이 거의 사라진다.

### 핵심 교훈

> **hook + JSON + git은 "보안 경계"가 아니라 "프로세스 가드레일"이다.**
> ISO 26262가 요구하는 것은 보안 경계가 아니라 프로세스 가드레일 + 인간 감독이다.
> 따라서 현재 아키텍처는 올바른 방향이며, 적대적 시나리오를 추가로 차단하면 충분히 강한 TD1 주장이 가능하다.

---

## 참조

- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) — 멀티 에이전트 오케스트레이션, Verification Protocol
- [Claude Code Hooks Reference](https://docs.anthropic.com/en/docs/claude-code/hooks) — PreToolUse 전체 도구 차단 가능
- [Claude Code Issue #11226](https://github.com/anthropics/claude-code/issues/11226) — Hook 자기 수정 방지 불가 (Not Planned)
- [Claude Code Issue #17283](https://github.com/anthropics/claude-code/issues/17283) — context:fork 무시 버그
- ISO 26262-8:2018 clause 11 — 도구 자격, TCL 매트릭스
- [GitHub CodeQL ISO 26262 Qualification](https://github.com/github/codeql-coding-standards/blob/main/docs/iso_26262_tool_qualification.md) — 실제 도구 자격 사례
- [Siemens Verification Horizons](https://blogs.sw.siemens.com/verificationhorizons/2022/04/13/clearing-the-fog-of-iso-26262-tool-qualification/) — TCL 결정 실무
