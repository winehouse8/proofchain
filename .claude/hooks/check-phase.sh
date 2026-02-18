#!/bin/bash
# HITL Phase Guard — PreToolUse Hook (v3.3.1: + git 명령 .claude/ 오탐 수정)
# Gate: Phase 기반 파일 접근 제어 + 자기 보호 + 코드 확장자 검사
# 5-Phase Model: spec, tc, code, test, verified
# Edit/Write: 영역별 정밀 검사 + 코드 확장자 차단
# Bash: 휴리스틱 쓰기 감지 + 코드 확장자 휴리스틱
#
# Layer 1 (Guard): test phase에서 src/ 수정 시 자동 backward (test→code)
# Layer 3 (Gate): verified 전환 시 추적성 전수 검사 (차단)
#   - @tc ↔ TC JSON 매핑 검사
#   - Supplementary TC 필수 필드 검증 (§6.3)
#   - Change-log 커버리지 경고 (§6.1 Hotfix light)
#   - Baseline TC 내용 불변 검증 (git tag 비교, cycle > 1)
#   - Reentry 로그 필수 필드 검증 (§8.4.1, §8.7, cycle > 1)
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
# ── Layer 1 Helper: Auto-backward (test→code) ──
# ══════════════════════════════════════════════════════════════
auto_backward() {
  # $1 = TARGET_AREAS (space-separated, may be empty)
  local target_areas="$1"
  local areas_json
  areas_json=$(jq '.areas // {}' "$STATE" 2>/dev/null) || return

  local backward_areas=""

  if [ -n "$target_areas" ]; then
    for area in $target_areas; do
      local phase
      phase=$(echo "$areas_json" | jq -r --arg a "$area" '.[$a].phase // "unknown"') || continue
      [ "$phase" = "test" ] && backward_areas="$backward_areas $area"
    done
  else
    # unmapped src/ → test phase인 모든 area를 backward
    backward_areas=$(echo "$areas_json" | jq -r '
      to_entries[] | select(.value.phase == "test") | .key
    ' 2>/dev/null) || backward_areas=""
  fi

  backward_areas=$(echo "$backward_areas" | xargs)
  [ -z "$backward_areas" ] && return

  for area in $backward_areas; do
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq --arg a "$area" --arg ts "$ts" '
      .areas[$a].phase = "code" |
      .log += [{
        "timestamp": $ts,
        "area": $a,
        "from": "test",
        "to": "code",
        "actor": "hook",
        "type": "auto-backward",
        "note": "Auto-backward: src/ modified during test phase"
      }]
    ' "$STATE" > "${STATE}.tmp" && mv "${STATE}.tmp" "$STATE"

    cat >&2 <<EOF
⚠ AUTO-BACKWARD: ${area} — test → code
  test phase에서 src/ 수정이 감지되어 자동으로 code phase로 전환했습니다.
  수정 완료 후:
  1. TC JSON에 supplementary TC를 추가하세요 (origin: "supplementary", added_reason 필수)
  2. 테스트 코드에 @tc 어노테이션을 부착하세요
  3. 테스트를 재실행하여 code → test로 복귀하세요
EOF
  done
}

# ══════════════════════════════════════════════════════════════
# ── Layer 3 Helper: Verified Gate (추적성 전수 검사) ──
# ══════════════════════════════════════════════════════════════
verified_gate() {
  # $1 = area key
  local area="$1"
  local tc_file
  tc_file=$(jq -r --arg a "$area" '.areas[$a].tc.file // empty' "$STATE" 2>/dev/null) || return 0
  [ -z "$tc_file" ] && return 0

  local tc_path="$CWD/$tc_file"
  [ ! -f "$tc_path" ] && return 0

  # ── 검사 1: active TC ↔ @tc 매핑 ──
  local active_tc_ids
  active_tc_ids=$(jq -r '
    [
      (.baseline_tcs // [] | .[] | select(.status != "obsolete") | .tc_id),
      (.supplementary_tcs // [] | .[] | .tc_id)
    ] | .[]
  ' "$tc_path" 2>/dev/null) || return 0

  [ -z "$active_tc_ids" ] && return 0

  # active TC의 req_id 매핑 (tc_id → req_id)
  local tc_req_map
  tc_req_map=$(jq -r '
    [
      (.baseline_tcs // [] | .[] | select(.status != "obsolete") | "\(.tc_id)|\(.req_id)"),
      (.supplementary_tcs // [] | .[] | "\(.tc_id)|\(.req_id)")
    ] | .[]
  ' "$tc_path" 2>/dev/null) || tc_req_map=""

  local test_dir="$CWD/tests"
  local found_tcs=""
  local found_reqs=""
  if [ -d "$test_dir" ]; then
    found_tcs=$(grep -rhoE '@tc\s+TC-[A-Z]{2}-[0-9]{3}[a-z]?' "$test_dir" 2>/dev/null | \
      sed 's/@tc\s*//' | sort -u) || found_tcs=""
    found_reqs=$(grep -rhoE '@req\s+REQ-[A-Z]{2}-[0-9]{3}' "$test_dir" 2>/dev/null | \
      sed 's/@req\s*//' | sort -u) || found_reqs=""
  fi

  local missing=""
  local missing_count=0
  local total_count=0

  while IFS= read -r tc_id; do
    [ -z "$tc_id" ] && continue
    total_count=$((total_count + 1))
    if ! echo "$found_tcs" | grep -qw "$tc_id"; then
      missing="$missing  - $tc_id (@tc 누락)"$'\n'
      missing_count=$((missing_count + 1))
    fi
  done <<< "$active_tc_ids"

  # @req 검사: TC에 연결된 req_id가 테스트 코드에 @req로 존재하는지
  local req_missing=""
  local req_missing_count=0
  local checked_reqs=""

  while IFS='|' read -r tc_id req_id; do
    [ -z "$req_id" ] && continue
    # 같은 req_id 중복 검사 방지
    if echo "$checked_reqs" | grep -qw "$req_id" 2>/dev/null; then
      continue
    fi
    checked_reqs="$checked_reqs $req_id"
    if [ -n "$found_reqs" ]; then
      if ! echo "$found_reqs" | grep -qw "$req_id"; then
        req_missing="$req_missing  - $req_id (@req 누락 — $tc_id 에서 참조)"$'\n'
        req_missing_count=$((req_missing_count + 1))
      fi
    else
      req_missing="$req_missing  - $req_id (@req 누락 — $tc_id 에서 참조)"$'\n'
      req_missing_count=$((req_missing_count + 1))
    fi
  done <<< "$tc_req_map"

  if [ "$missing_count" -gt 0 ] || [ "$req_missing_count" -gt 0 ]; then
    cat >&2 <<EOF
BLOCKED: ${area} — verified 전환 차단 (추적성 미충족)
EOF
    if [ "$missing_count" -gt 0 ]; then
      cat >&2 <<EOF
  Active TC: ${total_count}개 중 ${missing_count}개 @tc 어노테이션 누락:
${missing}
EOF
    fi
    if [ "$req_missing_count" -gt 0 ]; then
      cat >&2 <<EOF
  REQ 추적: ${req_missing_count}개 @req 어노테이션 누락:
${req_missing}
EOF
    fi
    cat >&2 <<EOF
  모든 테스트에 @tc TC-XX-NNNx 와 @req REQ-XX-NNN 주석을 추가한 후 다시 시도하세요.
  ISO 26262 Part 6 §9.3 추적성 요구사항을 충족해야 합니다.
EOF
    return 1
  fi

  # ── 검사 2: Supplementary TC 스키마 검증 (§6.3) ──
  local supp_errors=""
  local supp_error_count=0
  local required_fields="tc_id origin req_id type level title given when then added_reason"

  local supp_count
  supp_count=$(jq '.supplementary_tcs // [] | length' "$tc_path" 2>/dev/null) || supp_count=0

  if [ "$supp_count" -gt 0 ]; then
    local i=0
    while [ "$i" -lt "$supp_count" ]; do
      local tc_id_val
      tc_id_val=$(jq -r --argjson idx "$i" '.supplementary_tcs[$idx].tc_id // "unknown"' "$tc_path" 2>/dev/null)

      for field in $required_fields; do
        local val
        val=$(jq -r --argjson idx "$i" --arg f "$field" '.supplementary_tcs[$idx][$f] // empty' "$tc_path" 2>/dev/null)
        if [ -z "$val" ]; then
          supp_errors="$supp_errors  - ${tc_id_val}: \"${field}\" 필드 누락"$'\n'
          supp_error_count=$((supp_error_count + 1))
        elif [ "$field" = "added_reason" ] && [ "${#val}" -lt 10 ]; then
          supp_errors="$supp_errors  - ${tc_id_val}: \"added_reason\" 최소 10자 필요 (현재: ${#val}자)"$'\n'
          supp_error_count=$((supp_error_count + 1))
        fi
      done

      # origin must be "supplementary"
      local origin_val
      origin_val=$(jq -r --argjson idx "$i" '.supplementary_tcs[$idx].origin // empty' "$tc_path" 2>/dev/null)
      if [ -n "$origin_val" ] && [ "$origin_val" != "supplementary" ]; then
        supp_errors="$supp_errors  - ${tc_id_val}: origin은 \"supplementary\"여야 함 (현재: \"${origin_val}\")"$'\n'
        supp_error_count=$((supp_error_count + 1))
      fi

      i=$((i + 1))
    done
  fi

  if [ "$supp_error_count" -gt 0 ]; then
    cat >&2 <<EOF
BLOCKED: ${area} — verified 전환 차단 (Supplementary TC 스키마 오류)
  ${supp_error_count}개 필드 문제:
${supp_errors}
  필수 필드: tc_id, origin("supplementary"), req_id, type, level,
             title, given, when, then, added_reason
EOF
    return 1
  fi

  # ── 검사 3: Change-log 커버리지 경고 (§6.1 Hotfix light) ──
  # 차단 안 함 — 경고만
  local change_log="$CWD/.omc/change-log.jsonl"
  if [ -f "$change_log" ]; then
    # unmapped src/ 변경 경고
    local unmapped_files
    unmapped_files=$(grep '"area":"unmapped"' "$change_log" 2>/dev/null | \
      jq -r '.file' 2>/dev/null | sort -u) || unmapped_files=""

    if [ -n "$unmapped_files" ]; then
      cat >&2 <<EOF
⚠ COVERAGE WARNING: ${area} — 영역 미매핑 src/ 변경 감지
  다음 파일이 어떤 영역에도 매핑되지 않은 채 수정되었습니다:
EOF
      echo "$unmapped_files" | while IFS= read -r f; do
        [ -n "$f" ] && echo "  - $f" >&2
      done
      echo "  hitl-state.json의 code.files에 파일을 등록하면 추적성이 향상됩니다." >&2
    fi

    # auto-backward 이력이 있는 area: supplementary TC 존재 여부 경고
    local has_autobackward
    has_autobackward=$(jq --arg a "$area" '
      [.log // [] | .[] | select(.area == $a and .type == "auto-backward")] | length
    ' "$STATE" 2>/dev/null) || has_autobackward=0

    if [ "$has_autobackward" -gt 0 ] && [ "$supp_count" -eq 0 ]; then
      cat >&2 <<EOF
⚠ HOTFIX WARNING: ${area} — auto-backward 이력 ${has_autobackward}건 있으나 supplementary TC 없음
  test phase에서 코드 수정이 발생했으므로 보완 TC 추가를 권장합니다.
  TC JSON에 origin: "supplementary", added_reason 필드와 함께 추가하세요.
EOF
    fi
  fi

  # ── 검사 4: Baseline TC 내용 불변 (git tag 비교, cycle > 1) ──
  local first_tag="${area}-verified-c1"
  if git -C "$CWD" rev-parse "$first_tag" >/dev/null 2>&1; then
    # 첫 verified 태그가 존재 = cycle > 1
    local original_tc_json
    original_tc_json=$(git -C "$CWD" show "${first_tag}:${tc_file}" 2>/dev/null) || original_tc_json=""

    if [ -n "$original_tc_json" ]; then
      local original_baselines
      original_baselines=$(echo "$original_tc_json" | jq -r '
        .baseline_tcs // [] | .[] | .tc_id
      ' 2>/dev/null) || original_baselines=""

      if [ -n "$original_baselines" ]; then
        local baseline_errors=""
        local baseline_error_count=0

        while IFS= read -r orig_id; do
          [ -z "$orig_id" ] && continue

          # 현재 JSON에서 이 TC 찾기
          local cur_status
          cur_status=$(jq -r --arg id "$orig_id" '
            .baseline_tcs // [] | .[] | select(.tc_id == $id) | .status // "active"
          ' "$tc_path" 2>/dev/null) || cur_status=""

          if [ -z "$cur_status" ]; then
            baseline_errors="${baseline_errors}  - ${orig_id}: TC JSON에서 삭제됨 (삭제 금지, obsolete 마킹 필요)\n"
            baseline_error_count=$((baseline_error_count + 1))
            continue
          fi

          # obsolete면 내용 변경 상관없음
          [ "$cur_status" = "obsolete" ] && continue

          # given/when/then 비교
          local orig_gwt cur_gwt
          orig_gwt=$(echo "$original_tc_json" | jq -r --arg id "$orig_id" '
            .baseline_tcs[] | select(.tc_id == $id) |
            (.given // "") + "|||" + (.when // "") + "|||" + (.then // "")
          ' 2>/dev/null) || continue
          cur_gwt=$(jq -r --arg id "$orig_id" '
            .baseline_tcs[] | select(.tc_id == $id) |
            (.given // "") + "|||" + (.when // "") + "|||" + (.then // "")
          ' "$tc_path" 2>/dev/null) || continue

          if [ "$orig_gwt" != "$cur_gwt" ]; then
            baseline_errors="${baseline_errors}  - ${orig_id}: given/when/then 내용이 변경됨\n"
            baseline_error_count=$((baseline_error_count + 1))
          fi
        done <<< "$original_baselines"

        if [ "$baseline_error_count" -gt 0 ]; then
          cat >&2 <<EOF
BLOCKED: ${area} — verified 전환 차단 (Baseline TC 불변 위반)
  ${baseline_error_count}개 baseline TC 문제:
$(printf "$baseline_errors")
  Baseline TC의 given/when/then은 최초 verified 이후 수정할 수 없습니다.
  변경이 필요하면: status를 "obsolete"로 마킹 + supplementary TC 생성
  불변 규칙 #1 (ISO 26262 Part 8 §7.4.3)
EOF
          return 1
        fi
      fi
    fi
  fi

  # ── 검사 5: Reentry 로그 필수 필드 검증 (§8.4.1, §8.7, cycle > 1) ──
  local area_cycle
  area_cycle=$(jq -r --arg a "$area" '.areas[$a].cycle // 1' "$STATE" 2>/dev/null) || area_cycle=1

  if [ "$area_cycle" -gt 1 ]; then
    # 가장 최근의 reentry 로그 항목 찾기 (from=="verified" 또는 type=="reentry")
    local reentry_entry
    reentry_entry=$(jq --arg a "$area" '
      [.log // [] | .[] | select(.area == $a and (.from == "verified" or .type == "reentry"))] | last
    ' "$STATE" 2>/dev/null) || reentry_entry="null"

    if [ "$reentry_entry" = "null" ] || [ -z "$reentry_entry" ]; then
      cat >&2 <<EOF
BLOCKED: ${area} — verified 전환 차단 (Reentry 로그 부재)
  cycle ${area_cycle}이지만 reentry 로그 항목이 없습니다.
  Reentry 시 hitl-state.json의 log 배열에 다음 필드를 기록하세요:
    type, reason, affected_reqs
  단계를 건너뛰었다면: skipped_phases, skip_reason
  ISO 26262 Part 8 §8.4.1 (변경 요청), §8.7 (단계 생략 근거)
EOF
      return 1
    fi

    local log_errors=""
    local log_error_count=0

    # type, reason, affected_reqs 필수 필드 검사
    for field in type reason affected_reqs; do
      local val
      val=$(echo "$reentry_entry" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null)
      if [ -z "$val" ]; then
        log_errors="${log_errors}  - \"${field}\" 필드 누락\n"
        log_error_count=$((log_error_count + 1))
      fi
    done

    # skipped_phases가 있으면 skip_reason 필수 (§8.7)
    local skipped
    skipped=$(echo "$reentry_entry" | jq -r '
      if .skipped_phases then
        (.skipped_phases | if type == "array" then join(", ") else tostring end)
      else empty end
    ' 2>/dev/null) || skipped=""

    if [ -n "$skipped" ]; then
      local skip_reason_val
      skip_reason_val=$(echo "$reentry_entry" | jq -r '.skip_reason // empty' 2>/dev/null)
      if [ -z "$skip_reason_val" ]; then
        log_errors="${log_errors}  - \"skip_reason\" 필드 누락 (skipped_phases: ${skipped})\n"
        log_error_count=$((log_error_count + 1))
      fi
    fi

    if [ "$log_error_count" -gt 0 ]; then
      cat >&2 <<EOF
BLOCKED: ${area} — verified 전환 차단 (Reentry 로그 불완전)
  cycle ${area_cycle} reentry 로그에 ${log_error_count}개 필수 필드 누락:
$(printf "$log_errors")
  Reentry 시 log에 type, reason, affected_reqs 필드가 필수입니다.
  단계를 건너뛰었다면 skipped_phases + skip_reason도 필수입니다.
  ISO 26262 Part 8 §8.4.1 (변경 요청), §8.7 (단계 생략 근거)
EOF
      return 1
    fi
  fi

  return 0
}

# ══════════════════════════════════════════════════════════════
# ── Bash 도구: .claude/ 조작 차단 + 보호 경로 쓰기 감지 ──
# ══════════════════════════════════════════════════════════════
if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # .claude/ 보호 — 쓰기 연산만 차단 (git 명령 허용)
  # git 명령은 VCS 작업이므로 .claude/ 파일 쓰기가 아님.
  # 커밋 메시지 안의 >, cp 등이 쓰기 패턴으로 오탐되는 것을 방지.
  if echo "$CMD" | grep -qE '\.claude/' && \
      ! echo "$CMD" | grep -qE '^\s*git\s' && \
      echo "$CMD" | grep -qE '(sed\s.*-i|\btee\b|>[^&]|>>|\b(cp|mv|rm|mkdir|chmod|chown|install)\b)'; then
    echo "BLOCKED: .claude/ 디렉토리 쓰기가 차단되었습니다." >&2
    echo "HITL 훅과 스킬 설정은 보호됩니다. 읽기/VCS 명령은 허용됩니다." >&2
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

      # ── Layer 1: Bash에서 src/ 쓰기 + test phase → auto-backward ──
      if $BASH_SRC && [ -z "$BLOCKED_PATH" ]; then
        auto_backward ""
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

# ══════════════════════════════════════════════════════════════
# ── Layer 3: hitl-state.json에 verified 전환 시 추적성 검사 ──
# ══════════════════════════════════════════════════════════════
case "$FILE_PATH" in
  */.omc/hitl-state.json)
    # Write tool: 새 JSON에서 verified 전환 area 식별
    if [ "$TOOL" = "Write" ]; then
      NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
      if [ -n "$NEW_CONTENT" ]; then
        # 새 JSON에서 verified phase인 area 찾기
        NEW_VERIFIED=$(echo "$NEW_CONTENT" | jq -r '
          .areas // {} | to_entries[] | select(.value.phase == "verified") | .key
        ' 2>/dev/null) || NEW_VERIFIED=""

        for area in $NEW_VERIFIED; do
          # 현재 state에서 이 area가 verified가 아니면 → 전환 중
          CUR_PHASE=$(jq -r --arg a "$area" '.areas[$a].phase // "unknown"' "$STATE" 2>/dev/null) || CUR_PHASE="unknown"
          if [ "$CUR_PHASE" != "verified" ]; then
            if ! verified_gate "$area"; then
              exit 2
            fi
          fi
        done
      fi
    fi

    # Edit tool: new_string에 "verified" 포함 시 검사
    if [ "$TOOL" = "Edit" ]; then
      NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
      if echo "$NEW_STRING" | grep -q '"verified"'; then
        # test phase인 area들 검사
        TEST_AREAS=$(jq -r '.areas | to_entries[] | select(.value.phase == "test") | .key' "$STATE" 2>/dev/null) || TEST_AREAS=""
        for area in $TEST_AREAS; do
          if ! verified_gate "$area"; then
            exit 2
          fi
        done
      fi
    fi

    exit 0
    ;;
esac

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
    # ── Layer 1: unmapped src/ + test phase → auto-backward ──
    if $IS_SRC; then
      auto_backward ""
    fi
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
  # ── Layer 1: mapped src/ + test phase → auto-backward ──
  if $IS_SRC; then
    auto_backward "$TARGET_AREAS"
  fi
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
