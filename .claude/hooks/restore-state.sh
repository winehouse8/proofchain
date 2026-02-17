#!/bin/bash
# HITL State Restore — SessionStart Hook
# 세션 시작/재개 시 현재 상태를 Claude에게 주입
# 5-Phase Model: spec, tc, code, test, verified

CWD=$(pwd)
STATE="$CWD/.omc/hitl-state.json"

[ ! -f "$STATE" ] && exit 0

# 각 영역의 상태를 요약
echo "=== HITL 현황 ==="
jq -r '
  .areas | to_entries[] |
  "\(.key) (\(.value.name_ko // .value.name // .key)): \(.value.phase) [cycle \(.value.cycle // 1)]"
' "$STATE" 2>/dev/null

# cycle > 1인 활성 영역 (reentry 진행 중)
REENTRY=$(jq -r '
  .areas | to_entries[]
  | select(.value.phase != "verified" and (.value.cycle // 1) > 1)
  | "\(.key): \(.value.phase) [cycle \(.value.cycle)] — \(.value.cycle_reason // "N/A")"
' "$STATE" 2>/dev/null)

if [ -n "$REENTRY" ]; then
  echo ""
  echo "=== Reentry 진행 중 ==="
  echo "$REENTRY"
fi

# cycle 1 활성 영역 (초기 개발 진행 중)
INITIAL=$(jq -r '
  .areas | to_entries[]
  | select(.value.phase != "verified" and (.value.cycle // 1) == 1)
  | "\(.key): \(.value.phase)"
' "$STATE" 2>/dev/null)

if [ -n "$INITIAL" ]; then
  echo ""
  echo "=== 초기 개발 진행 중 ==="
  echo "$INITIAL"
fi

exit 0
