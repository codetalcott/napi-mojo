# Development Methodology

This project follows a strict **JavaScript-Driven, "Outside-In" Test-Driven Development (TDD)** pattern. All development is guided by the needs of the end-user (the JavaScript developer), and the FFI boundary is continuously validated by tests.

## The TDD Workflow

Every new feature must follow this three-step cycle:

### 1. RED: Write a Failing JavaScript Test

Before any Mojo code is written, add a test in `/tests` using Jest. The test describes desired functionality from the JavaScript consumer's perspective. It will fail because the feature doesn't exist yet.

### 2. GREEN: Write Mojo Code to Pass the Test

Write the minimum Mojo code in `/src` to make the failing test pass. The goal is only to satisfy the test's requirements — no extra abstractions yet.

### 3. REFACTOR: Clean Up the Mojo Code

With a passing test as a safety net, improve code quality, enhance safety, add documentation, and align with project standards — all while keeping the test green.

This cycle is mandatory. It provides a clear definition of done and guarantees correctness at the FFI boundary.

## Spike Phase

Before TDD cycles begin, a **spike** (`spike/ffi_probe.mojo`) validates the core FFI mechanism. The spike is throwaway code that answers: "Can a Mojo shared library call N-API functions from the Node.js host process?" The TDD cycles only begin after the spike confirms this works.
