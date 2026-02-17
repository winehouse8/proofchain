#!/bin/bash
# HITL Phase Guard — PreToolUse Hook (v2.2: Approach A + boundary fix + Bash boundary)
# Gate: Phase 기반 파일 접근 제어 + 자기 보호 + 코드 확장자 검사
# 5-Phase Model: spec, tc, code, test, verified
# Edit/Write: 영역별 정밀 검사 + 코드 확장자 차단
# Bash: 휴리스틱 쓰기 감지 + 코드 확장자 휴리스틱
#
# Approach A: 관리 경로(src/, tests/) 외부의 코드 파일 쓰기를 차단
#   - Edit/Write: 정확한 확장자 매칭 (file_path 기반)
#   - Bash: 휴리스틱 패턴 매칭 (명령어 문자열 기반, 오탐 가능)
#   - 예외: 루트 설정 파일 (*.config.*, *.setup.*, .*rc, .*rc.*)
#
# exit 0 = 허용, exit 2 = 차단 (+ stderr로 피드백)

set -euo pipefail
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
CWD=$(echo "$INPUT" | jq -r '.cwd')
STATE="$CWD/.omc/hitl-state.json"

# ── Bash 휴리스틱용 코드 확장자 패턴 (주요 언어만, 짧은 버전) ──
BASH_CODE_EXT='ts|tsx|js|jsx|mjs|cjs|py|rs|go|c|h|cpp|hpp|cs|java|kt|scala|swift|dart|rb|php|lua|sh|bash|ex|hs|vue|svelte|css|scss|sass|html|htm|sql|graphql|wasm|zig|nim|jl|cr|elm|sol'

# ── phase별 가능한 전환 출력 ──
print_transitions() {
  local phase="$1"
  case "$phase" in
    spec)
      cat >&2 <<'TRANSITIONS'
현재 spec 단계에서 가능한 전환:
  → forward → tc : SPEC 완료 + 사람 승인 → /test-gen-design
TRANSITIONS
      ;;
    tc)
      cat >&2 <<'TRANSITIONS'
현재 tc 단계에서 가능한 전환:
  → forward  → code : TC 승인 → 코딩 시작
  → backward → spec : SPEC 수정 필요 → /ears-spec
TRANSITIONS
      ;;
    code)
      cat >&2 <<'TRANSITIONS'
현재 code 단계에서 가능한 전환:
  → forward  → test : 코딩 완료 → /test-gen-code
  → backward → spec : SPEC 문제 발견 → /ears-spec
  → backward → tc   : TC 보강 필요 → /test-gen-design
TRANSITIONS
      ;;
    test)
      cat >&2 <<'TRANSITIONS'
현재 test 단계에서 가능한 전환:
  → forward  → verified : 전부 통과 + 사람 최종 검증
  → backward → spec     : SPEC 문제 → /ears-spec
  → backward → tc       : TC 부족 → /test-gen-design
  → backward → code     : 코드 수정 필요
TRANSITIONS
      ;;
  esac
}

# ══════════════════════════════════════════════════════════════
# ── Bash 도구: .claude/ 조작 차단 + 보호 경로 쓰기 감지 ──
# ══════════════════════════════════════════════════════════════
if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # .claude/ 보호
  if echo "$CMD" | grep -qE '\.claude/'; then
    echo "BLOCKED: .claude/ 디렉토리 조작이 차단되었습니다." >&2
    echo "HITL 훅과 스킬 설정은 보호됩니다." >&2
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
      # ── 관리 경로 대상: phase 검사 ──
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
        echo "BLOCKED: Bash 쓰기 명령이 보호 경로(${BLOCKED_PATH})를 수정하려 합니다." >&2
        echo "활성 영역 중 해당 경로를 수정할 수 있는 phase가 없습니다." >&2
        echo "" >&2
        echo "hitl-state.json을 확인하고, 사람에게 진행 방향을 안내하세요." >&2
        echo "CLAUDE.md의 Phase 안내와 Reentry 시나리오를 참조하세요." >&2
        exit 2
      fi
    else
      # ── 관리 경로 외부: 코드 확장자 감지 (Approach A, 휴리스틱) ──
      if echo "$CMD" | grep -qiE "\.(${BASH_CODE_EXT})\b"; then
        # 예외: 프로젝트 외부 절대 경로 대상 (boundary check)
        CODE_FILE=$(echo "$CMD" | grep -oiE '/[^ >"'"'"']*\.('"${BASH_CODE_EXT}"')' | head -1 || true)
        if [ -n "$CODE_FILE" ]; then
          case "$CODE_FILE" in
            "$CWD"/*) ;; # 프로젝트 내부 → 계속 검사
            *) exit 0 ;; # 프로젝트 외부 절대 경로 → 허용
          esac
        fi
        # 예외: 설정 파일 패턴 (*.config.ts, .eslintrc.js 등)
        if ! echo "$CMD" | grep -qE '\.(config|setup|rc)\.(ts|js|mjs|cjs|mts)\b'; then
          AREAS_JSON=$(jq '.areas // {}' "$STATE" 2>/dev/null)
          AREA_COUNT=$(echo "$AREAS_JSON" | jq 'length')
          if [ "$AREA_COUNT" != "0" ]; then
            echo "BLOCKED: Bash 쓰기 명령이 관리 경로 외부에서 코드 파일을 수정하려 합니다." >&2
            echo "" >&2
            echo "프로덕트 코드는 src/에, 테스트 코드는 tests/에 작성하세요." >&2
            echo "ISO 26262 추적성(Part 6 §9.3)을 위해 관리 경로 내에서 작업해야 합니다." >&2
            exit 2
          fi
        fi
      fi
    fi
  fi

  exit 0
fi

# ══════════════════════════════════════════════════════════════
# ── Edit/Write만 대상 (Read 등 다른 도구는 통과) ──
# ══════════════════════════════════════════════════════════════
if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then
  exit 0
fi

# ── 파일 경로 추출 ──
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# ── 프로젝트 외부 파일은 통과 (boundary check) ──
case "$FILE_PATH" in
  "$CWD"/*) ;;
  *) exit 0 ;;
esac

# ── 자기 보호: .claude/ 수정 차단 ──
case "$FILE_PATH" in
  */.claude/*|*/.claude/)
    echo "BLOCKED: .claude/ 디렉토리는 보호됩니다." >&2
    echo "HITL 훅과 스킬 설정을 수정할 수 없습니다." >&2
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
  */.omc/specs/*)      IS_SPEC=true ;;
  */.omc/test-cases/*) IS_TC=true ;;
  */.omc/*)            exit 0 ;;
  */src/*)             IS_SRC=true ;;
  */tests/*)           IS_TEST=true ;;
  *)
    # ══════════════════════════════════════════════════════════
    # ── Approach A: 관리 경로 외부 코드 확장자 검사 ──
    # ══════════════════════════════════════════════════════════
    EXT="${FILE_PATH##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
    case "$EXT_LOWER" in
      ts|tsx|js|jsx|mjs|cjs|mts|cts|py|pyx|pyi|rs|go|c|h|cpp|hpp|cc|hh|cxx|hxx|cs|java|kt|kts|scala|groovy|gvy|swift|dart|rb|php|pl|pm|lua|ps1|sh|bash|zsh|fish|ex|exs|erl|hrl|hs|lhs|ml|mli|clj|cljs|cljc|fs|fsx|elm|re|rei|zig|nim|cr|jl|v|r|sol|move|cairo|vue|svelte|astro|css|scss|sass|less|styl|html|htm|pug|ejs|hbs|njk|sql|graphql|gql|wasm|wat)
        BASENAME=$(basename "$FILE_PATH")
        case "$BASENAME" in
          *.config.*|*.setup.*|.?*rc|.?*rc.*) exit 0 ;;
        esac

        AREAS_JSON=$(jq '.areas // {}' "$STATE" 2>/dev/null)
        AREA_COUNT=$(echo "$AREAS_JSON" | jq 'length')
        [ "$AREA_COUNT" = "0" ] && exit 0

        cat >&2 <<EOF
BLOCKED: 코드 파일이 관리 경로(src/, tests/) 외부에 있습니다.
파일: $FILE_PATH

프로덕트 코드는 src/에, 테스트 코드는 tests/에 작성하세요.
ISO 26262 추적성(Part 6 §9.3)을 위해 관리 경로 내에서 작업해야 합니다.

이 파일이 설정 파일이라면, 허용되는 네이밍 패턴:
  *.config.* | *.setup.* | .*rc | .*rc.*
  (예: vite.config.ts, .eslintrc.js, jest.setup.ts)
EOF
        exit 2
        ;;
      *)
        exit 0 ;;
    esac
    ;;
esac

# ══════════════════════════════════════════════════════════════
# ── 영역 phase 수집 ──
# ══════════════════════════════════════════════════════════════
AREAS_JSON=$(jq '.areas // {}' "$STATE" 2>/dev/null)
AREA_COUNT=$(echo "$AREAS_JSON" | jq 'length')
[ "$AREA_COUNT" = "0" ] && exit 0

# ── 파일이 속한 영역 찾기 (다중 영역 매핑 지원) ──
TARGET_AREAS=""

if $IS_SPEC; then
  TARGET_AREAS=$(jq -r --arg fp "$FILE_PATH" '
    .areas | to_entries[] | select(.value.spec.file) |
    .value.spec.file as $sf | select($fp | endswith($sf)) |
    .key' "$STATE" 2>/dev/null)
fi

if $IS_TC; then
  TARGET_AREAS=$(jq -r --arg fp "$FILE_PATH" '
    .areas | to_entries[] | select(.value.tc.file) |
    .value.tc.file as $tf | select($fp | endswith($tf)) |
    .key' "$STATE" 2>/dev/null)
fi

if $IS_SRC; then
  TARGET_AREAS=$(jq -r --arg fp "$FILE_PATH" '
    .areas | to_entries[] |
    select(.value.code.files) |
    select([.value.code.files[] | . as $cf | select($fp | endswith($cf))] | length > 0) |
    .key' "$STATE" 2>/dev/null)
fi

if $IS_TEST; then
  TARGET_AREAS=$(echo "$FILE_PATH" | grep -oE 'tests/[^/]+/([A-Z]{2})' | grep -oE '[A-Z]{2}$' || true)
fi

if [ -z "$TARGET_AREAS" ]; then
  ACTIVE=$(echo "$AREAS_JSON" | jq '[to_entries[] | select(
    .value.phase == "spec" or
    .value.phase == "tc" or
    .value.phase == "code" or
    .value.phase == "test"
  )] | length')
  if [ "$ACTIVE" -gt 0 ]; then
    exit 0
  fi
  cat >&2 <<EOF
BLOCKED: 이 파일은 어떤 영역에도 매핑되지 않았고, 활성 영역이 없습니다.

가능한 행동:
  → 기존 영역의 reentry 시작 (사람에게 시나리오 A/B/C 확인)
  → 새 영역 등록 (hitl-state.json에 area 추가, phase: "spec")

사람에게 이 파일이 어떤 영역에 속하는지 확인하세요.
EOF
  exit 2
fi

# ══════════════════════════════════════════════════════════════
# ── 모든 매칭 영역의 phase를 검사 (하나라도 차단이면 차단) ──
# ══════════════════════════════════════════════════════════════
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

if [ -z "$BLOCKED_AREA" ]; then
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# ── 차단: 상태 머신 기반 피드백 ──
# ══════════════════════════════════════════════════════════════
AREA_NAME=$(echo "$AREAS_JSON" | jq -r --arg area "$BLOCKED_AREA" '.[$area].name // $area')

TRIED_PATH=""
$IS_SRC && TRIED_PATH="src/"
$IS_SPEC && TRIED_PATH=".omc/specs/"
$IS_TC && TRIED_PATH=".omc/test-cases/"
$IS_TEST && TRIED_PATH="tests/"

NEEDED_PHASES=""
$IS_SRC && NEEDED_PHASES="code 또는 test"
$IS_SPEC && NEEDED_PHASES="spec"
$IS_TC && NEEDED_PHASES="tc, code, 또는 test"
$IS_TEST && NEEDED_PHASES="code 또는 test"

if [ "$BLOCKED_PHASE" = "verified" ]; then
  cat >&2 <<EOF
BLOCKED: ${BLOCKED_AREA}(${AREA_NAME}) — verified [cycle ${BLOCKED_CYCLE}]
${TRIED_PATH} 수정은 ${NEEDED_PHASES} 단계에서 가능합니다.

사람에게 reentry 시나리오를 확인하세요:
  A. SPEC 변경 필요  → spec  (cycle++) → /ears-spec
  B. 코드 버그       → tc    (cycle++) → /test-gen-design
  C. 테스트 코드 오류 → code  (cycle++) → /test-gen-code

reentry 시 hitl-state.json 변경:
  phase → 진입 phase, cycle → $((BLOCKED_CYCLE + 1)),
  cycle_entry, cycle_reason, log 기록 필수
EOF
else
  cat >&2 <<EOF
BLOCKED: ${BLOCKED_AREA}(${AREA_NAME}) — ${BLOCKED_PHASE} [cycle ${BLOCKED_CYCLE}]
${TRIED_PATH} 수정은 ${NEEDED_PHASES} 단계에서 가능합니다.

EOF
  print_transitions "$BLOCKED_PHASE"

  AREA_WORD_COUNT=$(echo "$TARGET_AREAS" | wc -w | tr -d ' ')
  if [ "$AREA_WORD_COUNT" -gt 1 ]; then
    cat >&2 <<EOF

주의: 이 파일은 여러 영역에 매핑되어 있습니다: $TARGET_AREAS
차단 원인: ${BLOCKED_AREA}(${BLOCKED_PHASE})
→ 이 영역도 해당 경로를 수정할 수 있는 phase로 전환해야 합니다.
EOF
  fi

  echo "" >&2
  echo "사람에게 진행 방향을 확인하세요." >&2
fi

exit 2
