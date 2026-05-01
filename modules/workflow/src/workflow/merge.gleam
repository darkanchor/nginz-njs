//// Merge and aggregation strategies for collections of `StepResult`.
////
//// These combinators sit on top of the core pipeline algebra and handle
//// common patterns: joining bodies, concatenating headers, selecting the
//// best available result.

import gleam/list
import gleam/string
import workflow/pipeline.{type StepResult, Failed, Fetched}

/// Join all successful bodies with a delimiter.  Returns `Failed` if there
/// are no successful results.
///
pub fn merge_bodies(
  results: List(StepResult),
  delimiter: String,
) -> StepResult {
  let oks = pipeline.filter_ok(results)
  case oks {
    [] -> Failed("no successful results to merge")
    pairs -> {
      let bodies = list.map(pairs, fn(p) { p.1 })
      Fetched(200, string.join(bodies, delimiter))
    }
  }
}

/// Merge successful bodies using a custom combiner.  The combiner receives
/// the list of `(status, body)` pairs and returns the merged `StepResult`.
///
pub fn merge_with(
  results: List(StepResult),
  combiner: fn(List(#(Int, String))) -> StepResult,
) -> StepResult {
  let oks = pipeline.filter_ok(results)
  case oks {
    [] -> Failed("no successful results to merge")
    pairs -> combiner(pairs)
  }
}

/// Collect all response headers from successful results into a flat list
/// of `(name, value)` pairs.  Duplicate header names are preserved (the
/// caller decides how to de-duplicate).
///
/// Note: this extracts headers from the `StepResult` metadata — the
/// current `StepResult` does not carry headers.  This function is a
/// placeholder for when header forwarding is added to the step backend.
///
pub fn merge_headers(
  results: List(StepResult),
  extract: fn(StepResult) -> List(#(String, String)),
) -> List(#(String, String)) {
  list.fold(results, [], fn(acc, r) {
    case r {
      Fetched(_, _) -> list.append(acc, extract(r))
      Failed(_) -> acc
    }
  })
}

/// Require all results to be successful (`Fetched`).  Returns `Ok(results)`
/// if all pass, or `Error(Failed(...))` with the first failure.
///
pub fn require_all(
  results: List(StepResult),
) -> Result(List(StepResult), StepResult) {
  case results {
    [] -> Ok([])
    [r, ..rest] ->
      case r {
        Failed(_) -> Error(r)
        Fetched(_, _) ->
          case require_all(rest) {
            Ok(tail) -> Ok([r, ..tail])
            Error(e) -> Error(e)
          }
      }
  }
}

/// Select the first successful result, or return a default.
///
pub fn select_first_ok(
  results: List(StepResult),
  default: StepResult,
) -> StepResult {
  case pipeline.first_ok(results) {
    Ok(r) -> r
    Error(_) -> default
  }
}
