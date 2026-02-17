#!/bin/bash
# Phase Commit — PostToolUse Hook
# Detects phase transitions in hitl-state.json and auto-commits
# with structured messages. Creates git tags at verified milestones.
#
# Fires on every Edit/Write but exits immediately for non-hitl-state.json files.
# PostToolUse cannot block — exit 0 always.

set -euo pipefail
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

CWD=$(echo "$INPUT" | jq -r '.cwd')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# ── hitl-state.json 변경만 대상 ──
case "$FILE_PATH" in
  */.omc/hitl-state.json) ;;
  *) exit 0 ;;
esac

STATE="$CWD/.omc/hitl-state.json"
SNAPSHOT="$CWD/.omc/.phase-snapshot.json"

# ── git repo 필수 ──
git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# ── 현재 영역/phase 읽기 ──
CURRENT=$(jq -r '
  .areas // {} | to_entries[] |
  "\(.key)|\(.value.phase // "unknown")|\(.value.cycle // 1)|\(.value.name // .key)"
' "$STATE" 2>/dev/null) || exit 0

# 영역 없으면 스킵
[ -z "$CURRENT" ] && exit 0

# ── 스냅샷 읽기 (없으면 초기 생성) ──
if [ -f "$SNAPSHOT" ]; then
  PREV=$(jq -r '
    .areas // {} | to_entries[] |
    "\(.key)|\(.value.phase // "unknown")|\(.value.cycle // 1)|\(.value.name // .key)"
  ' "$SNAPSHOT" 2>/dev/null) || PREV=""
else
  # 최초 실행: 스냅샷 생성 후 초기 커밋
  cp "$STATE" "$SNAPSHOT"
  PREV=""
fi

# ── 전환 감지 ──
TRANSITIONS=()

while IFS='|' read -r area phase cycle name; do
  [ -z "$area" ] && continue

  OLD_LINE=$(echo "$PREV" | grep "^${area}|" 2>/dev/null || true)

  if [ -z "$OLD_LINE" ]; then
    # 새 영역 추가
    TRANSITIONS+=("${area}|${name}|(init)|${phase}|${cycle}")
  else
    OLD_PHASE=$(echo "$OLD_LINE" | cut -d'|' -f2)
    OLD_CYCLE=$(echo "$OLD_LINE" | cut -d'|' -f3)

    if [ "$OLD_PHASE" != "$phase" ] || [ "$OLD_CYCLE" != "$cycle" ]; then
      TRANSITIONS+=("${area}|${name}|${OLD_PHASE}|${phase}|${cycle}")
    fi
  fi
done <<< "$CURRENT"

# 전환 없음
if [ ${#TRANSITIONS[@]} -eq 0 ]; then
  cp "$STATE" "$SNAPSHOT"
  exit 0
fi

# ── 커밋 메시지 구성 ──
TRANS_COUNT=${#TRANSITIONS[@]}
SUBJECT=""
BODY=""
TAG_LIST=()

for t in "${TRANSITIONS[@]}"; do
  IFS='|' read -r area name from to cycle <<< "$t"

  if [ "$TRANS_COUNT" -eq 1 ]; then
    SUBJECT="[proofchain] ${area}(${name}): ${from} → ${to} (cycle ${cycle})"
  else
    SUBJECT="[proofchain] Phase transitions (${TRANS_COUNT} areas)"
  fi

  BODY="${BODY}  ${area}(${name}): ${from} → ${to} [cycle ${cycle}]
"

  if [ "$to" = "verified" ]; then
    TAG_LIST+=("${area}-verified-c${cycle}")
  fi
done

# ── git add + commit ──
git -C "$CWD" add -A 2>/dev/null || exit 0

# 커밋할 변경이 없으면 스킵
if git -C "$CWD" diff --cached --quiet 2>/dev/null; then
  cp "$STATE" "$SNAPSHOT"
  exit 0
fi

FULL_MSG=$(printf "%s\n\n%s" "$SUBJECT" "$BODY")
git -C "$CWD" commit --no-verify -m "$FULL_MSG" >/dev/null 2>&1 || {
  cp "$STATE" "$SNAPSHOT"
  exit 0
}

# ── verified 태그 생성 ──
if [ ${#TAG_LIST[@]} -gt 0 ]; then
  for tag in "${TAG_LIST[@]}"; do
    git -C "$CWD" tag "$tag" 2>/dev/null || true
  done
  echo "[proofchain] Tags: ${TAG_LIST[*]}" >&2
fi

# ── 스냅샷 갱신 ──
cp "$STATE" "$SNAPSHOT"

# ── 결과 보고 (stderr) ──
echo "[proofchain] ${SUBJECT}" >&2

exit 0
