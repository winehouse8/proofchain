---
name: reset
description: "Reset HITL process state and artifacts. Deletes specs, test cases, traceability, SYSTEM-CONTEXT.md, and resets hitl-state.json to empty areas/log while preserving project config and framework engine. Use when user says 초기화, reset, 리셋, clean, or /reset. Does NOT delete src/ or tests/ unless --full flag is given."
allowed-tools: Read, Bash, Write, Edit, AskUserQuestion
argument-hint: "[--full to also delete src/ and tests/]"
---

# HITL Reset

프로세스 상태와 산출물을 초기화한다. 프레임워크 엔진은 유지.

## Scope

| 대상 | 기본 동작 | --full |
|------|----------|--------|
| `.omc/hitl-state.json` areas/log | 비움 | 비움 |
| `.omc/specs/*` | 삭제 | 삭제 |
| `.omc/test-cases/*` | 삭제 | 삭제 |
| `.omc/traceability/*` | 삭제 | 삭제 |
| `.omc/SYSTEM-CONTEXT.md` | 삭제 | 삭제 |
| `src/*` | **유지** | 삭제 |
| `tests/*` | **유지** | 삭제 |
| `.omc/HITL.md` | 유지 | 유지 |
| `.claude/` | 유지 | 유지 |
| `CLAUDE.md` | 유지 | 유지 |

## Workflow

### 1. Current State Summary

`.omc/hitl-state.json`을 읽고 초기화 대상을 요약한다:

```
=== 초기화 대상 ===
Areas: CP(verified/c1), CV(code/c2), WR(test/c1)
Specs: 3 files
Test Cases: 3 files
Traceability: 1 file
SYSTEM-CONTEXT.md: exists
Log entries: 15
Mode: 기본 (.omc/ 산출물만)
```

### 2. Confirmation

사람에게 확인을 요청한다. **되돌릴 수 없는 작업**이므로 반드시 확인.

### 3. Execution

**CRITICAL — 실행 순서**: hook이 `.omc/hitl-state.json`을 읽어 phase를 검사하므로, 이 파일을 먼저 삭제해야 나머지 보호 경로의 삭제가 허용된다.

```
Step 1: project 설정 백업 (jq '.project' 로 추출, 변수에 보관)
Step 2: rm .omc/hitl-state.json          ← 보호 경로 아님 → 허용
Step 3: rm .omc/specs/*                  ← STATE 없음 → hook 통과
Step 4: rm .omc/test-cases/*             ← STATE 없음 → hook 통과
Step 5: rm .omc/traceability/*           ← STATE 없음 → hook 통과
Step 6: rm .omc/SYSTEM-CONTEXT.md        ← STATE 없음 → hook 통과
Step 7: Write fresh hitl-state.json      ← STATE 없음 → hook 통과

(--full 인 경우)
Step 8: rm -rf src/*                     ← STATE 없음 → hook 통과
Step 9: rm -rf tests/unit/* tests/component/* tests/e2e/* tests/visual/*
```

Fresh hitl-state.json 구조:

```json
{
  "project": { ... },
  "areas": {},
  "log": []
}
```

`project` 섹션은 Step 1에서 백업한 값을 그대로 사용한다.
단, `system_context` 필드는 `null`로 설정한다 (파일이 삭제되었으므로).

### 4. Verification

삭제 결과를 확인한다:
- `.omc/specs/` 비어있는지
- `.omc/test-cases/` 비어있는지
- `.omc/traceability/` 비어있는지
- `.omc/SYSTEM-CONTEXT.md` 삭제되었는지
- `hitl-state.json`이 유효한 JSON이고 `areas: {}, log: []`인지
- `hitl-state.json`의 `project.system_context`가 `null`인지

### 5. Summary

```
=== 초기화 완료 ===
삭제됨:
  .omc/specs/              N files
  .omc/test-cases/         M files
  .omc/traceability/       K files
  .omc/SYSTEM-CONTEXT.md   1 file
  hitl-state areas         X areas, Y log entries

유지됨:
  .omc/HITL.md
  .claude/ (hooks, skills, settings)
  src/ (Z files)
  tests/ (W files)

→ /ears-spec 으로 새 영역을 시작하세요.
```
