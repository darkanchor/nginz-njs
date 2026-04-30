# nginz_njs_response_transform

Response transformation scaffold for nginx written in Gleam. The long-term goal is a reusable body-shaping library that can be composed from other modules such as `workflow` and `webhook`, with `exports()` acting only as the final nginx adapter.

## Roadmap position

`response_transform` is a Tier-2 module in `ROADMAP.md`. It has no native blocker and belongs in the scripted layer because field masking, conditional JSON mutation, and application-specific shaping are policy-heavy composition problems rather than hot-path primitives.

## Design goals

- keep transformation plans as pure values
- make operation ordering explicit and testable
- let `workflow` and `webhook` compose this module rather than embedding body-shaping logic
- keep the nginx-facing entrypoint thin and focused on demo/integration wiring

## What is implemented

**`response_transform/plan.gleam`**
- `Operation` — transform steps such as `MaskField`, `DropField`, and `RenameField`
- `Plan` — a named ordered collection of operations
- `demo_plan` and `summary` — pure scaffold helpers used by tests and handlers

**`nginz_njs_response_transform.gleam`**
- `describe` — returns a stable summary of the demo transform plan
- `preview_plan` — returns a stable textual preview through `js_content`

**Integration tests**
- `tests/basic/` — verifies both scaffold handlers return stable responses with stock nginx only

## Core abstractions

- `Operation` — the atomic transformation step
- `Plan` — the ordered reusable transformation program
- future transform evaluators and body adapters — effectful execution should layer on top of the pure plan model, not replace it

The architectural rule for this module is: transformation semantics belong in a reusable Gleam library surface; nginx body-filter wiring is only the last adapter layer.

## Cross-module composition boundary

- `workflow` should orchestrate upstream calls and then compose `response_transform` when shaping responses
- `webhook` can reuse `response_transform` for callback normalization or outbound payload shaping
- `authz` may later reuse response-shaping helpers for denied-response formatting, but should not own transform logic

## Scripted core vs optional native integration

### Scripted core

- transform plan construction
- field masking and renaming policy
- conditional shaping semantics
- reusable composition helpers

### Optional native integration

- none required for the baseline scaffold
- a native transform primitive could later complement this module, but should not replace policy-level composition here

## Phased implementation plan

### Phase 1 — stabilize the transform plan model

Goal: define pure reusable values before implementing real body filters.

- [ ] expand `Operation` to cover path-based field access and conditional transforms
- [ ] keep plan construction deterministic and summary/debug helpers testable
- [ ] add pure validation for invalid or conflicting transform plans

### Phase 2 — add pure preview/evaluation helpers

Goal: let callers reason about transform semantics before wiring nginx filters.

- [ ] add pure preview helpers for JSON/object-like structures
- [ ] add plan composition helpers that preserve ordering explicitly
- [ ] document how `workflow` should consume the library surface rather than duplicate shaping logic

### Phase 3 — add nginx/body-filter adapters

Goal: connect reusable plans to real request/response flow.

- [ ] add the first body-filter adapter around the pure plan model
- [ ] support response status/body coupling where needed
- [ ] keep adapter errors separate from transform semantics

### Phase 4 — add richer transform policies

Goal: make the module useful for real product output shaping.

- [ ] add conditional rules based on headers, status, or metadata
- [ ] add JSON-specific helpers and path-based operations
- [ ] keep orchestration in `workflow`, not inside transform execution

## TDD plan

- [ ] unit-test plan summaries and operation ordering first
- [ ] add pure tests for future plan validation and preview helpers before nginx wiring
- [ ] keep the first body-filter adapter behind targeted integration tests

## Atomic commit strategy

- [ ] `response_transform: add pure plan model scaffold`
- [ ] `response_transform: add preview and evaluation helpers`
- [ ] `response_transform: add first body-filter adapter`
- [ ] `docs: document workflow and webhook composition patterns`

## Verification checklist

- [ ] `bun scripts/test.js response_transform` — unit tests pass
- [ ] `bun test modules/response_transform/tests/basic/do.test.js` — basic integration passes
