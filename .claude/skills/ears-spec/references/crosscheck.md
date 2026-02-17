# SPEC Cross-Validation Checklist

Run this checklist after drafting all requirements. Report each item as PASS, WARN, or FAIL.

## 1. Completeness

- [ ] Every requirement has a valid EARS sentence with `shall`
- [ ] Every requirement has a REQ ID in the correct format
- [ ] Every requirement has a rationale
- [ ] Every requirement has a verification method
- [ ] Each functional REQ has at least one plausible negative scenario (if not captured as a separate REQ, flag as WARN)
- [ ] Boundary conditions are addressed for numeric/size constraints
- [ ] Error handling is specified for operations that can fail

## 2. Ambiguity

Check each EARS sentence for vague or unbounded terms. Flag any occurrence:

| Vague term | Replacement guidance |
|------------|---------------------|
| fast, quickly, responsive | Specify time (e.g., "within 200ms") |
| large, small, many, few | Specify quantity (e.g., "up to 100 gates") |
| user-friendly, intuitive | Describe the observable behavior |
| appropriate, suitable | Define the criteria |
| etc., and so on | List all items explicitly |
| support, handle | Describe the specific action |
| normally, usually | Remove or specify the exception |

Also check:
- [ ] No passive voice hiding the actor ("shall be displayed" → by whom?)
- [ ] No compound requirements (multiple "shall" in one REQ → split)
- [ ] Pronouns resolve unambiguously ("it", "this" → use the noun)

## 3. Consistency

- [ ] No two REQs contradict each other
- [ ] Shared terms use identical wording across all REQs (e.g., "canvas" not sometimes "workspace")
- [ ] REQ numbering is sequential with no gaps
- [ ] Area code matches across all REQs in the SPEC

## 4. Verifiability

For each REQ, confirm at least one verification level is realistic:

| Level | Can verify this REQ? |
|-------|---------------------|
| unit | Pure logic, no UI needed |
| component | Single UI component behavior |
| api | HTTP endpoint behavior |
| e2e | Multi-step user flow |
| visual | Rendered appearance |

- [ ] Every REQ maps to at least one verification level
- [ ] No REQ requires subjective judgment to verify (e.g., "looks good")

## 5. Traceability Readiness

- [ ] Every REQ ID is unique within the SPEC
- [ ] REQ IDs follow the convention: REQ-{area}-{three digits}
- [ ] The SPEC file is named: SPEC-{project}-{area}.md

## Severity

| Level | Meaning | Action |
|-------|---------|--------|
| PASS | Check satisfied | Proceed |
| WARN | Potential issue found | Human must acknowledge or fix |
| FAIL | Definite problem | Must fix before SPEC finalization |
