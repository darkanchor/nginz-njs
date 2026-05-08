# nginz_njs_response_templating

Lightweight response generation and rendering for nginx written in Gleam. This module generates fresh text responses from templates and request/runtime facts; it complements `response_transform`, which mutates payloads that already exist.

## Use Case

**The problem**: sometimes nginx should produce the response itself. You may want a friendly maintenance page, a richer deny response, a small diagnostic endpoint, or a JSON/text fragment assembled from request context and runtime facts.

**How it solves it**: this module gives you a simple template model and a rendering layer that fills named placeholders from request variables or explicit values. That keeps response generation reusable and testable instead of scattering string-building across handlers. It is small on purpose, but it creates a clean place for response generation to live.

**When you would use this**: use it when nginx should generate a response directly rather than only proxying or mutating one. It is a good fit for maintenance pages, small operator endpoints, deny/allow explanations, and lightweight edge-rendered text or JSON fragments.

## Roadmap position

`response_templating` is a Milestone 3 standalone module in `ROADMAP.md`. It exists because response generation is a real library surface of its own, distinct from `response_transform`'s job of mutating existing payloads.

## Design goals

- keep templates and bindings as pure values
- make rendering deterministic and testable without nginx
- keep request-variable lookup at the nginx adapter boundary
- complement `response_transform`, not replace it

## What is implemented

**`response_templating/model.gleam`**
- `Template` — named template with ordered placeholder tokens
- `TemplateKind` — distinguishes text and JSON template outputs
- `Binding` — `Value(name, value)` pairs used for rendering
- `demo_template()` — stable demo template for scaffold verification
- `demo_json_template()` — JSON demo template for handler and contract proof
- `summary()` — human-readable template summary

**`response_templating/render.gleam`**
- `render(template, bindings)` — fills `{{name}}` placeholders from bindings
- `render_safe(template, bindings)` — preserves missing placeholders as `{{name}}`
- `render_with_defaults(template, bindings)` — defaults missing placeholders to their names
- `binding(name, value)` — helper constructor
- `bindings_to_dict(bindings)` — rendering support helper

**`response_templating/vars.gleam`**
- `from_request(r, names)` — build bindings from nginx request variables
- `from_dict(dict)` — turn string-keyed runtime facts into bindings
- `merge(base, overrides)` — combine binding sets with override precedence

**`response_templating/registry.gleam`**
- `Registry` / `new()` — named template registry
- `register()`, `lookup()`, `names()`, `summary()` — registry helpers used by route summaries and selection flows

**`response_templating/conditional.gleam`**
- `select()` — choose a template by name with fallback
- `render_if()` — render one of two templates from a boolean condition
- `select_by_status()` — choose a template using `<prefix>_<status>` / `<prefix>_default` lookup

**`nginz_njs_response_templating.gleam`**
- `describe` — returns a stable summary of the demo template
- `render_demo` — renders the demo template with static values
- `render_safe_demo` — shows safe rendering when bindings are partial
- `render_from_request` — renders using `$arg_name` / `$arg_mode` request variables with safe defaults
- `render_json_demo` — renders a JSON response with request-backed values
- `render_from_vars` — renders from nginx variables using the template placeholder list

**Integration tests**
- `tests/basic/` — describe, demo render, safe render, request-backed render, JSON render, and nginx-variable-backed render paths with stock nginx

## Core abstractions

- `Template` — the reusable response-generation value
- `Binding` — explicit placeholder/value binding
- `render` — deterministic generation over explicit inputs

Architectural rule: `response_templating` generates fresh output; `response_transform` edits output that already exists.

## Typical nginx usage

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /describe {
            js_content main.describe;
        }

        location /render {
            js_content main.render_demo;
        }

        location /render-safe {
            js_content main.render_safe_demo;
        }

        location /render-json {
            js_content main.render_json_demo;
        }

        location /from-request {
            js_content main.render_from_request;
        }

        location /from-vars {
            set $name "Casey";
            js_content main.render_from_vars;
        }
    }
}
```

## Phased implementation plan

### Phase 1 — establish the pure template model ✓

- [x] add `Template` and `Binding` as reusable values
- [x] add deterministic rendering for simple named placeholders
- [x] keep the first milestone text-focused and testable without nginx

### Phase 2 — add nginx request adapters (scaffold)

- [x] add `js_content` handlers for summary and demo rendering
- [x] add request-variable-backed rendering through `http.get_variable`
- [x] add richer response helpers for status/body/content-type composition
- [x] add JSON-oriented templating helpers once the first text path is proven useful

## TDD plan

- [x] unit-test template summaries and placeholder replacement
- [x] unit-test missing-binding behavior stays stable
- [x] integration-test describe/demo/request render handlers via `tests/basic/`
- [x] integration-test JSON/safe/variable-backed render handlers via `tests/basic/`

## Verification checklist

- [x] `bun scripts/test.js response_templating`
- [x] `bun test modules/response_templating/tests/basic/do.test.js`
- [x] `bun run build:module response_templating`

## Current HTTP contract

- `GET /describe`, `GET /render`, `GET /render-safe`, `GET /from-request`, and `GET /from-vars` return `200` text responses.
- `GET /render-json` returns `200` with `Content-Type: application/json`.
- `render_from_request` pulls values from `$arg_name` / `$arg_mode` and falls back to `guest` / `standard`.
- `render_from_vars` pulls values from nginx variables named after the template placeholders and falls back to the placeholder name when a variable is absent.
