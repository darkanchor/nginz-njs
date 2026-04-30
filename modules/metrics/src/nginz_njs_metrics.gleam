import metrics/line
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn describe(r: HTTPRequest) -> Nil {
  line.demo_metric()
  |> line.describe
  |> http.return_text(r, 200, _)
}

fn emit_demo(r: HTTPRequest) -> Nil {
  line.demo_metric()
  |> line.render_statsd
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("emit_demo", emit_demo)
}
