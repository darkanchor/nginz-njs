# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`nginz-njs` is a monorepo of scripted nginx modules authored in [Gleam](https://gleam.run) and compiled to [njs](https://nginx.org/en/docs/njs/) (QuickJS engine). It is the scripted companion to `nginz` (native Zig modules at `../nginz`). The nginz ROADMAP governs what belongs here vs. native — policy logic, orchestration, and gateway composition are scripted here; hot-path primitives stay native.

The Gleam bindings to the njs runtime are provided by the [`ngs`](https://hex.pm/packages/ngs) package (local copy at `/home/kaiwu/Documents/cgit/ngs`).

## Commands

### Unit tests (pure Gleam, no nginx needed)
```bash
bun scripts/test.js                    # all modules
bun scripts/test.js authz             # one module

# or directly in a module directory:
cd modules/authz && gleam test
```

### Build (Gleam → bundle → dist/)
```bash
bun scripts/build.js                  # all modules
bun scripts/build.js authz           # one module
```

### Integration tests (requires nginx binary)
```bash
make                                   # build nginx from submodules first (one-time)
bun test 'modules/**/tests/**/*.test.js'   # all modules
bun test modules/authz/tests           # one module
KEEP_LOGS=1 bun test modules/authz/tests  # preserve runtime dir for debugging
```

### Both unit + integration
```bash
bun test                               # runs scripts/test.js then bun integration tests
```

### Clean
```bash
bun run clean                          # removes dist/, modules/*/build/, modules/*/manifest.toml
```

## Architecture

### Build pipeline

```
modules/<name>/src/*.gleam
  → gleam build --target javascript
  → modules/<name>/build/dev/javascript/<name>/<name>.mjs
  → Bun.build() (bundle, ESM, browser target)
  → dist/<name>/njs/app.js   (loaded by nginx via js_import)
  → dist/<name>/nginx.conf   (copied from module root)
```

`scripts/build.js` drives this for all modules or a named one. It discovers modules by listing `modules/` directories.

### Module layout

Every module in `modules/<name>/` is an independent Gleam package:

```
modules/<name>/
  gleam.toml          target = "javascript", [javascript] runtime = "bun"
  module.json         distribution metadata (name, version, exports, nginx/njs compat)
  nginx.conf          example nginx config
  src/
    <name>.gleam      entry point — must export pub fn exports() -> JsObject
    <name>/           submodules (namespaced to avoid import path collisions)
      *.gleam
  test/
    <name>_test.gleam gleam unit tests (gleeunit, must match package name exactly)
  tests/
    <scenario>/
      nginx.conf      scenario-specific nginx config for integration test
      do.test.js      bun integration test
  docs/README.md
```

### Gleam import path rules

Within a Gleam package named `foo`:
- `src/foo.gleam` → module `foo` (the entry point)
- `src/foo/bar.gleam` → module `foo/bar` (importable as `import foo/bar`)
- `src/bar.gleam` → module `bar` — **avoid this**: it has no namespace and creates ambiguity for external consumers

Always put submodules under `src/<package-name>/`. The `ngs` package demonstrates this pattern: all bindings live under `src/njs/` giving them the `njs/` import prefix.

### Gleam type import syntax (Gleam 1.x)

Custom types require separate imports for the type and the constructor:
```gleam
import foo/bar.{type MyType, MyType}  // type annotation + constructor both
```
Closures returned as function type aliases need explicit annotations or Gleam cannot infer the parameter type:
```gleam
pub fn my_rule() -> Rule {
  fn(ctx: Context) -> Decision { ... }  // explicit, not fn(ctx) { ... }
}
```

### njs entry point pattern

Every module's `src/<name>.gleam` must export:
```gleam
pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("handler_name", handler_fn)
}
```

nginx config loads it as:
```nginx
js_engine qjs;
js_path "njs/";
js_import main from app.js;
location / { js_content main.handler_name; }
```

`js_path` is resolved relative to the nginx config file's directory (not the `-p` prefix). Integration tests use `js_path "njs/"` with the config at `dist/<name>/nginx.conf` and prefix at `dist/<name>/runtime/`.

### Integration test harness

`scripts/harness.js` manages nginx lifecycle. Tests import it with a path relative to the test file:
```javascript
import { startNginx, stopNginx, cleanupRuntime, TEST_URL } from "../../../../scripts/harness.js";

const CONF = join(import.meta.dir, "nginx.conf");  // use import.meta.dir for CWD independence
await startNginx(CONF, MODULE);  // starts nginx; runtime dir → dist/<name>/runtime/
```

`scripts/preload.js` (loaded by `bunfig.toml`) triggers a build before any bun integration test suite runs.

### Native vs scripted boundary

Follow the nginz ROADMAP (`../nginz/ROADMAP.md`) and `../nginz/docs/design-native-vs-scripted.md`:
- **Here**: policy rules, subrequest orchestration, JWT claim mapping, flag evaluation, response templating, webhook glue
- **In nginz**: WAF engine, rate limit counters, shared-memory state, upstream balancer internals, TLS/ACME, brotli/zstd

### Module catalog and roadmap priority

`registry/index.json` lists current modules. Roadmap priority (from nginz design doc):
1. `http_client` — `ngx.fetch()` wrapper (no native dependency, highest leverage)
2. `workflow` — subrequest orchestration (scaffolded)
3. `feature_flags` — stable bucketing (scaffolded)
4. `session` — blocked on nginz shared-dict native module
5. `authz` — blocked on nginz JWT native module for claim variables; exists as FP design reference
