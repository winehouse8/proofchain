# EARS Patterns Reference

EARS (Easy Approach to Requirements Syntax) defines 6 patterns. Each pattern fits a specific behavioral context.

## 1. Ubiquitous

**Template**: The `<system>` shall `<action>`.

For behavior that holds at all times, with no trigger or condition.

**Example**:
- The system shall display gate labels in English.
- The playground shall support undo for all user actions.

**Anti-pattern**: Do not use for conditional behavior. If there is a trigger or state, use Event-Driven or State-Driven.

## 2. Event-Driven

**Template**: When `<trigger>`, the `<system>` shall `<action>`.

For behavior triggered by a discrete event (click, message, signal).

**Example**:
- When the user drops a gate onto the canvas, the playground shall create a gate instance at the drop position.
- When the simulation starts, the engine shall evaluate all gates in topological order.

**Trigger must be**: observable, instantaneous, unambiguous.

## 3. State-Driven

**Template**: While `<state>`, the `<system>` shall `<action>`.

For behavior that persists as long as a condition holds.

**Example**:
- While the simulation is running, the playground shall highlight active wires in green.
- While the canvas is in read-only mode, the playground shall disable drag operations.

**State must be**: a named, testable condition with clear entry/exit.

## 4. Unwanted Behavior

**Template**: If `<unwanted condition>`, then the `<system>` shall `<action>`.

For error handling, recovery, or abnormal situations.

**Example**:
- If a wire creates a circular dependency, then the engine shall reject the connection and display an error.
- If the server is unreachable, then the playground shall switch to offline mode.

**Condition must be**: something that should NOT happen in normal flow but must be handled.

## 5. Optional Feature

**Template**: Where `<feature is enabled>`, the `<system>` shall `<action>`.

For behavior tied to a configuration or optional feature flag.

**Example**:
- Where truth table display is enabled, the playground shall show the truth table for the selected gate.
- Where dark mode is active, the playground shall render the canvas with a dark background.

**Use sparingly**: Most requirements should not be optional.

## 6. Complex (Combined)

**Template**: While `<state>`, when `<trigger>`, the `<system>` shall `<action>`.

Combines state and event. Use when behavior depends on both.

**Example**:
- While the simulation is running, when the user modifies a gate input, the engine shall re-evaluate the circuit within 100ms.
- While the canvas is in wiring mode, when the user clicks an output port, the playground shall start a new wire from that port.

**Rule**: Only combine State + Event. Do not chain more than two conditions.

---

## Pattern Selection Guide

```
Does the behavior always apply?
  YES → Ubiquitous
  NO  → Is there a trigger event?
          YES → Is there also a state condition?
                  YES → Complex (State + Event)
                  NO  → Event-Driven
          NO  → Is there a continuous state?
                  YES → State-Driven
                  NO  → Is it error/abnormal handling?
                          YES → Unwanted Behavior
                          NO  → Is it configurable?
                                  YES → Optional Feature
                                  NO  → Ubiquitous (re-evaluate)
```

## Writing Rules

1. **One "shall" per requirement**: Split compound behaviors into separate REQs
2. **Active voice**: "The system shall display" not "The display shall be shown"
3. **Measurable**: Replace vague terms (fast, large, user-friendly) with numbers
4. **Testable**: Every requirement must be verifiable by at least one test type
5. **No implementation**: Describe WHAT, not HOW (no "using React", "via REST API")
