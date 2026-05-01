# nginz_njs_response_transform

Response transformation library for nginx written in Gleam. Reusable plan-based field masking, dropping, renaming, and conditional shaping for JSON response bodies, with a `js_body_filter` adapter for nginx and no native dependency.

## Roadmap position

`response_transform` is a Tier-2 module in `ROADMAP.md`. No native blocker — all logic is scripted. The body-filter adapter uses njs `js_body_filter` + `js_header_filter` (for Content-Length clearing before chunked transfer takes over).

## Design goals

- keep transformation plans as pure values
- make operation ordering explicit and testable
- let `workflow` and `webhook` compose this module rather than embedding body-shaping logic
- keep the nginx-facing entrypoint thin and focused on adapter wiring

## What is implemented

**`response_transform/plan.gleam`**
- `Operation` — `MaskField`, `DropField`, `RenameField`, `SetField`, `WhenStatus`
- `Plan` — named ordered list of operations
- `PlanError` — `EmptyPlan`, `ConflictingOperations(String)`
- `demo_plan`, `summary`, `validate`, `compose`

**`response_transform/eval.gleam`**
- `apply(plan, fields)` — apply all operations to a `Dict(String, String)` field map
- `apply_at_status(plan, status, fields)` — same, but also evaluates `WhenStatus` ops matching the given status code

**`response_transform/body.gleam`**
- `filter(plan, r, data, flags)` — `js_body_filter` adapter; parses JSON body, applies plan, re-encodes
- `filter_with_status(plan, status, r, data, flags)` — same, with status-conditional ops
- `parse_object(body)` — parse a flat JSON object to `Dict(String, String)` (string values only)
- `encode_object(fields)` — encode back to a JSON object string
- Non-parseable bodies (e.g. non-string field values) pass through unchanged

**`nginz_njs_response_transform.gleam`**
- `describe` — stable plan summary
- `preview_plan` — plan summary prefixed with "preview: "
- `clear_content_length` — `js_header_filter` that removes the upstream Content-Length so nginx falls back to chunked transfer after body mutation
- `transform` — body filter handler; applies `demo_plan()` to the response body
- `transform_with_status` — body filter handler that also reads `$status` for conditional ops

**Integration tests**
- `tests/basic/` — describe and preview_plan handlers with stock nginx
- `tests/transform/` — `js_body_filter` pipeline with a two-server setup verifying mask/drop/rename against a live response body

## API reference

### `response_transform/plan`

| Function | Description |
|---|---|
| `demo_plan()` | Default plan: mask `user.email`, drop `internal.trace`, rename `user.id` → `user_id` |
| `validate(plan)` | `Ok(plan)` or `Error(PlanError)` |
| `compose(plans)` | Merge multiple plans into one, preserving operation order |
| `summary(plan)` | Human-readable string of all operations |

**`Operation` variants**

| Variant | Summary token | Description |
|---|---|---|
| `MaskField(path)` | `mask:path` | Replace field value with `"***"` |
| `DropField(path)` | `drop:path` | Remove field from output |
| `RenameField(from, to)` | `rename:from->to` | Rename a key, preserve value |
| `SetField(path, value)` | `set:path=value` | Set or overwrite a field with a literal value |
| `WhenStatus(status, op)` | `when(N):...` | Apply inner operation only when response status matches |

**`PlanError` variants**

| Error | Condition |
|---|---|
| `EmptyPlan` | No operations in the plan |
| `ConflictingOperations(path)` | Same path appears in multiple direct operations |

### `response_transform/eval`

| Function | Signature | Description |
|---|---|---|
| `apply` | `Plan, Dict(String,String) -> Dict(String,String)` | Apply all ops unconditionally |
| `apply_at_status` | `Plan, Int, Dict(String,String) -> Dict(String,String)` | Apply ops, evaluating WhenStatus against given status |

### `response_transform/body`

| Function | Description |
|---|---|
| `filter(plan, r, data, flags)` | Body filter adapter; pass-through on non-string-value JSON |
| `filter_with_status(plan, status, r, data, flags)` | Body filter with status-conditional ops |
| `parse_object(body)` | Parse flat JSON object; Error on non-string values |
| `encode_object(fields)` | Encode Dict to JSON object string |

## Typical nginx usage

```nginx
js_import main from app.js;

location /api/ {
    # Clear Content-Length before body changes size
    js_header_filter main.clear_content_length;
    # Apply transform plan to response body
    js_body_filter main.transform buffer_type=string;
    proxy_pass http://backend;
}

location /api/errors/ {
    js_header_filter main.clear_content_length;
    # Status-conditional: WhenStatus(404, DropField("stack_trace")) etc.
    js_body_filter main.transform_with_status buffer_type=string;
    proxy_pass http://backend;
}
```

**Note:** `js_header_filter main.clear_content_length` is required before `js_body_filter` when the transform changes the body size. This clears the upstream `Content-Length`, causing nginx to use `Transfer-Encoding: chunked` for the client response.

## Limitation: string-only JSON values

`body.parse_object` decodes JSON objects where all values are strings. Fields with numeric, boolean, or nested object values cause the parse to fail — the original body is forwarded unchanged. This covers the primary use case (PII masking of string fields like `email`, `name`) without full JSON tree manipulation.

## Cross-module composition boundary

- `workflow` should compose `response_transform` for shaping upstream call results before returning to the client
- `webhook` can compose it for outbound payload normalization
- `authz` may reuse it for denied-response formatting

## Phased implementation plan

### Phase 1 — stabilize the transform plan model ✓

- [x] expand `Operation` with `SetField` and `WhenStatus`
- [x] add `PlanError` and `validate` for conflicting/empty plans
- [x] add `compose` for multi-plan merging

### Phase 2 — add pure evaluation helpers ✓

- [x] `eval.gleam` with `apply` and `apply_at_status`
- [x] `WhenStatus` conditional evaluated against response status at apply time
- [x] fully unit-testable without nginx

### Phase 3 — add nginx body-filter adapter ✓

- [x] `body.gleam` with `filter` and `filter_with_status` for `js_body_filter`
- [x] `clear_content_length` header filter to enable chunked transfer after body mutation
- [x] pass-through on non-parseable bodies (graceful degradation)

### Phase 4 — richer transform policies ✓

- [x] `SetField` for hardcoded/overridden values
- [x] `WhenStatus` for status-conditional field operations
- [x] status read from nginx `$status` variable via `transform_with_status`

## TDD plan

- [x] unit-test plan summaries and operation ordering
- [x] unit-test validate (empty, conflicting, WhenStatus exception)
- [x] unit-test compose (merge, empty)
- [x] unit-test eval: mask, drop, rename, set, WhenStatus match/no-match
- [x] unit-test body: parse, encode, round-trip, invalid JSON pass-through
- [x] integration-test body filter via `tests/transform/`

## Verification checklist

- [x] `bun scripts/test.js response_transform` — 21 unit tests pass
- [x] `bun test modules/response_transform/tests/basic/do.test.js` — 2 basic tests pass
- [x] `bun test modules/response_transform/tests/transform/do.test.js` — 4 body-filter integration tests pass
