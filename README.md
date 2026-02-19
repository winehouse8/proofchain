# proofchain

**ISO 26262-grade software verification for AI-assisted development with Claude Code.**

proofchain turns Claude Code into a disciplined development assistant by enforcing a 5-phase verification loop through [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) and [skills](https://docs.anthropic.com/en/docs/claude-code/skills). Every line of code is traceable to a specification, every test case is designed before seeing the implementation, and every change after verification requires justified reentry with full regression.

The AI writes code. You make decisions. The framework enforces the process.

---

## The Problem

AI coding assistants make it easy to write code fast — and just as easy to skip verification. Without guardrails:

- Tests get written after the code, testing *implementation* instead of *specification*
- Requirements exist only in conversation, with no formal traceability
- "It works" replaces "it's verified" — no regression, no audit trail
- Changes after "done" happen freely, with no impact analysis

proofchain prevents all of this through mechanical enforcement — not by trusting the AI to follow rules, but by making it impossible to violate them.

---

## Core Idea

**SPEC is the single source of truth.** Code and tests are independently derived from the spec.

```
SPEC (requirements)
  ├──→ Test Case Design (what to test — without seeing code)
  │       Baseline TC: "SPEC says X, so we must verify X"
  │
  └──→ Implementation (source code)
          ↓
      Test Code Generation (TC design + source → executable tests)
          ↓
      All pass → verified (locked)
```

The critical insight: **test case design is deliberately isolated from source code.** This ensures tests verify the *specification*, not the *implementation*. If you write tests after seeing the code, you unconsciously test what the code does rather than what it should do.

proofchain enforces this through a two-tier TC model:

| Tier | When Created | Sees Code? | Mutable? | Purpose |
|------|-------------|-----------|----------|---------|
| **Baseline TC** | After SPEC approval | Never | Frozen after first `verified` | Prove SPEC coverage |
| **Supplementary TC** | During coding/testing | Yes | Freely | Strengthen coverage |

Baseline TCs are the contract: "we will test at least this much." Supplementary TCs are reinforcement: "we found more to test." Writing easy tests after seeing code is cheating; adding harder tests is strengthening.

---

## The 5-Phase State Machine

Every development area (a component, feature, or module) progresses through exactly 5 phases:

```
spec ──→ tc ──→ code ──→ test ──→ verified
  ↑       ↑      ↑        ↑          │
  │       │      │        │          │ reentry (cycle++)
  │       └──────┴────────┘          │
  │              backward            │
  └──────────────────────────────────┘
```

### Phases

| Phase | What Happens | Artifact | Allowed Writes | Human Role |
|-------|-------------|----------|----------------|------------|
| **spec** | Write requirements using EARS patterns | `SPEC-*.md` | `.omc/specs/` only | Review & approve |
| **tc** | Design test cases **without seeing source code** | `TC-*.json` | `.omc/test-cases/` only | Review & approve |
| **code** | Implement the feature | Source code | `src/` | Monitor |
| **test** | Generate test code from source + TC, run & iterate | Test files | `src/`, `tests/` | Review failures |
| **verified** | Locked. Nothing can be written. | — | Nothing | Final sign-off |

> **tc ≠ test code.** `tc` is *test case design* — a JSON specification of *what* to test (given/when/then). Actual executable test code is generated in the `test` phase by combining source code + TC designs.

### Transitions

13 transitions are allowed. Everything else is blocked.

| Type | Transitions | Cycle | When |
|------|------------|-------|------|
| **Forward** | spec→tc, tc→code, code→test, test→verified | Same | Phase complete + human approval |
| **Backward** | tc→spec, code→spec, code→tc, test→spec, test→tc, test→code | Same | Human finds issue |
| **Reentry** | verified→spec, verified→tc, verified→code | cycle++ | Change needed after verification |

Any other transition (e.g., spec→code, spec→test) is mechanically blocked. This is not a warning — the write operation is rejected.

### Reentry: Controlled Change After Verification

Once an area reaches `verified`, it's locked. To make any change, you must formally re-enter the state machine:

| Scenario | Entry Phase | Skipped Phases | Justification |
|----------|------------|---------------|---------------|
| **A. SPEC change** (new feature, spec error) | spec | None | Full cycle |
| **B. Code bug** (spec is correct) | tc | spec | Must justify why spec phase is skipped |
| **C. Test code error** | code | spec, tc | Must justify why spec and tc phases are skipped |

Every reentry:
- Increments the cycle counter (cycle 1 → 2 → 3...)
- Requires `type`, `reason`, and `affected_reqs` in the log
- Skipped phases require `skip_reason` (ISO 26262 Part 8 §8.7)
- Demands **full regression testing** — all existing tests must pass
- All changes are git-committed with cycle metadata

---

## How Enforcement Actually Works

### The Single Enforcer

proofchain's entire enforcement depends on **one shell script**: `check-phase.sh`. This is a [PreToolUse hook](https://docs.anthropic.com/en/docs/claude-code/hooks) — it runs *before* every `Edit`, `Write`, and `Bash` call that Claude makes. If it exits with code 2, the operation is blocked.

```
Claude Code                          check-phase.sh
─────────                           ──────────────
  Claude wants to edit src/auth.ts
    → PreToolUse fires ──────────→  Read hitl-state.json
                                    Area AU is in "spec" phase
                                    src/ requires "code" or "test"
                                    ← exit 2 (BLOCKED)
    ← Operation rejected
    Claude sees: "BLOCKED: AU(Auth) — spec [cycle 1]
                  src/ writes require code or test phase"
```

Every other hook is PostToolUse (runs *after* the operation) and **cannot block anything**:

```
Hook                  Type            Can Block?   Role
──────────────        ────            ──────────   ────
check-phase.sh        PreToolUse      YES          The only enforcer
trace-change.sh       PostToolUse     NO           Warnings + audit log
artifact-commit.sh    PostToolUse     NO           Auto git commit for SPEC/TC
phase-commit.sh       PostToolUse     NO           Auto git commit + tag for transitions
restore-state.sh      SessionStart    NO           Status report
checkpoint.sh         PreCompact      NO           State preservation
```

### 3-Layer Architecture

The enforcement is organized in three layers within `check-phase.sh`:

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Gate                                                    │
│ Verified transition only. 8 checks. BLOCK if any fail.          │
│ @tc/@req traceability, TC schema, baseline immutability,         │
│ reentry log, TC existence, transition validation                 │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Guide                        (trace-change.sh)          │
│ Every file change. Non-blocking.                                 │
│ change-log.jsonl, @tc/@req warnings, phantom TC warnings         │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: Guard                                                   │
│ Every Edit/Write/Bash. BLOCK or auto-correct.                    │
│ Phase-based file access, auto-backward, .claude/ protection,     │
│ destructive git blocking, code path enforcement                  │
└─────────────────────────────────────────────────────────────────┘
```

**Layer 1 — Guard** (every operation)

- Phase-based file access: `src/` only writable in code/test, `specs/` only in spec, etc.
- Auto-backward: editing `src/` during test phase automatically transitions to code (no block, no friction)
- `.claude/` self-protection: hooks and skills cannot be modified by the AI
- Destructive git blocking: `git tag -d`, `git checkout .claude/`, `git reset --hard`, `git push --force` are blocked
- Code path enforcement: code files must live in `src/` or `tests/`, not scattered elsewhere

**Layer 2 — Guide** (non-blocking, PostToolUse)

- Records every file change to `change-log.jsonl` with area, phase, timestamp
- Warns when test files lack `@tc` or `@req` annotations
- Warns when `@tc` references a TC ID that doesn't exist in the JSON ("phantom reference")
- Never blocks — all warnings go to stderr

**Layer 3 — Gate** (verified transition only)

When the AI writes `"verified"` to hitl-state.json, `verified_gate()` runs 8 sequential checks:

| Check | What It Verifies | Blocks? |
|-------|-----------------|---------|
| **1** | Every active TC has a matching `@tc` annotation in test code | Yes |
| **2** | Every REQ has a matching `@req` annotation in test code | Yes |
| **3** | Supplementary TCs have all 10 required fields (including `added_reason` ≥ 10 chars) | Yes |
| **4** | Baseline TC given/when/then unchanged since first `verified` (git tag comparison, cycle > 1) | Yes |
| **5** | Reentry log has `type`, `reason`, `affected_reqs`; if phases skipped, `skip_reason` exists (cycle > 1) | Yes |
| **6** | At least 1 active TC exists (not all obsolete, not empty) | Yes |
| **7** | Phase transition is in the allowed 13-transition map; reentry has cycle++ | Yes |
| **8** | Unmapped files in change-log | Warn only |

Checks are sequential — if Check 1 fails, Check 2-8 don't run. Each failure message tells exactly which TCs/REQs are missing and what to do.

### Destructive Git Protection

Four git operations that could undermine the verification chain are blocked:

| Command | Why It's Dangerous | Defense |
|---------|-------------------|---------|
| `git tag -d` | Deletes verified tags → Check 4 (baseline immutability) loses its reference point | Blocked |
| `git checkout/restore .claude/` | Restores old hook versions → all enforcement can be rolled back | Blocked |
| `git reset --hard` | Destroys HITL state, in-progress work, and audit history | Blocked |
| `git push --force` | Destroys remote audit trail | Blocked |

All patterns use `^\s*` anchoring to match only the actual command, not text inside commit messages.

### Phase Transition Validation

When hitl-state.json is written, the hook validates every phase change against the allowed transition map:

```
Allowed:
  Forward:  spec→tc  tc→code  code→test  test→verified
  Backward: tc→spec  code→spec  code→tc  test→spec  test→tc  test→code
  Reentry:  verified→spec  verified→tc  verified→code (cycle++ required)

Blocked (examples):
  spec→code  (skipping tc)
  spec→test  (skipping tc and code)
  tc→test    (skipping code)
  verified→verified  (no-op not needed)
```

If a reentry transition (from `verified`) doesn't increment the cycle counter, it's also blocked.

### Self-Protection

The framework protects itself from modification:

- `Edit`/`Write` to any `.claude/` file → blocked
- `Bash` commands writing to `.claude/` (cp, mv, rm, sed -i, tee, redirect) → blocked
- `git checkout/restore .claude/` → blocked (prevents reverting hooks to old versions)
- Git commands (add, commit, push) are allowed — they're VCS operations, not file writes

---

## Skills: Guided Workflows

Skills are slash-command prompts that guide the AI through each phase. They are **not automatically invoked** — the human chooses when to run them. The hooks enforce the process regardless of whether skills are used.

| Command | Phase | What It Does |
|---------|-------|-------------|
| `/ears-spec` | spec | Guides EARS-pattern requirement writing with structured templates |
| `/test-gen-design` | tc | Designs baseline TCs in **isolated context** (never reads `src/`) |
| `/test-gen-code` | test | Generates executable test code from source + TC, runs with iterative fix loop |
| `/traceability` | any | Generates REQ ↔ TC ↔ Test Code bidirectional matrix |
| `/frontend-design` | code | Creates production-grade frontend UI designs |
| `/reset` | any | Resets process state and artifacts to framework-only |

**Key**: `/test-gen-design` runs with `context: fork`, creating a separate Claude context that cannot access the main conversation's code context. This is the TC isolation mechanism.

---

## Automatic Git History

Every artifact change is automatically committed — no manual git operations needed.

| What Changes | When | Hook | Commit Message |
|-------------|------|------|---------------|
| SPEC files | Every edit | `artifact-commit.sh` | `[artifact] AU(Auth): SPEC-AU-auth.md [spec, cycle 1]` |
| TC JSON files | Every edit | `artifact-commit.sh` | `[artifact] AU(Auth): TC-AU.json [tc, cycle 1]` |
| Source + tests | Phase transition | `phase-commit.sh` | `[proofchain] AU(Auth): code → test (cycle 1)` |
| Verified milestone | Verified transition | `phase-commit.sh` | Git tag: `AU-verified-c1` |

```bash
# Full audit trail available through git
git log --grep="artifact"                  # SPEC/TC change history
git log --grep="proofchain"                # Phase transition history
git tag -l "AU-*"                          # Verified milestones
git show AU-verified-c1:src/auth.ts        # Reproduce any past state
git diff AU-verified-c1..AU-verified-c2    # Exact changes between cycles
```

Verified tags are immutable — `git tag -d` is blocked by the hook, so baselines cannot be retroactively altered.

---

## ISO 26262 Compliance

### Why ISO 26262?

ISO 26262 is the automotive functional safety standard. Its Part 6 (software development) and Part 8 (supporting processes) define the most rigorous publicly available requirements for software verification. proofchain doesn't target automotive — it borrows ISO 26262's rigor as a benchmark for any project that demands verified, traceable software.

### Tool Confidence Level (TCL)

ISO 26262 Part 8 §11 classifies tools by their potential to introduce or fail to detect errors:

```
Tool Impact (TI):     TI2 — proofchain can fail to detect errors
                            (e.g., if AI writes wrong code that passes weak tests)

Tool error Detection (TD): TD1 — high confidence in detecting errors
                                 Human reviews every transition
                                 + 8 mechanical gate checks at verified
                                 + baseline TC immutability
                                 + full regression on reentry

TCL = TI2 + TD1 = TCL1 → No separate tool qualification required
```

### What ISO 26262 Requires vs. What proofchain Provides

| ISO 26262 Requirement | Clause | Enforcement | Level |
|-----------------------|--------|-------------|-------|
| Bidirectional traceability (REQ ↔ TC ↔ Test) | Part 6 §9.3 | Verified gate Check 1-2: @tc/@req annotations | **Mechanical (blocks)** |
| Verification independence | Part 6 §9.4.3 | TC isolation: `/test-gen-design` in fork context, never reads src/ | **Skill (guided)** |
| Regression testing | Part 6 §9.4.6 | `/test-gen-code` Amendment Mode runs all tests on cycle > 1 | **Skill (automatic)** |
| Test for every requirement | Part 6 §10.4.1 | Verified gate Check 1: all active TCs must have @tc in tests | **Mechanical (blocks)** |
| Configuration item identification | Part 8 §7.4.1 | Managed paths: SPEC, TC, src, tests all in defined locations | **Mechanical (blocks)** |
| Baseline establishment | Part 8 §7.4.3 | Git tag `{area}-verified-c{N}` at every verified milestone | **Automatic** |
| Baseline immutability | Part 8 §7.4.3 | Verified gate Check 4: git tag comparison of given/when/then | **Mechanical (blocks)** |
| Change control after verification | Part 8 §7.4.4 | Verified lock: no writes to src/, tests/, specs/, test-cases/ | **Mechanical (blocks)** |
| Configuration status recording | Part 8 §7.4.5 | Per-artifact git commits + phase transition commits | **Automatic** |
| Change request identification | Part 8 §8.4.1 | Verified gate Check 5: reentry log with type, reason, affected_reqs | **Mechanical (blocks)** |
| Phase skip justification | Part 8 §8.7 | Verified gate Check 5: skip_reason required when phases skipped | **Mechanical (blocks)** |

**Score: 9/11 mechanically enforced (blocks), 2/11 skill-guided (automatic when skills are used).**

### What It Doesn't Do

ISO 26262 compliance is not the same as ISO 26262 certification. proofchain does not:

- Generate a formal Tool Classification Report (required for certification)
- Guarantee tamper-proof enforcement (hooks can theoretically be bypassed outside Claude Code)
- Replace human judgment in safety analysis (HARA, FMEA, FTA)
- Certify the AI's output as safe — it certifies the *process* was followed

The framework's position: **hook + JSON + git is a process guardrail, not a security boundary.** ISO 26262 requires process guardrails + human oversight, not tamper-proof tools.

---

## Defense Status

proofchain identifies 7 adversarial scenarios where the AI could theoretically bypass enforcement. Current defense status:

| # | Scenario | Risk | Status | How |
|---|---------|------|--------|-----|
| **A1** | Phase skip (e.g., spec→code) | High | **Defended** | Transition validation map (v3.4) |
| **A2** | Delete verified git tags | High | **Defended** | `git tag -d` blocked (v3.4) |
| **A3** | Restore old hooks via git | Critical | **Defended** | `git checkout .claude/` blocked (v3.4) |
| **A4** | Empty tests with annotations only | High | Undefended | Planned: test execution evidence (Tier 2) |
| **A5** | Verify with zero test cases | Medium | **Defended** | Check 6: active TC > 0 (v3.4) |
| **A6** | Skip skills entirely | Medium | Undefended | Planned: UserPromptSubmit guidance (Tier 3) |
| **A7** | Read src/ during TC design | Medium | Undefended | Planned: PreToolUse Read blocking (Tier 2) |

4/7 scenarios defended. Remaining 3 are documented improvement targets (see `docs/research-enforcement-architecture.md`).

---

## Enforcement Summary

| Category | Count | Examples |
|----------|-------|---------|
| **Hard blocks** | 22 | Verified lock, phase-based file access, transition validation, destructive git blocking, .claude/ self-protection, baseline TC immutability, reentry log validation, TC existence check, code path enforcement |
| **Auto state changes** | 5 | auto_backward (test→code), artifact git commit, phase git commit, verified git tag, change-log recording |
| **Warnings** | 9 | @tc/@req annotation gaps, phantom TC references, unmapped files, hotfix warnings, invalid transition warnings |
| **Awareness** | 3 | Session start status report, pre-compact state checkpoint, /traceability recommendation |

---

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

---

## Project Structure

```
.claude/
├── hooks/
│   ├── check-phase.sh          Layer 1 Guard + Layer 3 Gate (PreToolUse) — the single enforcer
│   ├── trace-change.sh         Layer 2 Guide (PostToolUse)
│   ├── artifact-commit.sh      SPEC/TC auto-commit (PostToolUse)
│   ├── phase-commit.sh         Phase transition auto-commit + tag (PostToolUse)
│   ├── restore-state.sh        Session status reporter (SessionStart)
│   └── checkpoint.sh           State preserver (PreCompact)
├── skills/
│   ├── ears-spec/              SPEC co-pilot (EARS patterns)
│   ├── test-gen-design/        Baseline TC generator (isolated fork context)
│   ├── test-gen-code/          Test code generator + runner + fix loop
│   ├── frontend-design/        Frontend UI design
│   ├── traceability/           Traceability matrix generator
│   └── reset/                  Process reset
└── settings.json               Hook wiring (PreToolUse + PostToolUse + SessionStart + PreCompact)

.omc/
├── HITL.md                     Detailed process definition (state transitions, reentry rules)
├── hitl-state.json             Central state (phase, cycle, area config, transition log)
├── change-log.jsonl            File change audit log (trace-change.sh writes here)
├── specs/                      SPEC-{area}-{name}.md
├── test-cases/                 TC-{area}.json (baseline_tcs + supplementary_tcs)
└── traceability/               Traceability matrices

src/                            Source code (managed path)
tests/                          Test code (managed path)
├── {unit,component,e2e,visual}/    Test types
│   └── {AREA_CODE}/                Area directory (e.g., AU/, DB/)
│       └── *.test.ts               Test files with @tc/@req annotations
docs/                           Assessment and audit reports

CLAUDE.md                       AI guide (loaded every session — state machine rules, invariants)
```

---

## Philosophy

> **"Track during development, block at the gate."**

During code/test phases, you work freely. Layer 2 records changes and warns about missing annotations, but never blocks. When you try to reach `verified`, Layer 3 checks everything. This preserves fast iteration while ensuring nothing reaches `verified` without full traceability.

proofchain is not a perfect technical barrier — it's a **reasonable control + human oversight** model. The hooks catch accidental violations. The skills guide correct workflows. The human makes all critical decisions.

This mirrors real safety-critical development: no tool replaces human judgment, but good tooling makes it much harder to accidentally skip steps. ISO 26262 doesn't require tamper-proof tools — it requires sufficient trust through process guardrails + human supervision. That's exactly what proofchain provides.

---

## Further Reading

- [`docs/research-enforcement-architecture.md`](docs/research-enforcement-architecture.md) — Adversarial scenario analysis, Claude Code API capabilities, and improvement roadmap
- [`docs/re-audit-v3.4.md`](docs/re-audit-v3.4.md) — Comprehensive audit report with ISO 26262 compliance matrix
- [`.omc/HITL.md`](.omc/HITL.md) — Detailed HITL process definition (state transitions, reentry rules, TC tiers)

## License

MIT
