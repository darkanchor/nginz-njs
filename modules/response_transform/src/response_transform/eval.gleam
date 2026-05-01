import gleam/dict.{type Dict}
import gleam/list
import response_transform/plan.{
  type Operation, type Plan, DropField, MaskField, RenameField, SetField,
  WhenStatus,
}

pub fn apply(plan: Plan, fields: Dict(String, String)) -> Dict(String, String) {
  apply_at_status(plan, -1, fields)
}

pub fn apply_at_status(
  plan: Plan,
  status: Int,
  fields: Dict(String, String),
) -> Dict(String, String) {
  list.fold(plan.operations, fields, fn(acc, op) { apply_op(acc, op, status) })
}

fn apply_op(
  fields: Dict(String, String),
  op: Operation,
  status: Int,
) -> Dict(String, String) {
  case op {
    MaskField(path) ->
      case dict.has_key(fields, path) {
        True -> dict.insert(fields, path, "***")
        False -> fields
      }
    DropField(path) -> dict.delete(fields, path)
    RenameField(from, to) ->
      case dict.get(fields, from) {
        Ok(v) -> fields |> dict.delete(from) |> dict.insert(to, v)
        Error(_) -> fields
      }
    SetField(path, value) -> dict.insert(fields, path, value)
    WhenStatus(s, inner_op) ->
      case s == status {
        True -> apply_op(fields, inner_op, status)
        False -> fields
      }
  }
}
