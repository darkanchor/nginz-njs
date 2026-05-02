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
- `Binding` — `Value(name, value)` pairs used for rendering
- `demo_template()` — stable demo template for scaffold verification
- `summary()` — human-readable template summary

**`response_templating/render.gleam`**
- `render(template, bindings)` — fills `{{name}}` placeholders from bindings
- `binding(name, value)` — helper constructor
- `bindings_to_dict(bindings)` — rendering support helper

**`nginz_njs_response_templating.gleam`**
- `describe` — returns a stable summary of the demo template
- `render_demo` — renders the demo template with static values
- `render_from_request` — renders using `$arg_name` / `$arg_mode` request variables with safe defaults

**Integration tests**
- `tests/basic/` — describe, demo render, and request-backed render paths with stock nginx

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

        location /from-request {
            js_content main.render_from_request;
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
- [ ] add richer response helpers for status/body/content-type composition
- [ ] add JSON-oriented templating helpers once the first text path is proven useful

## TDD plan

- [x] unit-test template summaries and placeholder replacement
- [x] unit-test missing-binding behavior stays stable
- [x] integration-test describe/demo/request render handlers via `tests/basic/`

## Verification checklist

- [ ] `bun scripts/test.js response_templating`
- [ ] `bun test modules/response_templating/tests/basic/do.test.js`
- [ ] `bun run build:module response_templating`
