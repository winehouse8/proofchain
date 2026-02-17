# SPEC-PC-CA: Calculator

**Area:** CA (Calculator)
**Cycle:** 1
**Status:** draft

---

## 1. 개요

사칙연산을 수행하는 웹 계산기. 두 수를 입력받아 덧셈, 뺄셈, 곱셈, 나눗셈 결과를 반환한다.

## 2. 요구사항

### REQ-CA-001: 덧셈
**[EARS: Ubiquitous]**
The calculator **shall** return the sum of two numbers when the add operation is invoked.

### REQ-CA-002: 뺄셈
**[EARS: Ubiquitous]**
The calculator **shall** return the difference of two numbers when the subtract operation is invoked.

### REQ-CA-003: 곱셈
**[EARS: Ubiquitous]**
The calculator **shall** return the product of two numbers when the multiply operation is invoked.

### REQ-CA-004: 나눗셈
**[EARS: Ubiquitous]**
The calculator **shall** return the quotient of two numbers when the divide operation is invoked.

### REQ-CA-005: 0으로 나누기 방어
**[EARS: If-Then]**
If the divisor is zero, the calculator **shall** return an error message "Cannot divide by zero" instead of performing the division.

### REQ-CA-006: 소수점 처리
**[EARS: Ubiquitous]**
The calculator **shall** handle floating-point numbers and return results with up to 10 decimal places of precision.

## 3. 범위 외

- 히스토리 기능
- 괄호 연산
- 메모리 기능 (M+, M-, MR)
