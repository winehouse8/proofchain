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

| Phase | What Happens | Allowed Writes | Human Role |
|-------|-------------|----------------|------------|
| **spec** | Write requirements (EARS patterns) | `.omc/specs/` | Review & approve |
| **tc** | Generate baseline test cases (isolated) | `.omc/test-cases/` | Review & approve |
| **code** | Implement the feature | `src/`, `tests/` | Monitor |
| **test** | Run tests, iterate on failures | `src/`, `tests/` | Review failures |
| **verified** | Locked. All tests pass. | Nothing | Final sign-off |

### Transitions

| Type | When | Cycle |
|------|------|-------|
| **Forward** | Phase complete + human approval | Same |
| **Backward** | Human finds issue (same cycle) | Same |
| **Reentry** | Change needed after `verified` | cycle++ |

## How It Works

### Enforcement Layer: Hooks

A `PreToolUse` hook (`check-phase.sh`) intercepts every `Edit`, `Write`, and `Bash` call:

```
Claude tries to edit src/auth.ts
  → Hook reads hitl-state.json
  → Area AU is in "spec" phase
  → BLOCKED: src/ writes require "code" or "test" phase
  → Hook outputs available transitions as guidance
```

It also blocks:
- **Code files outside managed paths** — writing `./hack.ts` instead of `src/hack.ts` is caught (70+ extensions)
- **`.claude/` modifications** — the framework protects itself from AI tampering
- **Shared file conflicts** — files mapped to multiple areas are checked against all

### Workflow Layer: Skills

| Command | Phase | What It Does |
|---------|-------|-------------|
| `/ears-spec` | spec | Guides EARS-pattern requirement writing |
| `/test-gen-design` | tc | Generates baseline TCs in **isolated context** (never reads `src/`) |
| `/test-gen-code` | code→test | Generates test code, runs tests, iterates (max 5 retries) |
| `/traceability` | any | Generates REQ ↔ TC ↔ Test bidirectional matrix |
| `/reset` | any | Resets process state and artifacts |

### Rules Layer: CLAUDE.md

Loaded into every Claude Code session, providing state machine rules, phase guidance, and invariant constraints.

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

### Setup

1. **Clone into your project root:**

```bash
git clone https://github.com/winehouse8/proofchain.git my-project
cd my-project
```

2. **Configure your project** in `.omc/hitl-state.json`:

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

3. **Start Claude Code:**

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
You: "Approve" → phase: tc

You: "/test-gen-design"              ← Generate test cases (isolated)
You: "Approve" → phase: code

You: Implement feature               ← Write code
You: "/test-gen-code"                ← Generate + run tests
All pass → phase: verified

You: "Found a bug in DB"
Claude: Reentry scenarios:
  A. SPEC change needed  → spec  (cycle++)
  B. Code bug (SPEC ok)  → tc    (cycle++)
  C. Test code error     → code  (cycle++)
You: "B" → DB re-enters at tc, cycle 2
```

## Project Structure

```
.claude/
├── hooks/
│   ├── check-phase.sh          Phase guard (PreToolUse)
│   ├── restore-state.sh        Status reporter (SessionStart)
│   └── checkpoint.sh           State preserver (PreCompact)
├── skills/
│   ├── ears-spec/               SPEC co-pilot
│   ├── test-gen-design/         Baseline TC generator
│   ├── test-gen-code/           Test code generator + runner
│   ├── traceability/            Traceability matrix
│   └── reset/                   Process reset
└── settings.json                Hook wiring

.omc/
├── HITL.md                      Detailed process definition
├── hitl-state.json              State (all skills read/write this)
├── specs/                       SPEC-{code}-{area}.md
├── test-cases/                  TC-{area}.json
└── traceability/                Traceability matrices

CLAUDE.md                        Framework rules (loaded every session)
```

## Key Invariants

1. **Baseline TC Immutability** — After first `verified`, baseline TC content is frozen. Changes mark them `obsolete` + create supplementary TCs.
2. **TC Isolation** — Test case design never sees source code. Prevents tests that validate implementation rather than specification.
3. **Full Regression** — Every reentry (cycle > 1) requires running ALL tests (ISO 26262 Part 6 §9.4.6).
4. **Skip Justification** — Skipping phases during reentry requires documented reasoning (ISO 26262 Part 8 §8.7).
5. **Audit Trail** — Every transition logged with timestamp, actor, reason, and affected requirements.
6. **Code Path Enforcement** — Product code must live in managed paths (`src/`, `tests/`). Code files outside are blocked.

## ISO 26262 Alignment

| Requirement | Implementation |
|-------------|---------------|
| Part 6 §9.3 — Traceability | REQ ↔ TC ↔ Test Code bidirectional matrix (`/traceability`) |
| Part 6 §9.4.6 — Regression testing | Full regression mandatory on cycle > 1 |
| Part 8 §7.4.1 — Configuration management | Phase-locked file access, baseline TC immutability |
| Part 8 §8.7 — Change impact analysis | Reentry logging with `affected_reqs`, `skip_reason` |

## Philosophy

proofchain is not a perfect technical barrier — it's a **reasonable control + human oversight** model. The hooks catch accidental violations. The skills guide correct workflows. The human makes all critical decisions.

This mirrors real safety-critical development: no tool replaces human judgment, but good tooling makes it much harder to accidentally skip steps.

## License

MIT
