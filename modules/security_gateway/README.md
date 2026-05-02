# nginz_njs_security_gateway

## Status

**No longer a standalone Milestone 2 package. Merge target: `authz`.**

The review conclusion is that `security_gateway` should not exist as a second policy engine beside `authz`. Its strongest ideas — typed security signals, policy combinators, and custom security responses — belong inside the existing authorization/policy module rather than behind a parallel package boundary.

## Why the standalone package was demoted

`security_gateway` duplicates the most important part of `authz`:

- the same `all_of` / `any_of` / `not_` policy-combinator model
- the same “native facts → typed context → decision” shape
- overlapping response-shaping concerns

At the same time, it inherits the same phase-risk warning surfaced by `ratelimit_policy`: not every native signal is safely composable in a CONTENT-phase handler, especially when the signal comes from native deny-path behavior.

That makes a second standalone policy engine the wrong move.

## What should move into `authz`

- typed signal modeling for broader security facts
- OIDC identity adapters that feed the same policy context
- WAF and nftset facts where phase-safe allow-path composition is actually valid
- challenge/deny helpers that fit the existing `Decision` model

The goal is one policy engine, not two.

## Important constraint

This merge is not permission to overclaim native-signal composition. The phase lesson from `ratelimit_policy` still applies:

- do not assume native deny-path variables are available after `error_page`
- treat WAF / ratelimit composition carefully and only document what is phase-safe
- prefer explicit proof via native integration tests before claiming a new security signal is part of the reusable policy story

## Outcome for the roadmap

`security_gateway` is removed as an independent package. Its useful work is now tracked as part of Milestone 2’s `authz` extension track.
