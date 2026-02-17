# Failure Classification Algorithm

테스트 실패 시 원인을 분류하는 알고리즘. 분류에 따라 수정 대상이 달라진다.

## Decision Tree

```
1. 컴파일/타입 에러?
   YES → TEST_BUG (import, 타입, 문법 수정)
   NO  → 2로

2. 대상 코드/요소를 찾지 못함?
   YES → 기능이 구현되어 있는가?
         NO  → CODE_BUG (기능 구현)
         YES → TEST_BUG (잘못된 셀렉터, import 경로)
   NO  → 3으로

3. Assertion 실패?
   → 테스트 기대값이 TC spec(given/when/then)과 일치하는가?
     YES → CODE_BUG (코드가 스펙을 충족하지 않음)
     NO  → TEST_BUG (테스트가 TC를 잘못 번역)

4. TC가 SPEC과 불일치?
   YES → SPEC_ISSUE (사람에게 보고, 중단)
```

## Classification Actions

| 분류 | 수정 대상 | 행동 |
|------|-----------|------|
| `TEST_BUG` | `tests/` | 테스트 코드 수정 후 재실행 |
| `CODE_BUG` | `src/` | 소스 코드 수정 후 재실행 |
| `SPEC_ISSUE` | 없음 | **즉시 중단**, 사람에게 불일치 내용 보고 |

## Error Pattern Quick Reference

| 에러 패턴 | 분류 |
|-----------|------|
| `Cannot find module` | TEST_BUG |
| `Property X does not exist on type Y` | TEST_BUG (API 불일치면 CODE_BUG) |
| `Element not found` / timeout | TEST_BUG (셀렉터) |
| `Expected X, Received Y` (X=TC 스펙대로) | CODE_BUG |
| `Expected X, Received Y` (X≠TC 스펙) | TEST_BUG |
