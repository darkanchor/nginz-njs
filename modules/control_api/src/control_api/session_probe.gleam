import control_api/response
import gleam/int
import njs/ngx
import session/store

/// Probe a session shared dict by writing and reading a sentinel entry.
/// Returns JSON status indicating whether the dict is reachable.
pub fn session_probe(dict_name: String) -> String {
  let sentinel_id = "__control_api_session_probe__"
  let sentinel_subject = "probe-subject"
  store.save(dict_name, sentinel_id, sentinel_subject, 60)
  case store.load(dict_name, sentinel_id) {
    Ok(_) ->
      response.json_ok([#("session_dict", dict_name), #("reachable", "true")])
    Error(_) -> response.json_error("session dict not reachable: " <> dict_name)
  }
}

/// Return session layer info: which dict is configured and current timestamp.
pub fn session_info(dict_name: String) -> String {
  response.json_ok([
    #("module", "control_api"),
    #("session_dict", dict_name),
    #("now_ms", int.to_string(ngx.now())),
  ])
}
