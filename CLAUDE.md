# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`nginz-njs` is a monorepo of scripted nginx modules authored in [Gleam](https://gleam.run) and compiled to [njs](https://nginx.org/en/docs/njs/) (QuickJS engine). It is the scripted companion to `nginz` (native Zig modules at `../nginz`). The nginz ROADMAP governs what belongs here vs. native — policy logic, orchestration, and gateway composition are scripted here; hot-path primitives stay native.

The Gleam bindings to the njs runtime are provided by the [`ngs`](https://hex.pm/packages/ngs) package (local copy at `/home/kaiwu/Documents/cgit/ngs`).

## Core design rule: modules are building blocks

Every module in this repo has two distinct surfaces:

1. **Reusable Gleam library surface** — the `pub` types and functions under `src/<name>/...`
2. **Final njs surface** — the `pub fn exports() -> JsObject` entrypoint in `src/nginz_njs_<name>.gleam`

The project encourages FP composibility and modularity, a highly reusable component might not have its own `exports()` at all.
Aggressive refactors are appreciated when real reusable components get minted in the njs domain.

Treat the first surface as the primary design target. Modules are meant to be used by other Gleam modules inside/outside this monorepo as long as they expose clean public interfaces. The `exports()` function is the final adapter layer for nginx and is also what integration tests exercise today.

Design implication: do not build modules as isolated handler scripts when the logic should be reusable. Build the reusable Gleam core first, then adapt it through `exports()`. Example: `workflow` should consume `http_client` as a Gleam building block instead of owning a separate fetch abstraction.

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

### Integration tests
```bash
# Basic scenarios — standard nginx, always runnable
bun run test:int                       # modules/*/tests/basic/do.test.js
bun test modules/authz/tests/basic/do.test.js  # one file
KEEP_LOGS=1 bun test modules/authz/tests/basic/do.test.js  # keep dist/<module>/logs/ for debug

# Native module scenarios — requires nginx rebuilt with nginz modules
make                                   # zig build package -Doptimize=ReleaseSmall + nginx configure + make
bun run test:native                    # all scenarios including jwt, enrich, etc.
```

### Both unit + basic integration
```bash
bun run test                           # unit tests + basic integration tests (no native deps)
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
  → append: export default exports()     ← njs js_import needs the default export
  → dist/<name>/njs/app.js   (loaded by nginx via js_import)
  → dist/<name>/nginx.conf   (copied from module root)
```

`scripts/build.js` drives this for all modules or a named one. It discovers modules by listing `modules/` directories.

Read this pipeline carefully: the Gleam package is built first, and only the final `exports()` entrypoint is bundled into the njs artifact. Keep that separation visible in code structure.

### Module layout

Every module in `modules/<name>/` is an independent Gleam package. The directory name is the short form (e.g., `authz`); the Gleam package name uses the `nginz_njs_` prefix for Hex.pm uniqueness (e.g., `nginz_njs_authz`).

```
modules/<name>/
  gleam.toml              name = "nginz_njs_<name>", target = "javascript"
  nginx.conf              example nginx config
  src/
    nginz_njs_<name>.gleam   entry point — final njs adapter; must export pub fn exports() -> JsObject
    <name>/                  reusable library modules (namespaced to avoid import path collisions)
      *.gleam
  test/
    nginz_njs_<name>_test.gleam  gleeunit entry (must match package name exactly)
  tests/
    <scenario>/
      nginx.conf           scenario-specific nginx config for integration test
      do.test.js           bun integration test
  docs/README.md
```

`scripts/build.js` reads the `name` field from `gleam.toml` to locate the compiled entry mjs at `build/dev/javascript/<package_name>/<package_name>.mjs`.

When adding functionality, prefer putting real logic under `src/<name>/...` with clean `pub` interfaces, and keep `src/nginz_njs_<name>.gleam` thin. If another module could plausibly use the logic directly, it belongs in the reusable library surface rather than in the `exports()` adapter.

**Test scenario naming convention:**
- `tests/basic/` — standard nginx only; runs with `bun run test:int` and `bun run test`
- `tests/<feature>/` (e.g., `tests/jwt/`, `tests/enrich/`) — requires native modules from `make`; runs with `bun run test:native`

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

Every module's `src/nginz_njs_<name>.gleam` must export:
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

`js_path "njs/"` resolves relative to the nginx config file's directory. The harness copies test scenario configs into `dist/<name>/nginx.conf` before starting nginx (so `njs/` resolves to `dist/<name>/njs/` where `app.js` lives). Nginx prefix is `dist/<name>/` — logs land in `dist/<name>/logs/`.

This entry point is the final deployment boundary, not the place where most module logic should live.

### Integration test harness

`scripts/harness.js` manages nginx lifecycle. Tests import it with a path relative to the test file:
```javascript
import { startNginx, stopNginx, cleanupRuntime, TEST_URL } from "../../../../scripts/harness.js";

const CONF = join(import.meta.dir, "nginx.conf");  // use import.meta.dir for CWD independence
await startNginx(CONF, MODULE);  // starts nginx; runtime dir → dist/<name>/runtime/
```

`scripts/preload.js` (loaded by `bunfig.toml`) triggers a build before any bun integration test suite runs.

### Gleam integer arithmetic in compiled JS

Gleam compiles to JS but `int.bitwise_exclusive_or` uses the gleam_stdlib helper which applies 32-bit semantics via JS `^` for in-range operands. Regular `*` is float, so values exceeding `Number.MAX_SAFE_INTEGER` lose precision. Hash functions that accumulate state across many characters (like FNV-1a) **must wrap each multiplication** via `int.remainder(h * prime, modulus)` where `modulus = 4_294_967_296` to stay in 32-bit range. See `feature_flags/evaluation.gleam`.

### Native vs scripted boundary

Follow the nginz ROADMAP (`../nginz/ROADMAP.md`) and `../nginz/docs/design-native-vs-scripted.md`:
- **Here**: policy rules, subrequest orchestration, JWT claim mapping, flag evaluation, response templating, webhook glue
- **In nginz**: WAF engine, rate limit counters, shared-memory state, upstream balancer internals, TLS/ACME, brotli/zstd

### Module catalog and roadmap priority

`ROADMAP.md` has the full scripted module roadmap. Module metadata (name, version, native deps) lives in each module's `gleam.toml` under `[metadata]`. Priority order:
1. `http_client` — `ngx.fetch()` wrapper (no native dependency, highest leverage)
2. `workflow` — subrequest orchestration (scaffolded)
3. `feature_flags` — stable bucketing (scaffolded)
4. `authz` — FP design reference; JWT claims need the native `jwt` module in the binary
5. `session` — targets njs built-in `ngx.shared` for runtime backing

The `Makefile` builds native modules from `submodules/nginz/` using `zig build package`. Default: `echoz jwt`. Override with `make NGINZ_MODULES="echoz jwt requestid"`.
