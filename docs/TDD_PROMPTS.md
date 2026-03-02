# A set of prompts to follow the **JavaScript-Driven, "Outside-In" TDD** pattern.

---

### **Preamble for the LLM Agent**

"We will now begin the systematic development of the napi-mojo library. We will
adhere strictly to a **JavaScript-Driven, 'Outside-In' TDD** pattern. For each
new feature, our workflow will be:

1. **RED**: First, you will be prompted to write a failing JavaScript test using
   Jest that describes the new functionality.
2. **GREEN**: Second, you will be prompted to write the minimal Mojo code
   required to make that specific test pass.
3. **REFACTOR**: Finally, we will refactor the Mojo code for safety and clarity,
   ensuring the test still passes.

You must adhere to the 'Standards Guide for LLM Agent Contributions' in all
responses."

---

### **Phase 0: Foundation & Environment Setup**

#### **Prompt 1: Generate package.json with Testing**

"Generate the initial package.json file for the napi-mojo project. The file must
define:

- Project name: napi-mojo
- Version: 0.1.0
- Scripts:
  - build: Executes bash build.sh.
  - test: Executes jest.
- As a development dependency, include jest.

Adhere to standard JSON formatting."

---

#### **Prompt 2: Generate Build Script**

"Generate the initial build.sh script for Linux/macOS. This script must:

1. Compile the Mojo source file at src/lib.mojo into a shared library at
   build/libnapi\_mojo.so using mojo build \-shared.
2. Rename the output file to build/index.node.
3. Include comments explaining each step."

---

### **Phase 1: "Hello, World" (TDD Cycle 1\)**

#### **Prompt 3: Write Failing Test for hello() (RED)**

"This is our first feature. In a new file tests/basic.test.js, write a Jest test
for a function named hello on our addon. The test should:

1. require the addon from ../build/index.node.
2. Call addon.hello().
3. Assert that the result is strictly equal to the string 'Hello from Mojo\!'.

This test is expected to fail because the addon and function do not exist yet."

---

#### **Prompt 4: Implement Mojo hello() to Pass Test (GREEN)**

"The hello() test is failing as expected. Now, generate the complete Mojo source
code for src/lib.mojo to make the test pass.

This code must:

1. Use **raw sys.ffi.external\_call** for all N-API interactions.
2. Define the minimal opaque structs (napi\_env, napi\_value, etc.) and the
   descriptive napi\_property\_descriptor struct.
3. Implement a Mojo function hello\_fn that calls napi\_create\_string\_utf8 to
   produce the required string.
4. Implement the napi\_register\_module\_v1 entry point to export the hello\_fn
   with the name hello.

Follow all rules in the standards guide. The goal is simply to make the test
from Prompt 3 pass."

---

### **Phase 2: Refactoring for Safety (REFACTOR)**

#### **Prompt 5: Implement Safety Abstractions and Refactor**

"The hello() test is passing, but the implementation uses raw FFI calls. We will
now refactor for safety without changing the external behavior.

Generate the updated Mojo code for src/lib.mojo that:

1. Defines our custom NapiError struct and an internal \_check\_status(...)
   helper function that raises an error on N-API failure.
2. Creates a new private, safe wrapper function, \_create\_string\_utf8(...),
   which uses \_check\_status.
3. Refactors the existing hello\_fn to use this new safe wrapper.

After this refactoring, the existing hello() test in tests/basic.test.js must
still pass."

---

### **Phase 3: Add createObject (TDD Cycle 2\)**

#### **Prompt 6: Write Failing Test for createObject() (RED)**

"Time for our next feature. In a new test file tests/object.test.js, write a
failing Jest test for a function named createObject.

The test should call addon.createObject() and assert that:

1. The result is of type object.
2. The result is not null.
3. The number of keys in the object is 0."

---

#### **Prompt 7: Implement Mojo createObject() to Pass Test (GREEN)**

"The createObject() test is now failing. Update the src/lib.mojo source to make
this new test pass.

You must:

1. Create a new private, safe wrapper \_napi\_create\_object(...) that uses our
   \_check\_status helper.
2. Implement a new public Mojo function create\_object\_fn that uses the safe
   wrapper.
3. Add a new napi\_property\_descriptor to the list in
   napi\_register\_module\_v1 to export this new function with the name
   createObject.

The existing 'hello' test must also continue to pass."
