# nginz-njs

**Scripted nginx modules in Gleam — functional, type-safe, composable.**

`nginz-njs` is the scripted companion to [`nginz`](https://github.com/kaiwu/nginz). Where `nginz` provides high-performance native modules built in Zig, this monorepo provides the scripted layer: policy logic, orchestration, and product-specific composition — authored in [Gleam](https://gleam.run) and compiled to [njs](https://nginx.org/en/docs/njs/) via [QuickJS](https://bellard.org/quickjs/).

## Why Gleam

njs already gives us a capable scripting surface: request hooks, body filters, subrequests, `ngx.fetch()`, shared dict, and stream APIs. The gap is not the runtime. The gap is **how we author modules on top of it**.

Plain JavaScript works, but it offers no type safety, no structural guarantees, and no natural composability model. Policy logic written in JS drifts toward ad-hoc branching trees that are hard to test and hard to reuse.

Gleam solves this:

- **Type safety at compile time** — authorization rules, routing decisions, flag evaluations are checked before deployment
- **FP composability** — rules are first-class functions; combine them with `all_of`, `any_of`, and pipeline operators
- **Immutability by default** — no shared mutable state; each request flows through a pure transformation pipeline
- **Gleam packages** — each module is independently publishable to [Hex](https://hex.pm), versioned, and reusable

The underlying runtime is still njs + QuickJS. Gleam compiles to ES2020 JavaScript, which njs with QuickJS handles natively. No second runtime, no Lua detour.

## Architecture

```
                 ┌─────────────────────────────────────┐
                 │           nginz (native)             │
                 │  Zig modules: WAF, JWT, OIDC,        │
                 │  ratelimit, healthcheck, canary,      │
                 │  redis, pgrest, consul, ...           │
                 └─────────────────┬───────────────────┘
                                   │ nginx variables, subrequests
                 ┌─────────────────▼───────────────────┐
                 │         nginz-njs (scripted)         │
                 │  Gleam packages → njs modules:       │
                 │  authz, workflow, feature-flags, ... │
                 │  (this repo)                         │
                 └─────────────────┬───────────────────┘
                                   │ Gleam bindings
                 ┌─────────────────▼───────────────────┐
                 │              ngs                     │
                 │  Gleam ↔ njs bindings package        │
                 │  http, stream, crypto, fs, ngx, ...  │
                 └─────────────────────────────────────┘
```

- **nginz** stays focused on native primitives, performance-critical engines, and platform integrations
- **nginz-njs** handles policy logic, orchestration, and product customization
- **[ngs](https://hex.pm/packages/ngs)** provides the typed Gleam bindings to the njs runtime API

## What composability looks like

```gleam
// modules/authz/src/policy.gleam

pub type Decision { Allow  Deny(reason: String) }
pub type Rule = fn(Context) -> Decision

pub fn evaluate(ctx: Context, rules: List(Rule)) -> Decision {
  list.fold_until(rules, Allow, fn(_, rule) {
    case rule(ctx) {
      Allow    -> list.Continue(Allow)
      Deny(r)  -> list.Stop(Deny(r))
    }
  })
}

pub fn method_in(allowed: List(String)) -> Rule {
  fn(ctx) {
    case list.contains(allowed, ctx.method) {
      True  -> Allow
      False -> Deny("method not allowed: " <> ctx.method)
    }
  }
}

pub fn path_prefix(prefix: String) -> Rule {
  fn(ctx) {
    case string.starts_with(ctx.path, prefix) {
      True  -> Allow
      False -> Deny("path not allowed: " <> ctx.path)
    }
  }
}

pub fn all_of(rules: List(Rule)) -> Rule {
  fn(ctx) { evaluate(ctx, rules) }
}
```

Rules are plain functions. You build policies by composing them:

```gleam
let api_policy = all_of([
  method_in(["GET", "POST"]),
  path_prefix("/api"),
  any_of([has_claim("role", "admin"), has_claim("role", "user")]),
])
```

Pure, testable, no hidden state.

## Module catalog

| Module | Purpose | Status |
|---|---|---|
| [`authz`](modules/authz/) | Policy-based authorization: method, path, header, JWT claim rules | scaffold |
| [`workflow`](modules/workflow/) | Subrequest orchestration and `ngx.fetch()`-driven enrichment pipelines | scaffold |
| [`feature_flags`](modules/feature_flags/) | Feature flag evaluation with stable bucketing for A/B routing | scaffold |

## Dev / test / package

### Build pipeline

Each module is an independent Gleam package that targets the `javascript` runtime:

```
modules/<name>/src/*.gleam
        │
        ▼  gleam build --target javascript
modules/<name>/build/dev/javascript/<name>/<name>.mjs
        │
        ▼  Bun.build() (native bundler, no esbuild install needed)
dist/<name>/njs/app.js    ← loaded by nginx via js_import
dist/<name>/nginx.conf    ← example nginx configuration
```

### Commands

```bash
# --- build ---
bun run build                    # build all modules → dist/
bun run build:module authz       # build one module only

# --- unit tests (pure Gleam, no nginx required) ---
bun run test:unit                # gleam test for all modules
bun run test:unit authz          # gleam test for one module
# or directly from a module directory:
cd modules/authz && gleam test

# --- integration tests (requires nginx binary) ---
make                             # build nginx from submodules first
bun run test:int                 # bun test against real nginx, all modules
bun test modules/authz/tests     # one module only
KEEP_LOGS=1 bun test modules/authz/tests  # keep runtime dir for debug

# --- both ---
bun test                         # unit + integration

# --- clean ---
bun run clean                    # remove dist/, build/, manifest.toml
```

### Packaging

There is no publish step yet. The deliverable for each module is:

```
dist/<name>/
  njs/app.js      ← the bundled njs script; load with js_import in nginx
  nginx.conf      ← example configuration
```

Copy `dist/<name>/` to your nginx deployment. The `module.json` at the module root carries version and compatibility metadata for future distribution tooling.

When modules are stable they will be published to [Hex](https://hex.pm) as independent Gleam packages, so users can depend on them directly in their own Gleam njs projects via `gleam add authz`.

### Requirements

- [Gleam](https://gleam.run) >= 1.14.0
- [Bun](https://bun.sh) >= 1.1.0
- nginx with njs + QuickJS engine (see `Makefile` for building from submodules)

## Project structure

```
nginz-njs/
├── modules/
│   ├── authz/              ← each module is a Gleam package
│   │   ├── gleam.toml      ← Gleam project config, declares ngs dependency
│   │   ├── module.json     ← machine-readable metadata for distribution
│   │   ├── nginx.conf      ← example nginx configuration
│   │   ├── src/            ← Gleam source modules
│   │   ├── test/           ← Gleam unit tests (gleam test)
│   │   ├── tests/          ← bun integration tests against real nginx
│   │   └── docs/           ← design notes, limitations, operational guidance
│   ├── workflow/
│   └── feature_flags/
├── scripts/
│   ├── build.js            ← build all/one module: gleam build + Bun.build()
│   ├── test.js             ← gleam unit tests for all/one module
│   ├── harness.js          ← bun integration test harness (nginx lifecycle)
│   └── preload.js          ← bun preload: build before integration tests run
├── registry/
│   └── index.json          ← module catalog
├── dist/                   ← build output (gitignored)
├── submodules/
│   └── nginx/              ← nginx source for building the test binary
└── Makefile                ← builds nginx binary for integration tests
```

## Per-module structure

```
modules/<name>/
├── gleam.toml        Gleam package config; declares ngs as dependency
├── module.json       name, version, nginx/njs compatibility metadata
├── nginx.conf        example nginx config showing the module in use
├── src/
│   ├── <name>.gleam  entry point; exports() returns the JsObject for nginx
│   └── *.gleam       supporting modules (policy, pipeline, evaluation, …)
├── test/
│   └── *_test.gleam  Gleam unit tests — run with `gleam test`
├── tests/
│   └── <scenario>/
│       ├── nginx.conf  scenario-specific nginx config (optional override)
│       └── do.test.js  bun integration test
└── docs/
    └── README.md     design rationale, limitations, operational guidance
```

## Authoring a new module

1. Create the module directory and Gleam package:

```bash
mkdir modules/my_module
cd modules/my_module
gleam new . --name my_module
```

2. Add `ngs` as a dependency in `gleam.toml`:

```toml
[dependencies]
ngs = ">= 1.0.8 and < 2.0.0"
```

3. Write the entry point with an `exports()` function:

```gleam
// src/my_module.gleam
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn handler(r: HTTPRequest) -> Nil {
  r |> http.return_text(200, "OK\n")
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("handler", handler)
}
```

4. Create `module.json`, `nginx.conf`, unit tests, and integration tests.

5. Register the module in `registry/index.json`.

6. Add the module to `scripts/build.js` if it needs special build steps (usually not required).

## Native vs scripted boundary

This project **only** contains scripted modules. The decision rule:

| Build here (scripted) | Build in nginz (native) |
|---|---|
| Policy logic, routing rules, flag evaluation | WAF engine, rate limit counters, shared-memory state |
| JWT claim-to-role mapping | JWT signature verification |
| Subrequest orchestration | Circuit breaker state machine |
| Response templating, body transforms | brotli/zstd compression |
| Webhook signature glue | TLS / ACME certificate management |
| Feature flag evaluation | Upstream balancer internals |

When the performance-critical primitive is native (HMAC, JSON parsing, shared-memory atomics), the surrounding policy belongs here.

## Relationship to nginz roadmap

The nginz roadmap (Sprint 2+) targets a shared-dict native module and an upstream balancer module. When those land, scripted modules in this repo will be able to depend on them:

- `workflow` can use shared dict for caching enrichment results
- `feature_flags` can use shared dict for flag state without an external service
- `authz` can cache introspection results by token hash

This repo intentionally stays ahead of the native layer: scripted modules define what the platform needs, native primitives follow.

## License

Apache-2.0
