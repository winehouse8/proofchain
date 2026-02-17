/**
 * Calculator — REQ-CA-001 ~ REQ-CA-006
 */

export function add(a: number, b: number): number {
  return a + b;
}

export function subtract(a: number, b: number): number {
  return a - b;
}

export function multiply(a: number, b: number): number {
  return a * b;
}

export function divide(a: number, b: number): number | string {
  if (b === 0) {
    return "Cannot divide by zero";
  }
  return parseFloat((a / b).toFixed(10));
}
