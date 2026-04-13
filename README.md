# nginz-njs

`nginz-njs` is a companion project to `nginz`.

Its purpose is to build a reusable **njs + QuickJS module ecosystem** that works with:

- stock nginx with `ngx_http_js_module` / `ngx_stream_js_module`
- `nginz`, where native Zig modules and njs modules can complement each other

This project is **not** a second runtime effort and **not** a Lua replacement project. The runtime direction is already decided by nginx njs plus QuickJS. The job here is to build the ecosystem around it.

## Goal

Create a monorepo of **self-contained njs modules** that are:

- independently usable
- individually testable
- easy to package and document
- suitable for future distribution tooling

The long-term aim is to give `nginz` an OpenResty-like programmable ecosystem without inventing a separate scripting language stack.

## Core design principles

1. **Companion, not replacement**
   - `nginz` stays focused on native Zig modules, lower-level nginx integration, performance-sensitive engines, and platform primitives.
   - `nginz-njs` focuses on policy logic, orchestration, customization, and reusable scripting modules.

2. **Self-contained modules**
   - each module should live in its own directory
   - each module should have its own docs, examples, tests, and nginx-facing entry files

3. **Monorepo, not a single giant package**
   - we want shared conventions, but modules must remain separately understandable and separately shippable

4. **No package manager first**
   - first ship good modules
   - then define packaging conventions
   - only later consider a registry / installer story

5. **Native vs njs boundary**
   - keep WAF core, shared-memory engines, balancer internals, deep stream/TCP logic, and performance-critical scanners native
   - use njs for orchestration, policy logic, gateway composition, and product-specific glue

## What njs already gives us

njs already provides a strong programmable surface, including:

- request/response hooks
- header/body filters
- subrequests
- `ngx.fetch()`
- variables access
- timers
- filesystem access
- `ngx.shared`
- stream APIs
- periodic handlers

So this project should not try to recreate those primitives. It should build **reusable modules on top of them**.

## First candidate modules

The first wave should prove the model with a few practical modules:

### 1. authz

Use njs for:

- path / method / header authorization logic
- JWT / OIDC claim-to-policy mapping
- custom access decisions

Why first:

- policy logic is script-friendly
- strong gateway value
- pairs naturally with native auth modules in `nginz`

### 2. workflow

Use njs for:

- subrequest orchestration
- `ngx.fetch()`-driven enrichment
- gateway workflows
- remote auth / remote config / composition logic

Why first:

- one of the strongest scripting use cases
- hard to justify as one-off native modules repeatedly

### 3. feature-flags

Use njs for:

- experiment routing
- flag evaluation
- rollout policies
- request bucketing

Why first:

- logic-heavy and easy to evolve
- complements canary and traffic modules well

## Proposed repository structure

```text
nginz-njs/
  README.md
  package.json
  modules/
    authz/
    workflow/
    feature-flags/
  scripts/
  tests/
    authz/
    workflow/
    feature-flags/
  registry/
  submodules/
```

## Per-module structure

Each module should remain self-contained.
A module can be preferably a gleam package which depends on `ngs` package, the gleam bindings to njs.
We strive to use FP composibility and immutability features to build the modules.

```text
modules/<name>/
  README.md
  gleam.toml
  module.json
  src/
  test/
  docs/
```

Recommended purpose of each part:

- `module.json`: machine-readable metadata for future packaging/distribution
- `test/`: gleam tests 
- `docs/`: design notes, limitations, and operational guidance

## Shared libraries

- create dedicated gleam package for shared utilities and helpers
- if a helper is too specific to one module, keep it inside that module instead.
- use gleam package dependency

## Suggested early conventions

### module.json

Each module should eventually expose metadata like:

- name
- version
- type (`http`, `stream`, or both)
- entry file
- compatibility notes for nginx / njs versions

### Packaging

Initial packaging can be simple:

- module source files
- `module.json`
- README
- nginx-facing entry files

No installer or registry is required yet.

### Testing

We should aim for:

- integration tests with bun
- module-local tests inside each module

## Immediate next steps

1. formalize `module.json`
2. define minimal authoring conventions for module entry files
3. build the first three modules:
   - `authz`
   - `workflow`
   - `feature-flags`
4. add example and test conventions
5. only then discuss packaging / registry workflow

## Session handoff note

If work resumes in a later session, the current intent is:

- keep `nginz-njs` as a **companion monorepo** beside `nginz`
- focus first on **real njs modules**, not infrastructure theater
- treat njs as the **composition/customization layer** on top of native nginx and nginz primitives
- do not drift into building a parallel Lua-style runtime stack
