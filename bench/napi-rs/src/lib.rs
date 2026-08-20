//! The napi-rs half of the comparison.
//!
//! Every function mirrors the semantics of its napi-mojo counterpart in
//! src/addon/ EXACTLY — same argument types, same return values, same string
//! lengths — because the thing being measured is per-call boundary overhead,
//! and a difference in what the callee does would contaminate it.
//!
//! Kept idiomatic on purpose: this is what a napi-rs user actually writes,
//! macros and all. Hand-rolling raw napi_ calls here would beat the framework
//! being compared and would not represent anyone's real code.

#![deny(clippy::all)]

use napi::bindgen_prelude::*;
use napi_derive::napi;

/// Mirrors `hello()` — a fixed 16-byte string, same length as "Hello from Mojo!".
///
/// `&'static str`, NOT `String`. napi-mojo's hello() uses JsString.create_literal,
/// which hands napi a pointer straight into .rodata. Returning an owned String
/// here would make Rust do a heap allocation and copy that Mojo never does, and
/// the comparison would be measuring that allocation rather than the boundary.
#[napi]
pub fn hello() -> &'static str {
  "Hello from Rust!"
}

/// Mirrors `greet(name)` — "Hello, {name}!".
#[napi]
pub fn greet(name: String) -> String {
  format!("Hello, {}!", name)
}

/// Mirrors `add(a, b)` — two f64 in, one f64 out.
#[napi]
pub fn add(a: f64, b: f64) -> f64 {
  a + b
}

/// Mirrors `addInts(a, b)` — type-checked i32 addition.
#[napi]
pub fn add_ints(a: i32, b: i32) -> i32 {
  a + b
}

/// Mirrors `isPositive(n)`.
#[napi]
pub fn is_positive(n: f64) -> bool {
  n > 0.0
}

/// Mirrors `getNull()`.
#[napi]
pub fn get_null() -> Null {
  Null
}

/// Mirrors `createObject()` — an empty object.
#[napi]
pub fn create_object<'env>(env: &'env Env) -> Result<Object<'env>> {
  Object::new(env)
}

/// Mirrors `makeGreeting()` — `{ message: "Hello!" }`.
#[napi]
pub fn make_greeting<'env>(env: &'env Env) -> Result<Object<'env>> {
  let mut obj = Object::new(env)?;
  obj.set("message", "Hello!")?;
  Ok(obj)
}

/// Mirrors `getProperty(obj, key)`.
#[napi]
pub fn get_property<'env>(obj: Object<'env>, key: String) -> Result<Unknown<'env>> {
  obj.get_named_property::<Unknown>(&key)
}

/// Mirrors `strictEquals(a, b)`.
#[napi]
pub fn strict_equals(env: &Env, a: Unknown, b: Unknown) -> Result<bool> {
  env.strict_equals(a, b)
}
