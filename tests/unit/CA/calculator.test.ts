import { describe, it, expect } from 'vitest';
import { add, subtract, multiply, divide, power } from '../../../src/calculator';

// TC-CA-001: 덧셈 — 양수 + 양수 (REQ-CA-001)
describe('add', () => {
  it('TC-CA-001: 양수 + 양수 → 합계 반환', () => {
    expect(add(2, 3)).toBe(5);
  });

  // TC-CA-002: 덧셈 — 음수 포함 (REQ-CA-001)
  it('TC-CA-002: 음수 + 음수 → 합계 반환', () => {
    expect(add(-1, -4)).toBe(-5);
  });

  // TC-CA-003: 덧셈 — 소수점 (REQ-CA-001, REQ-CA-006)
  it('TC-CA-003: 소수점 덧셈 → 부동소수점 오차 허용', () => {
    expect(add(0.1, 0.2)).toBeCloseTo(0.3);
  });
});

// TC-CA-004 ~ TC-CA-005: 뺄셈 (REQ-CA-002)
describe('subtract', () => {
  it('TC-CA-004: 기본 뺄셈', () => {
    expect(subtract(10, 3)).toBe(7);
  });

  it('TC-CA-005: 음수 결과', () => {
    expect(subtract(3, 10)).toBe(-7);
  });
});

// TC-CA-006 ~ TC-CA-007: 곱셈 (REQ-CA-003)
describe('multiply', () => {
  it('TC-CA-006: 기본 곱셈', () => {
    expect(multiply(4, 5)).toBe(20);
  });

  it('TC-CA-007: 0 포함 곱셈', () => {
    expect(multiply(7, 0)).toBe(0);
  });
});

// TC-CA-008 ~ TC-CA-010: 나눗셈 (REQ-CA-004, REQ-CA-005, REQ-CA-006)
describe('divide', () => {
  it('TC-CA-008: 기본 나눗셈', () => {
    expect(divide(10, 2)).toBe(5);
  });

  it('TC-CA-009: 소수점 결과 (10자리)', () => {
    expect(divide(1, 3)).toBe(0.3333333333);
  });

  it('TC-CA-010: 0으로 나누기 → 에러 메시지', () => {
    expect(divide(5, 0)).toBe('Cannot divide by zero');
  });
});

// TC-CA-011 ~ TC-CA-013: 거듭제곱 (REQ-CA-007, REQ-CA-008) [supplementary, cycle 2]
describe('power', () => {
  it('TC-CA-011: 기본 거듭제곱', () => {
    expect(power(2, 3)).toBe(8);
  });

  it('TC-CA-012: 0승 → 1', () => {
    expect(power(5, 0)).toBe(1);
  });

  it('TC-CA-013: 음수 지수 → 역수', () => {
    expect(power(2, -2)).toBe(0.25);
  });
});
