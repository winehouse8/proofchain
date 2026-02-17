---
name: reset
description: "Reset project to framework-only state. Deletes all HITL artifacts (specs, TCs, traceability), source code, tests, npm deps, git tags, and resets hitl-state.json to generic template. Use when user says 초기화, reset, 리셋, clean, or /reset. Use --keep-code to preserve src/ and tests/."
allowed-tools: Read, Bash, Write, Edit, AskUserQuestion
argument-hint: "[--keep-code to preserve src/ and tests/]"
---

# HITL Reset

프로젝트를 프레임워크만 남긴 초기 상태로 되돌린다. 기본 동작은 **전체 초기화**.

## Scope

| 대상 | 기본 동작 | --keep-code |
|------|----------|-------------|
| `.omc/hitl-state.json` areas/log | 비움 (제네릭 템플릿) | 비움 (project 설정 유지) |
| `.omc/hitl-state.json` project | 제네릭 템플릿으로 리셋 | **유지** |
| `.omc/specs/*` | 삭제 | 삭제 |
| `.omc/test-cases/*` | 삭제 | 삭제 |
| `.omc/traceability/*` | 삭제 | 삭제 |
| `.omc/SYSTEM-CONTEXT.md` | 삭제 | 삭제 |
| `.omc/.phase-snapshot.json` | 삭제 | 삭제 |
| `src/*` | 삭제 | **유지** |
| `tests/*` | 삭제 | **유지** |
| `package.json`, `package-lock.json` | 삭제 | **유지** |
| `node_modules/` | 삭제 | **유지** |
| git tags (`*-verified-*`) | 삭제 | 삭제 |
| `.omc/HITL.md` | 유지 | 유지 |
| `.claude/` | 유지 | 유지 |
| `CLAUDE.md` | 유지 | 유지 |
| `README.md` | 유지 | 유지 |
| `.gitignore` | 유지 | 유지 |

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
src/: 5 files
tests/: 8 files
package.json: exists
node_modules/: exists
Git tags: CP-verified-c1, CV-verified-c1
Mode: 전체 초기화 (프레임워크만 남김)
```

### 2. Confirmation

사람에게 확인을 요청한다. **되돌릴 수 없는 작업**이므로 반드시 확인.

### 3. Execution

**CRITICAL — 실행 순서**: hook이 `.omc/hitl-state.json`을 읽어 phase를 검사하므로, 이 파일을 먼저 삭제해야 나머지 보호 경로의 삭제가 허용된다.

**NOTE**: `rm` 실행 시 zsh의 glob 에러를 방지하기 위해 `rm -rf <dir> && mkdir -p <dir>` 패턴을 사용한다. `rm -f dir/*` 는 빈 디렉토리에서 실패할 수 있다.

```
Step 1: project 설정 백업 (jq '.project' 로 추출, 변수에 보관)
        --keep-code 시에만 사용. 기본 모드에서는 제네릭 템플릿 사용.
Step 2: rm .omc/hitl-state.json          ← 보호 경로 아님 → 허용
Step 3: rm -rf .omc/specs && mkdir -p .omc/specs
Step 4: rm -rf .omc/test-cases && mkdir -p .omc/test-cases
Step 5: rm -rf .omc/traceability && mkdir -p .omc/traceability
Step 6: rm -f .omc/SYSTEM-CONTEXT.md
Step 7: rm -f .omc/.phase-snapshot.json

(기본 모드 — 전체 초기화)
Step 8:  rm -rf src && mkdir -p src
Step 9:  rm -rf tests && mkdir -p tests/unit tests/component tests/e2e tests/visual
Step 10: rm -f package.json package-lock.json
Step 11: rm -rf node_modules

(git tags 정리)
Step 12: git tag -l '*-verified-*' 로 태그 목록 확인, 있으면 전부 삭제

(hitl-state.json 재생성)
Step 13: Write fresh hitl-state.json
```

**기본 모드** fresh hitl-state.json (제네릭 템플릿):

```json
{
  "project": {
    "code": "",
    "name": "",
    "frameworks": {
      "unit": "",
      "component": "",
      "e2e": "",
      "visual": ""
    },
    "system_context": null,
    "paths": {
      "specs": ".omc/specs/",
      "test_cases": ".omc/test-cases/",
      "traceability": ".omc/traceability/",
      "source": "src/",
      "tests": {
        "unit": "tests/unit/",
        "component": "tests/component/",
        "e2e": "tests/e2e/",
        "visual": "tests/visual/"
      }
    }
  },
  "areas": {},
  "log": []
}
```

**--keep-code 모드**: `project` 섹션은 Step 1에서 백업한 값을 그대로 사용한다.
단, `system_context` 필드는 `null`로 설정한다 (파일이 삭제되었으므로).

### 4. Verification

삭제 결과를 확인한다:
- `.omc/specs/` 비어있는지
- `.omc/test-cases/` 비어있는지
- `.omc/traceability/` 비어있는지
- `.omc/SYSTEM-CONTEXT.md` 삭제되었는지
- `.omc/.phase-snapshot.json` 삭제되었는지
- `hitl-state.json`이 유효한 JSON이고 `areas: {}, log: []`인지
- 기본 모드: `hitl-state.json`의 `project.code`가 빈 문자열인지
- --keep-code 모드: `hitl-state.json`의 `project.system_context`가 `null`인지
- 기본 모드: `src/`, `tests/`가 빈 디렉토리인지
- 기본 모드: `package.json`, `node_modules/` 삭제되었는지
- git tags에 `*-verified-*` 패턴이 없는지

### 5. Summary

```
=== 초기화 완료 ===
삭제됨:
  .omc/specs/              N files
  .omc/test-cases/         M files
  .omc/traceability/       K files
  .omc/SYSTEM-CONTEXT.md   (있었으면 삭제)
  .omc/.phase-snapshot.json
  hitl-state areas         X areas, Y log entries
  src/                     A files
  tests/                   B files
  package.json + lock      삭제
  node_modules/            삭제
  git tags                 T tags

유지됨:
  .omc/HITL.md
  .claude/ (hooks, skills, settings)
  CLAUDE.md
  README.md
  .gitignore

→ 프로젝트 설정 후 /ears-spec 으로 새 영역을 시작하세요.
```
