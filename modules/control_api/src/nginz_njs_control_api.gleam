import control_api/response
import control_api/router
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn describe(r: HTTPRequest) -> Nil {
  router.describe_routes()
  |> http.return_text(r, 200, _)
}

fn health(r: HTTPRequest) -> Nil {
  response.ok("control_api=ready")
  |> http.return_text(r, 200, _)
}

fn inspect_flag(r: HTTPRequest) -> Nil {
  let name = case http.get_variable(r, "arg_name") {
    Ok(value) -> value
    Error(_) -> "unknown"
  }

  response.ok(
    response.kv("flag", name) <> " " <> response.kv("mode", "inspect"),
  )
  |> http.return_text(r, 200, _)
}

fn toggle_flag_preview(r: HTTPRequest) -> Nil {
  let name = case http.get_variable(r, "arg_name") {
    Ok(value) -> value
    Error(_) -> "unknown"
  }
  let enabled = case http.get_variable(r, "arg_enabled") {
    Ok(value) -> value
    Error(_) -> "unset"
  }

  response.ok(
    response.kv("preview", "set_flag")
    <> " "
    <> response.kv("name", name)
    <> " "
    <> response.kv("enabled", enabled),
  )
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("health", health)
  |> ngx.merge("inspect_flag", inspect_flag)
  |> ngx.merge("toggle_flag_preview", toggle_flag_preview)
}
