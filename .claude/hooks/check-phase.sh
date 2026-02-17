#!/bin/bash
# HITL Phase Guard — PreToolUse Hook
# Gate: Phase 기반 파일 접근 제어 + 자기 보호
# 5-Phase Model: spec, tc, code, test, verified
# Edit/Write: 영역별 정밀 검사, Bash: 휴리스틱 쓰기 감지
#
# exit 0 = 허용, exit 2 = 차단 (+ stderr로 피드백)

set -euo pipefail
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
CWD=$(echo "$INPUT" | jq -r '.cwd')
STATE="$CWD/.omc/hitl-state.json"

# ── Bash 도구: .claude/ 조작 차단 + 보호 경로 쓰기 감지 ──
if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # .claude/ 보호
  if echo "$CMD" | grep -qE '\.claude/'; then
    echo "BLOCKED: .claude/ 디렉토리 조작이 차단되었습니다." >&2
    echo "HITL 훅 설정은 보호됩니다." >&2
    exit 2
  fi

  # 쓰기 연산 감지 (sed -i, 리다이렉트, cp, mv, rm, tee)
  IS_WRITE=false
  echo "$CMD" | grep -qE 'sed\s.*-i' && IS_WRITE=true
  echo "$CMD" | grep -qE '\btee\b' && IS_WRITE=true
  echo "$CMD" | grep -qE '(>[^&]|>>)' && IS_WRITE=true
  echo "$CMD" | grep -qE '\b(cp|mv|rm)\s' && IS_WRITE=true

  if $IS_WRITE && [ -f "$STATE" ]; then
    BASH_SRC=false; BASH_SPEC=false; BASH_TC=false; BASH_TEST=false
    echo "$CMD" | grep -qE '\bsrc/' && BASH_SRC=true
    echo "$CMD" | grep -qE '\.omc/specs/' && BASH_SPEC=true
    echo "$CMD" | grep -qE '\.omc/test-cases/' && BASH_TC=true
    echo "$CMD" | grep -qE '\btests/' && BASH_TEST=true

    if $BASH_SRC || $BASH_SPEC || $BASH_TC || $BASH_TEST; then
      AREAS_JSON=$(jq '.areas // {}' "$STATE" 2>/dev/null)
      AREA_COUNT=$(echo "$AREAS_JSON" | jq 'length')
      [ "$AREA_COUNT" = "0" ] && exit 0
      BLOCKED_PATH=""

      if $BASH_SPEC; then
        CNT=$(echo "$AREAS_JSON" | jq '[to_entries[] | select(.value.phase == "spec")] | length')
        [ "$CNT" = "0" ] && BLOCKED_PATH=".omc/specs/"
      fi
      if $BASH_TC && [ -z "$BLOCKED_PATH" ]; then
        CNT=$(echo "$AREAS_JSON" | jq '[to_entries[] | select(.value.phase == "tc" or .value.phase == "code" or .value.phase == "test")] | length')
        [ "$CNT" = "0" ] && BLOCKED_PATH=".omc/test-cases/"
      fi
      if $BASH_SRC && [ -z "$BLOCKED_PATH" ]; then
        CNT=$(echo "$AREAS_JSON" | jq '[to_entries[] | select(.value.phase == "code" or .value.phase == "test")] | length')
        [ "$CNT" = "0" ] && BLOCKED_PATH="src/"
      fi
      if $BASH_TEST && [ -z "$BLOCKED_PATH" ]; then
        CNT=$(echo "$AREAS_JSON" | jq '[to_entries[] | select(.value.phase == "code" or .value.phase == "test")] | length')
        [ "$CNT" = "0" ] && BLOCKED_PATH="tests/"
      fi

      if [ -n "$BLOCKED_PATH" ]; then
        echo "BLOCKED: Bash 명령이 보호 경로(${BLOCKED_PATH})를 수정하려 합니다." >&2
        echo "활성 phase에서 해당 경로 수정이 허용되지 않습니다." >&2
        echo "reentry를 시작하거나, Edit/Write 도구를 사용하세요." >&2
        exit 2
      fi
    fi
  fi

  exit 0
fi

# ── Edit/Write만 대상 (Read 등 다른 도구는 통과) ──
if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then
  exit 0
fi

# ── 파일 경로 추출 ──
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# ── 자기 보호: .claude/ 수정 차단 ──
case "$FILE_PATH" in
  */.claude/*|*/.claude)
    echo "BLOCKED: .claude/ 디렉토리는 보호됩니다." >&2
    echo "HITL 훅 설정을 수정할 수 없습니다." >&2
    exit 2
    ;;
esac

# ── hitl-state.json이 없으면 통과 ──
[ ! -f "$STATE" ] && exit 0

# ── 보호 대상 판별 ──
IS_SRC=false
IS_SPEC=false
IS_TC=false
IS_TEST=false

case "$FILE_PATH" in
  */src/*)             IS_SRC=true ;;
  */.omc/specs/*)      IS_SPEC=true ;;
  */.omc/test-cases/*) IS_TC=true ;;
  */tests/*)           IS_TEST=true ;;
  *)                   exit 0 ;;  # 보호 대상 아님 → 허용
esac

# ── 영역 phase 수집 ──
AREAS_JSON=$(jq '.areas // {}' "$STATE" 2>/dev/null)
AREA_COUNT=$(echo "$AREAS_JSON" | jq 'length')
[ "$AREA_COUNT" = "0" ] && exit 0

# ── 파일이 속한 영역 찾기 (다중 영역 매핑 지원) ──
TARGET_AREAS=""

# SPEC 파일 → 영역 매핑 (1:1)
if $IS_SPEC; then
  TARGET_AREAS=$(jq -r --arg fp "$FILE_PATH" '
    .areas | to_entries[] | select(.value.spec.file) |
    .value.spec.file as $sf | select($fp | endswith($sf)) |
    .key' "$STATE" 2>/dev/null)
fi

# TC 파일 → 영역 매핑 (1:1)
if $IS_TC; then
  TARGET_AREAS=$(jq -r --arg fp "$FILE_PATH" '
    .areas | to_entries[] | select(.value.tc.file) |
    .value.tc.file as $tf | select($fp | endswith($tf)) |
    .key' "$STATE" 2>/dev/null)
fi

# src/ 파일 → 영역 매핑 (1:N — 공유 파일은 여러 영역에 매핑될 수 있음)
if $IS_SRC; then
  TARGET_AREAS=$(jq -r --arg fp "$FILE_PATH" '
    .areas | to_entries[] |
    select(.value.code.files) |
    select([.value.code.files[] | . as $cf | select($fp | endswith($cf))] | length > 0) |
    .key' "$STATE" 2>/dev/null)
fi

# tests/ 파일 → 경로에서 영역 코드 추출 (tests/unit/CP/ → CP)
if $IS_TEST; then
  TARGET_AREAS=$(echo "$FILE_PATH" | grep -oE 'tests/[^/]+/([A-Z]{2})' | grep -oE '[A-Z]{2}$' || true)
fi

# 영역을 특정할 수 없는 경우 (새 파일 등)
if [ -z "$TARGET_AREAS" ]; then
  # 활성 phase인 영역이 하나라도 있으면 허용
  ACTIVE=$(echo "$AREAS_JSON" | jq '[to_entries[] | select(
    .value.phase == "spec" or
    .value.phase == "tc" or
    .value.phase == "code" or
    .value.phase == "test"
  )] | length')
  if [ "$ACTIVE" -gt 0 ]; then
    exit 0
  fi
  echo "BLOCKED: 파일을 특정 영역에 매핑할 수 없고, 활성 영역이 없습니다." >&2
  echo "reentry 프로세스를 시작하세요." >&2
  exit 2
fi

# ── 모든 매칭 영역의 phase를 검사 (하나라도 차단이면 차단) ──
BLOCKED_AREA=""
BLOCKED_PHASE=""
BLOCKED_CYCLE=""

for AREA in $TARGET_AREAS; do
  PHASE=$(echo "$AREAS_JSON" | jq -r --arg area "$AREA" '.[$area].phase // "unknown"')

  AREA_ALLOWED=false

  if $IS_SPEC; then
    [ "$PHASE" = "spec" ] && AREA_ALLOWED=true
  fi

  if $IS_TC; then
    case "$PHASE" in
      tc|code|test) AREA_ALLOWED=true ;;
    esac
  fi

  if $IS_SRC; then
    case "$PHASE" in
      code|test) AREA_ALLOWED=true ;;
    esac
  fi

  if $IS_TEST; then
    case "$PHASE" in
      code|test) AREA_ALLOWED=true ;;
    esac
  fi

  if ! $AREA_ALLOWED; then
    BLOCKED_AREA="$AREA"
    BLOCKED_PHASE="$PHASE"
    BLOCKED_CYCLE=$(echo "$AREAS_JSON" | jq -r --arg area "$AREA" '.[$area].cycle // 1')
    break
  fi
done

# 모든 영역이 허용이면 통과
if [ -z "$BLOCKED_AREA" ]; then
  exit 0
fi

# ── 차단: 구체적 피드백 ──
AREA_NAME=$(echo "$AREAS_JSON" | jq -r --arg area "$BLOCKED_AREA" '.[$area].name // $area')

if [ "$BLOCKED_PHASE" = "verified" ]; then
  cat >&2 <<EOF
BLOCKED: ${BLOCKED_AREA}(${AREA_NAME}) 영역이 verified 상태입니다. [cycle ${BLOCKED_CYCLE}]

reentry를 시작하세요. 시나리오에 따라 진입점 선택:
  A. 새 기능 / SPEC 오류  → phase를 "spec"으로 (cycle++)
  B. 코드 버그 (SPEC 정확) → phase를 "tc"로 (cycle++)
  C. 테스트 코드 오류      → phase를 "code"로 (cycle++)

hitl-state.json의 해당 area를 변경하세요:
  phase → 진입 phase, cycle → ${BLOCKED_CYCLE}+1,
  cycle_entry → 진입 phase, cycle_reason → 사유
  log에 type, reason, affected_reqs, skip_reason 기록
EOF
else
  echo "BLOCKED: ${BLOCKED_AREA}(${AREA_NAME}) 영역이 ${BLOCKED_PHASE} 상태입니다. [cycle ${BLOCKED_CYCLE}]" >&2
  echo "" >&2
  if $IS_SRC; then
    echo "src/ 수정은 code 또는 test 단계에서만 가능합니다." >&2
    # 공유 파일인 경우 어떤 영역이 차단 원인인지 알려줌
    AREA_COUNT=$(echo "$TARGET_AREAS" | wc -w | tr -d ' ')
    if [ "$AREA_COUNT" -gt 1 ]; then
      echo "이 파일은 여러 영역에 매핑되어 있습니다: $TARGET_AREAS" >&2
      echo "차단 원인 영역: ${BLOCKED_AREA}(${BLOCKED_PHASE})" >&2
    fi
  elif $IS_SPEC; then
    echo ".omc/specs/ 수정은 spec 단계에서만 가능합니다." >&2
  elif $IS_TC; then
    echo ".omc/test-cases/ 수정은 tc, code, test 단계에서만 가능합니다." >&2
  elif $IS_TEST; then
    echo "tests/ 수정은 code 또는 test 단계에서만 가능합니다." >&2
  fi
fi

exit 2
