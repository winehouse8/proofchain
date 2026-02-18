# proofchain

**ISO 26262-grade software verification for AI-assisted development with Claude Code.**

proofchain is a Human-in-the-Loop (HITL) development framework that enforces rigorous software verification through a 5-phase state machine. Using Claude Code's [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) and [skills](https://docs.anthropic.com/en/docs/claude-code/skills), it ensures every line of code is traceable to a specification and verified through systematic testing — at a level of rigor inspired by ISO 26262.

## Why?

AI coding assistants make it easy to write code fast — and just as easy to skip verification. proofchain prevents this by enforcing a structured development loop where:

- You **can't write code** until the spec is approved
- You **can't modify tests** until test cases are designed
- Test cases are generated **without seeing source code** (isolation)
- Every change after verification requires a **justified reentry** with full regression
- All artifacts maintain **bidirectional traceability** (REQ ↔ TC ↔ Test Code)
- Every SPEC and TC change is **individually git-committed** for audit trail

The AI writes code. You make decisions. The framework enforces the process.

## The 5-Phase State Machine

```
spec ──→ tc ──→ code ──→ test ──→ verified
  ↑       ↑      ↑        ↑          │
  │       │      │        │          │ reentry (cycle++)
  │       └──────┴────────┘          │
  │              backward            │
  └──────────────────────────────────┘
```

> **tc ≠ test code.** `tc` stands for **test case design** — a specification of *what* to test (given/when/then in JSON), not executable code. Actual test code is generated in the `test` phase by combining the source code + test case designs.

| Phase | What Happens | Artifact | Allowed Writes | Human Role |
|-------|-------------|----------|----------------|------------|
| **spec** | Write requirements (EARS patterns) | `SPEC-*.md` | `.omc/specs/` | Review & approve |
| **tc** | Design test cases **without seeing code** | `TC-*.json` | `.omc/test-cases/` | Review & approve |
| **code** | Implement the feature | Source code | `src/` | Monitor |
| **test** | Generate test code from source + TC, run & iterate | Test files | `src/`, `tests/` | Review failures |
| **verified** | Locked. All tests pass. | — | Nothing | Final sign-off |

The key insight: test case *design* (tc) is deliberately isolated from source code. This ensures tests verify the **specification**, not the implementation.

### Transitions

| Type | When | Cycle |
|------|------|-------|
| **Forward** | Phase complete + human approval | Same |
| **Backward** | Human finds issue (same cycle) | Same |
| **Reentry** | Change needed after `verified` | cycle++ |

## How It Works

### 3-Layer Enforcement: Hooks

proofchain uses a layered enforcement architecture — **Guard, Guide, Gate** — that keeps development smooth while ensuring nothing slips through.

```
Layer 3 [Gate]    Verified transition: full traceability check
                  @tc/@req mapping, supplementary TC schema → BLOCK if incomplete

Layer 2 [Guide]   During development: non-blocking warnings
                  change-log recording, @tc/@req annotation warnings → stderr only

Layer 1 [Guard]   File access control + automatic state correction
                  phase-based write blocking, auto-backward, .claude/ protection → BLOCK or auto-fix
```

**Layer 1 — Guard** (`check-phase.sh`, PreToolUse)

Intercepts every `Edit`, `Write`, and `Bash` call:

```
Claude tries to edit src/auth.ts
  → Hook reads hitl-state.json
  → Area AU is in "spec" phase
  → BLOCKED: src/ writes require "code" or "test" phase
  → Hook outputs available transitions as guidance
```

When a bug is found during test phase and code needs fixing:

```
Claude edits src/auth.ts during "test" phase
  → auto_backward: phase automatically changes test → code
  → Edit is ALLOWED (not blocked)
  → State is accurately tracked
  → Developer flow is uninterrupted
```

**Layer 2 — Guide** (`trace-change.sh`, PostToolUse)

Non-blocking warnings and audit logging:

```
Claude writes tests/unit/AU/auth.test.ts
  → Records to change-log.jsonl (file, area, phase, timestamp)
  → Checks @tc annotations: 5 test functions, only 3 @tc → WARNING
  → Checks phantom refs: @tc TC-AU-004 not in TC JSON → WARNING
  → All warnings are stderr only — never blocks
```

**Layer 3 — Gate** (`check-phase.sh` verified_gate)

Final quality checkpoint before `verified`:

```
Claude sets phase to "verified"
  → Check 1: Every active TC → has @tc annotation in tests? → BLOCK if missing
  → Check 2: Every REQ → has @req annotation in tests? → BLOCK if missing
  → Check 3: Supplementary TC schema valid? → BLOCK if invalid
  → Check 4: Baseline TC given/when/then unchanged since first verified? → BLOCK if modified (cycle > 1)
  → Check 5: Reentry log has type, reason, affected_reqs? → BLOCK if missing (cycle > 1)
  → Check 6: Unmapped files in change-log? → WARN (non-blocking)
  → All pass → verified. Git tag created.
```

### Automatic Git History

Every artifact change is automatically tracked in git — no manual commits needed.

| What Changes | When Committed | Hook | Message Format |
|-------------|---------------|------|---------------|
| SPEC files | Every edit | `artifact-commit.sh` | `[artifact] AU(Auth): SPEC-AU-auth.md [spec, cycle 1]` |
| TC JSON files | Every edit | `artifact-commit.sh` | `[artifact] AU(Auth): TC-AU.json [tc, cycle 1]` |
| Source + tests | Phase transition | `phase-commit.sh` | `[proofchain] AU(Auth): code → test (cycle 1)` |
| Verified milestone | Verified transition | `phase-commit.sh` | Git tag: `AU-verified-c1` |

This provides full artifact history for ISO 26262 compliance:

```bash
git log --grep="artifact"                  # SPEC/TC change history
git log --grep="proofchain"                # Phase transition history
git tag -l "AU-*"                          # Verified milestones
git show AU-verified-c1:src/auth.ts        # Reproduce past state
git diff AU-verified-c1..AU-verified-c2    # Changes between cycles
```

### Workflow Layer: Skills

| Command | Phase | What It Does |
|---------|-------|-------------|
| `/ears-spec` | spec | Guides EARS-pattern requirement writing |
| `/test-gen-design` | tc | Designs test case specs in **isolated context** (never reads `src/`) |
| `/test-gen-code` | test | Generates executable test code from source + TC designs, runs & iterates |
| `/traceability` | any | Generates REQ ↔ TC ↔ Test bidirectional matrix |
| `/frontend-design` | code | Creates production-grade frontend UI designs |
| `/reset` | any | Resets process state and artifacts |

### Rules Layer: CLAUDE.md

Loaded into every Claude Code session, providing state machine rules, phase guidance, and invariant constraints.

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

### Setup

1. **Clone:**

```bash
git clone https://github.com/winehouse8/proofchain.git my-project
cd my-project
```

2. **Create a project branch:**

```bash
git checkout -b project/my-app
```

> **Important:** Never develop directly on `main`. The main branch holds only the framework template.

3. **Configure your project** in `.omc/hitl-state.json`:

```json
{
  "project": {
    "code": "MY",
    "name": "My Project",
    "frameworks": {
      "unit": "vitest",
      "component": "playwright",
      "e2e": "playwright",
      "visual": ""
    },
    "paths": {
      "source": "src/",
      "tests": {
        "unit": "tests/unit/",
        "component": "tests/component/"
      }
    }
  },
  "areas": {},
  "log": []
}
```

4. **Start Claude Code:**

```bash
claude
```

The session begins with a HITL status report. Define your first area and run `/ears-spec` to start.

### Typical Session

```
=== HITL Status ===
AU (Authentication) : spec [cycle 1] → Next: Write SPEC. Use /ears-spec.
DB (Database)       : verified [cycle 1] → Done. Reentry required for changes.

You: "/ears-spec"                    ← Write requirements
You: "Approve" → phase: tc          ← SPEC auto-committed to git

You: "/test-gen-design"              ← Design test cases (isolated, no code access)
You: "Approve" → phase: code        ← TC auto-committed to git

You: "Implement the feature"         ← Write source code in src/
You: "/test-gen-code"                ← Generate test code from src/ + TC, run & iterate
All pass → phase: verified           ← Git tag AU-verified-c1 created

You: "Found a bug in DB"
Claude: Reentry scenarios:
  A. SPEC change needed  → spec  (cycle++)
  B. Code bug (SPEC ok)  → tc    (cycle++)
  C. Test code error     → code  (cycle++)
You: "B" → DB re-enters at tc, cycle 2, full regression required
```

### Reentry: Going Back After Verification

When a bug is found or a change is needed after `verified`, proofchain requires a structured reentry:

| Scenario | Entry Phase | Skipped Phases | Required |
|----------|------------|---------------|----------|
| **A. SPEC change** (new feature, spec error) | spec | None | Full cycle |
| **B. Code bug** (spec is correct) | tc | spec | Justify skip |
| **C. Test code error** | code | spec, tc | Justify skips |

Every reentry:
- Increments the cycle counter (cycle 1 → 2 → 3...)
- Requires `type`, `reason`, and `affected_reqs` in the log
- Skipped phases require `skip_reason` (ISO 26262 Part 8 §8.7)
- Demands **full regression testing** — all existing tests must pass (ISO 26262 Part 6 §9.4.6)
- All changes are git-committed with cycle metadata for audit trail

## Project Structure

```
.claude/
├── hooks/
│   ├── check-phase.sh          Layer 1 Guard + Layer 3 Gate (PreToolUse)
│   ├── trace-change.sh         Layer 2 Guide (PostToolUse)
│   ├── artifact-commit.sh      SPEC/TC auto-commit (PostToolUse)
│   ├── phase-commit.sh         Phase transition auto-commit + tag (PostToolUse)
│   ├── restore-state.sh        Session status reporter (SessionStart)
│   └── checkpoint.sh           State preserver (PreCompact)
├── skills/
│   ├── ears-spec/              SPEC co-pilot (EARS patterns)
│   ├── test-gen-design/        Baseline TC generator (isolated)
│   ├── test-gen-code/          Test code generator + runner
│   ├── frontend-design/        Frontend UI design
│   ├── traceability/           Traceability matrix
│   └── reset/                  Process reset
└── settings.json               Hook wiring

.omc/
├── HITL.md                     Detailed process definition
├── hitl-state.json             Central state (all skills read/write this)
├── change-log.jsonl            File change audit log
├── specs/                      SPEC-{area}-{name}.md
├── test-cases/                 TC-{area}.json
└── traceability/               Traceability matrices

src/                            Source code
tests/                          Test code
├── {unit,component,e2e,visual}/    Test types
│   └── {AREA_CODE}/                Area directory (e.g., AU/, DB/)
│       └── *.test.ts               Test files with @tc/@req annotations
docs/                           Assessment reports

CLAUDE.md                       AI guide prompt (loaded every session)
```

## Key Invariants

1. **Baseline TC Immutability** — After first `verified`, baseline TC content (given/when/then) is frozen. Changes mark them `obsolete` + create supplementary TCs.
2. **TC Isolation** — Test case design never sees source code. Prevents tests that validate implementation rather than specification.
3. **Full Regression** — Every reentry (cycle > 1) requires running ALL tests (ISO 26262 Part 6 §9.4.6).
4. **Skip Justification** — Skipping phases during reentry requires documented reasoning (ISO 26262 Part 8 §8.7).
5. **Verified Lock** — No writes to src/, tests/, specs/, test-cases/ while in `verified` state. Reentry is the only path.
6. **Artifact Version Control** — Every SPEC and TC modification is individually git-committed. Phase transitions are committed with all changed files.
7. **Supplementary TC Quality** — Supplementary TCs require 10 mandatory fields including `added_reason` (minimum 10 characters). Verified gate blocks incomplete TCs.
8. **Code Path Enforcement** — Product code must live in managed paths (`src/`, `tests/`). Code files outside are blocked.
9. **Test Directory Convention** — Test files must follow `tests/{type}/{AREA_CODE}/` pattern (e.g., `tests/unit/AU/auth.test.ts`) for automatic area mapping.
10. **Audit Trail** — Every transition logged with timestamp, actor, reason, and affected requirements.

## ISO 26262 Alignment

| Requirement | Standard | Implementation |
|-------------|----------|---------------|
| Bidirectional traceability | Part 6 §9.3 | REQ ↔ TC ↔ Test Code matrix. Verified gate enforces @tc/@req annotations. `/traceability` generates full matrix. |
| Regression testing | Part 6 §9.4.6 | Full regression mandatory on cycle > 1. `/test-gen-code` Amendment Mode runs all tests. |
| Configuration management | Part 8 §7.4 | Phase-locked file access, baseline TC immutability, git tag at verified milestones, per-artifact git commits. |
| Change impact analysis | Part 8 §8.4 | Reentry logging with `type`, `reason`, `affected_reqs`. Skip justification with `skip_reason`. |
| Skip justification | Part 8 §8.7 | `skip_reason` mandatory when phases are skipped during reentry. |
| Tool qualification | Part 8 §11 | HITL achieves TCL1 (TI2 + TD1). Human-in-the-loop + TC isolation + full regression = no separate tool qualification needed. |

## What It Enforces (Summary)

| Category | Count | Examples |
|----------|-------|---------|
| **Hard blocks** | 16 | Verified lock, phase access control, code path enforcement, .claude/ write protection, baseline TC immutability, reentry log validation |
| **Auto state changes** | 5 | auto_backward, phase commit, verified tag, change-log, artifact commit |
| **Warnings** | 9 | @tc/@req annotation gaps, phantom TC references, unmapped files, invalid transitions |
| **Awareness** | 3 | Session start report, pre-compact checkpoint, artifact commit confirmation |

## Philosophy

proofchain is not a perfect technical barrier — it's a **reasonable control + human oversight** model. The hooks catch accidental violations. The skills guide correct workflows. The human makes all critical decisions.

The enforcement philosophy: **"Track during development, block at the gate."** During code/test phases, you work freely with non-blocking warnings. At verified transition, everything is checked. This preserves fast iteration while ensuring nothing reaches `verified` without full traceability.

This mirrors real safety-critical development: no tool replaces human judgment, but good tooling makes it much harder to accidentally skip steps.

## License

MIT
