# nginz-njs

**Scripted nginx modules in Gleam — functional, type-safe, composable.**

`nginz-njs` is a collection of scripted nginx modules authored in [Gleam](https://gleam.run) and compiled to [njs](https://nginx.org/en/docs/njs/) via [QuickJS](https://bellard.org/quickjs/). It works with stock, unmodified nginx — no custom binary required. Optionally pairs with [`nginz`](https://github.com/kaiwu/nginz) native modules (built in Zig) when you need signature verification, rate counters, or other performance-critical primitives alongside the scripted policy layer.

## Why Gleam

njs already gives us a capable scripting surface: request hooks, body filters, subrequests, `ngx.fetch()`, shared dict, and stream APIs. The gap is not the runtime. The gap is **how we author modules on top of it**.

Plain JavaScript works, but it offers no type safety, no structural guarantees, and no natural composability model. Policy logic written in JS drifts toward ad-hoc branching trees that are hard to test and hard to reuse.

Gleam solves this:

- **Type safety at compile time** — authorization rules, routing decisions, flag evaluations are checked before deployment
- **FP composability** — rules are first-class functions; combine them with `all_of`, `any_of`, and pipeline operators
- **Immutability by default** — no shared mutable state; each request flows through a pure transformation pipeline
- **Gleam packages** — each module is independently publishable to [Hex](https://hex.pm), versioned, and reusable

The underlying runtime is still njs + QuickJS. Gleam compiles to ES2020 JavaScript, which njs with QuickJS handles natively. No second runtime, no Lua detour.

## Modules are building blocks first

Every module in this repo has two distinct surfaces:

1. a **reusable Gleam library surface** under `src/<name>/...`, made of clean `pub` types and functions
2. a **final njs interface** in `src/nginz_njs_<name>.gleam`, exposed through `pub fn exports() -> JsObject`

The project encourages FP composibility and modularity, a highly reusable component might not have its own `exports()` at all.

The first surface is the real product. Modules are meant to be used by other Gleam modules inside/outside this monorepo as ordinary building blocks, as long as they expose stable public interfaces. The `exports()` function is the last-mile adapter that turns those building blocks into an nginx-facing njs module and, in this repo today, is also what integration tests exercise.

So we should not design modules as isolated one-off nginx scripts. We should design reusable Gleam packages that can also be exported to nginx. For example, `workflow` should be able to depend on and use `http_client` as a Gleam library, rather than re-owning fetch logic at the handler layer.

## Architecture

nginx is the center. Both `nginz` and `nginz-njs` are independent module sets that plug into stock, unmodified nginx — neither depends on the other.

```
  ┌──────────────────────────┐        ┌──────────────────────────────────┐
  │      nginz (native)      │        │       nginz-njs (scripted)       │
  │  Zig modules compiled    │        │  Gleam packages compiled to njs: │
  │  into nginx via          │        │  authz, workflow, feature_flags, │
  │  --add-module:           │        │  http_client (this repo)         │
  │  jwt, echoz, waf,        │        │                                  │
  │  ratelimit, canary, ...  │        │  built on ngs — typed Gleam      │
  └────────────┬─────────────┘        │  bindings to the njs runtime API │
               │ --add-module         └──────────────┬───────────────────┘
               │                                     │ js_import / js_content
               ▼                                     ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │                        nginx  (stock, unmodified)                      │
  │              njs + QuickJS engine built in via --add-module            │
  └────────────────────────────────────────────────────────────────────────┘
```

Both module sets are fully compatible with the official nginx distribution. You can use neither, either, or both together — they compose through standard nginx primitives: variables, locations, subrequests, and the njs scripting surface.

When used together, native modules handle the performance-critical work (signature verification, rate counters, shared-memory state) and expose results as nginx variables; scripted modules read those variables and apply policy logic in Gleam.

Inside `nginz-njs` itself, composability happens at the Gleam module boundary first. The deployable nginx module is the outer shell around a reusable Gleam package.

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

At the repo level, composability should also look like this:

- `http_client` provides request/response and fetch primitives
- `workflow` builds orchestration on top of those primitives
- `authz` can use `http_client` for external decision points without owning the HTTP client abstraction itself
- `feature_flags` stays a pure evaluation building block that other modules can call directly from Gleam
- `response_transform` should shape bodies for `workflow` or `webhook` rather than owning orchestration
- `webhook` should compose `http_client` for delivery and `response_transform` for payload shaping
- `session` should provide reusable session facts that `authz` and `feature_flags` can consume
- `mlcache` should provide reusable cache semantics for `authz`, `feature_flags`, `webhook`, and `session`
- `metrics` should be the reusable instrumentation surface consumed by other modules

In other words: **`exports()` is the adapter layer, not the whole module design.**

## Module catalog

| Module | Purpose | Status |
|---|---|---|
| [`nginz_njs_http_client`](modules/http_client/) | Typed request-building scaffold for a future `ngx.fetch()` wrapper | scaffold |
| [`nginz_njs_authz`](modules/authz/) | Policy-based authorization: method, path, header, JWT claim rules | scaffold |
| [`nginz_njs_workflow`](modules/workflow/) | Subrequest orchestration and `ngx.fetch()`-driven enrichment pipelines | scaffold |
| [`nginz_njs_feature_flags`](modules/feature_flags/) | Feature flag evaluation with stable bucketing for A/B routing | scaffold |
| [`nginz_njs_session`](modules/session/) | Session-state scaffold with reusable session modeling and explicit shared-dict blocker | scaffold |
| [`nginz_njs_mlcache`](modules/mlcache/) | Two-level cache scaffold with reusable cache semantics and explicit shared-dict blocker | scaffold |
| [`nginz_njs_response_transform`](modules/response_transform/) | Response/body-shaping scaffold for reusable transform plans | scaffold |
| [`nginz_njs_webhook`](modules/webhook/) | Webhook signing and verification scaffold built for composition with http_client | scaffold |
| [`nginz_njs_metrics`](modules/metrics/) | Metrics formatting and forwarding scaffold for cross-module instrumentation | scaffold |

## Setup

### 1. Clone with submodules

```bash
git clone --recurse-submodules https://github.com/kaiwu/nginz-njs.git
# or, after a plain clone:
git submodule update --init --recursive
```

This initializes four submodules:

| Path | Contents |
|---|---|
| `submodules/nginx` | nginx source |
| `submodules/njs` | njs scripting engine |
| `submodules/quickjs` | QuickJS engine (used by njs) |
| `submodules/nginz` | Native Zig modules (echoz, jwt, …) |

### 2. Build nginx with native modules

```bash
make                                      # default: echoz + jwt
make NGINZ_MODULES="echoz jwt requestid"  # add more nginz modules
```

What `make` does:

1. **Builds QuickJS** (`libquickjs.a`) from `submodules/quickjs`
2. **Builds nginz native modules** via `zig build package -Doptimize=ReleaseSmall` in `submodules/nginz` — produces `zig-out/modules/<name>/` with a linkable object file for each module
3. **Configures and builds nginx** with `--add-module` flags for njs and each selected nginz module

The resulting binary is at `submodules/nginx/objs/nginx`. The `Makefile` symlinks or exports `NGINX_BIN` so the integration test harness picks it up automatically.

**This step is a prerequisite for native-module integration tests** (`bun run test:native`). Basic integration tests (`bun run test:int`) and unit tests (`bun run test:unit`) work without it.

### 3. Activate git hooks

```bash
git config core.hooksPath .githooks
```

This installs a pre-push hook that runs `gleam format` across all modules before every push, keeping CI's format check green.

### 4. Tool requirements

- [Gleam](https://gleam.run) >= 1.14.0
- [Bun](https://bun.sh) >= 1.1.0
- [Zig](https://ziglang.org) >= 0.14.0 (only needed for `make`)

## Dev / test / package

### Build pipeline

Each module is an independent Gleam package that targets the `javascript` runtime:

```
modules/<name>/src/*.gleam
        │
        ▼  gleam build --target javascript
modules/<name>/build/dev/javascript/nginz_njs_<name>/nginz_njs_<name>.mjs
        │
        ▼  Bun.build() (native bundler, no esbuild install needed)
        ▼  append: export default exports()
dist/<name>/njs/app.js    ← loaded by nginx via js_import
dist/<name>/nginx.conf    ← example nginx configuration
```

The important implication is that `gleam build` produces a normal reusable Gleam package first, and only then do we bundle the package's final `exports()` entrypoint into the njs artifact loaded by nginx.

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

# --- integration tests ---
bun run test:int                 # basic scenarios (standard nginx, always works)
bun test modules/authz/tests/basic/do.test.js  # one scenario
KEEP_LOGS=1 bun test modules/authz/tests/basic/do.test.js  # keep logs for debug

# --- native module integration tests (requires rebuilt nginx) ---
make                             # build nginx with echoz + jwt from submodules/nginz
bun run test:native              # all scenarios including native-module tests

# --- both (unit + basic integration) ---
bun run test                     # unit tests + basic integration tests

# --- clean ---
bun run clean                    # remove dist/, build/, manifest.toml
```

### Deploying a module

Build output lands in `dist/<name>/njs/app.js`. There are two ways to deploy it:

**DIY (most flexible):** copy `dist/<name>/njs/app.js` to your nginx host and adapt `dist/<name>/nginx.conf` to fit your existing config.

**Helper script:**

```bash
bun run deploy authz /etc/nginx/conf.d/authz
# or directly:
bun scripts/deploy.js authz /etc/nginx/conf.d/authz
```

The script copies `app.js` to `<dest>/njs/app.js`, prints the nginx config snippet to load the module, and warns if your nginx binary is missing any required native modules (declared in `[metadata] native_modules` in `gleam.toml`).

When modules are stable they will be published to [Hex](https://hex.pm) as independent Gleam packages — versioning and dependency metadata live in `gleam.toml`. Users can depend on them directly via `gleam add nginz_njs_authz`.

## Project structure

```
nginz-njs/
├── modules/
│   ├── authz/              ← directory name; Gleam package is nginz_njs_authz
│   │   ├── gleam.toml      ← package config (name, version, ngs dependency)
│   │   ├── nginx.conf      ← example nginx configuration
│   │   ├── src/            ← Gleam source modules
│   │   ├── test/           ← Gleam unit tests (gleam test)
│   │   ├── tests/          ← bun integration tests against real nginx
│   │   └── docs/           ← design notes, limitations, operational guidance
│   ├── http_client/
│   ├── workflow/
│   └── feature_flags/
├── scripts/
│   ├── build.js            ← build all/one module: gleam build + Bun.build()
│   ├── deploy.js           ← copy app.js to dest, print nginx snippet, check native deps
│   ├── test.js             ← gleam unit tests for all/one module
│   ├── harness.js          ← bun integration test harness (nginx lifecycle)
│   └── preload.js          ← bun preload: build before integration tests run
├── ROADMAP.md              ← scripted module roadmap
├── dist/                   ← build output (gitignored)
├── submodules/
│   ├── nginx/              ← nginx source
│   ├── njs/                ← njs scripting engine
│   ├── quickjs/            ← QuickJS engine
│   └── nginz/              ← native Zig modules (echoz, jwt, …)
└── Makefile                ← builds nginx + selected nginz native modules
```

## Per-module structure

```
modules/<name>/
├── gleam.toml        package name "nginz_njs_<name>", version, ngs dependency
├── nginx.conf        example nginx config showing the module in use
├── src/
│   ├── nginz_njs_<name>.gleam  final njs adapter; exports() returns the JsObject for nginx
│   └── <name>/                 reusable library modules with clean `pub` interfaces
│       └── *.gleam
├── test/
│   └── nginz_njs_<name>_test.gleam  Gleam unit tests (gleeunit entry)
├── tests/
│   └── <scenario>/
│       ├── nginx.conf  scenario-specific nginx config
│       └── do.test.js  bun integration test
└── docs/
    └── README.md     design rationale, limitations, operational guidance
```

## Authoring a new module

1. Create the module directory and Gleam package with the `nginz_njs_` prefix:

```bash
mkdir modules/my_module
cd modules/my_module
gleam new . --name nginz_njs_my_module
```

2. Add `ngs` as a dependency in `gleam.toml`:

```toml
[dependencies]
ngs = ">= 1.0.8 and < 2.0.0"
```

3. Rename the generated entry file and write the `exports()` function:

```bash
mv src/nginz_njs_my_module.gleam src/nginz_njs_my_module.gleam  # already correct
mv test/nginz_njs_my_module_test.gleam test/nginz_njs_my_module_test.gleam
```

```gleam
// src/nginz_njs_my_module.gleam
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

4. Add `[metadata.native]` to `gleam.toml` declaring any required native nginx modules, namespaced by source:

```toml
[metadata.native]
nginz = ["jwt"]   # omit the section entirely if no native deps
```

`bun scripts/build.js` reads this and fails early if the declared modules are absent from the nginx binary. `bun scripts/deploy.js` reads the same data to warn operators and print the correct `make` command.

5. Create `nginx.conf`, unit tests in `test/`, and integration tests in `tests/<scenario>/`.

When authoring a module, keep the `exports()` file thin. If another module could plausibly reuse the logic, it belongs under `src/<name>/...` as part of the building-block surface rather than inside the nginx adapter.

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

## Relationship to nginz

`nginz` is included as a submodule at `submodules/nginz/`. The `Makefile` builds selected native modules (default: `echoz`, `jwt`) via `zig build package` and links them into the nginx binary. The set of active modules is controlled by the `NGINZ_MODULES` variable:

```bash
make                              # build with default: echoz jwt
make NGINZ_MODULES="echoz jwt requestid"  # extend the set
```

Scripted modules in this repo orchestrate and compose the native primitives:

- `nginz_njs_http_client` is the typed scripted wrapper layer over built-in `ngx.fetch()`
- `nginz_njs_authz` uses JWT claim variables exposed by the native `jwt` module
- `nginz_njs_workflow` drives subrequests through nginx locations backed by native modules
- `nginz_njs_feature_flags` will use shared-dict state once the native `shared_dict` module lands

See [ROADMAP.md](ROADMAP.md) for the scripted module roadmap.

## License

Apache-2.0
