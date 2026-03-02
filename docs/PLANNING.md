Here are the core planning documents to guide LLM agents through the napi-mojo build.

---

### README.md

# NAPI-Mojo: Node.js Addons in Mojo

**Project Goal:** To create a safe, ergonomic, and high-performance library for building Node.js native addons in the Mojo programming language. This project aims to be the Mojo equivalent of Rust's `napi-rs`.

## 🚀 Guiding Principles

1. **Safety First:** Provide a safe abstraction layer over the C-based N-API.
2. **Ergonomics:** Offer a user-friendly API that feels natural to Mojo developers.
3. **Performance:** Leverage Mojo's performance features to enable high-speed native modules.

## 📂 Project Structure

- `/src`: All Mojo source code.
- `/tests`: All JavaScript Jest tests.
- `/examples`: Standalone JavaScript usage examples.
- `/build`: Compiled output (`index.node`).
- `package.json`: Node.js project configuration.
- `build.sh`: The compilation script.

## 🛠️ Development Process

This project strictly follows a test-driven development pattern. For details on the development workflow and contribution standards, please see:

- **`METHODOLOGY.md`**: Our core TDD workflow.
- **`CONTRIBUTING.md`**: The standards and rules for all contributions.

---

### METHODOLOGY.md

# Development Methodology

This project follows a strict **JavaScript-Driven, "Outside-In" Test-Driven Development (TDD)** pattern. This approach ensures that all development is guided by the needs of the end-user (the JavaScript developer) and that our FFI boundary is continuously validated.

## 🔄 The TDD Workflow

Every new feature or bug fix must follow this three-step cycle:

### **1. RED 🔴: Write a Failing JavaScript Test**

Before any Mojo code is written, a new test must be added to a file in the `/tests` directory using the Jest framework. This test should describe the desired functionality from the perspective of a JavaScript consumer and will fail because the feature does not yet exist.

### **2. GREEN 🟢: Write Mojo Code to Pass the Test**

Next, write the minimum amount of Mojo code necessary in the `/src` directory to make the failing test pass. This may involve creating new public functions, private wrappers, and updating the module registration. The goal is simply to satisfy the test's requirements.

### **3. REFACTOR 🔵: Clean Up the Mojo Code**

With a passing test, the Mojo implementation can be refactored with confidence. This step involves improving code quality, enhancing safety, adding documentation, and aligning the code with our project standards, all while ensuring the test continues to pass.

This cycle is mandatory for all contributions. It provides a clear definition of done and guarantees that our library is both correct and robust.

---

### CONTRIBUTING.md

# Contributor's Guide

This document outlines the standards and rules for all contributions to the `napi-mojo` project, especially for LLM agents acting as pair programmers. Adherence to these standards is required.

## ⭐ Core Directives

1. **Safety is Paramount**: The primary goal is to build a safe boundary over the N-API. Every FFI call that can fail **must** be checked.
2. **Explain Everything**: Code without explanation is incomplete. All contributions must clearly explain the "what" and the "why."
3. **Follow the Methodology**: All development must adhere to the TDD pattern described in `METHODOLOGY.md`.
4. **Reference the Source**: The [official Node.js N-API documentation](https://nodejs.org/api/n-api.html) is the single source of truth for all N-API functionality.

## ✍️ Technical Standards

### **Mojo Code**

- **Naming**: `UpperCamelCase` for types (structs, traits), `snake_case` for functions and variables.
- **Error Handling**: All fallible public functions must use the `raises` keyword. Internal N-API errors must be converted to our custom `NapiError` type.
- **Documentation**: All public items must have `##` docstrings. `unsafe` blocks must be accompanied by a comment explaining their necessity and safety invariants.

### **N-API Interaction**

- **Status Checks**: Every N-API call that returns a `napi_status` **must** be immediately checked by our internal error-handling helpers.
- **Memory Management**: All `napi_value` handles must be created within a `HandleScope` abstraction to prevent memory leaks.

### **Interaction Protocol (for LLM Agents)**

- **Structure**: When providing code, present the complete code block first, followed immediately by a clear explanation.
- **Justification**: When choosing an implementation strategy, briefly justify it with respect to our project goals and standards.
- **Clarity**: If a prompt is ambiguous, ask for clarification before proceeding with an implementation.
