import gleam/int
import gleam/list
import gleam/string

pub type Operation {
  MaskField(path: String)
  DropField(path: String)
  RenameField(from: String, to: String)
  SetField(path: String, value: String)
  WhenStatus(status: Int, op: Operation)
}

pub type Plan {
  Plan(name: String, operations: List(Operation))
}

pub type PlanError {
  EmptyPlan
  ConflictingOperations(String)
}

pub fn demo_plan() -> Plan {
  Plan(name: "default_response_transform", operations: [
    MaskField("user.email"),
    DropField("internal.trace"),
    RenameField("user.id", "user_id"),
  ])
}

fn operation_text(operation: Operation) -> String {
  case operation {
    MaskField(path) -> "mask:" <> path
    DropField(path) -> "drop:" <> path
    RenameField(from, to) -> "rename:" <> from <> "->" <> to
    SetField(path, value) -> "set:" <> path <> "=" <> value
    WhenStatus(status, op) ->
      "when(" <> int.to_string(status) <> "):" <> operation_text(op)
  }
}

pub fn summary(plan: Plan) -> String {
  let parts = list.map(plan.operations, operation_text)
  plan.name <> " [" <> string.join(parts, ", ") <> "]"
}

fn primary_path(op: Operation) -> String {
  case op {
    MaskField(p) -> p
    DropField(p) -> p
    RenameField(from, _) -> from
    SetField(p, _) -> p
    WhenStatus(_, inner) -> primary_path(inner)
  }
}

fn find_duplicate(paths: List(String)) -> Result(String, Nil) {
  case paths {
    [] -> Error(Nil)
    [head, ..rest] ->
      case list.contains(rest, head) {
        True -> Ok(head)
        False -> find_duplicate(rest)
      }
  }
}

pub fn validate(plan: Plan) -> Result(Plan, PlanError) {
  case plan.operations {
    [] -> Error(EmptyPlan)
    ops -> {
      let direct_paths =
        ops
        |> list.filter(fn(op) {
          case op {
            WhenStatus(_, _) -> False
            _ -> True
          }
        })
        |> list.map(primary_path)
      case find_duplicate(direct_paths) {
        Ok(path) -> Error(ConflictingOperations(path))
        Error(_) -> Ok(plan)
      }
    }
  }
}

pub fn compose(plans: List(Plan)) -> Plan {
  case plans {
    [] -> Plan(name: "empty", operations: [])
    [first, ..rest] ->
      Plan(
        name: first.name,
        operations: list.fold(rest, first.operations, fn(acc, p) {
          list.append(acc, p.operations)
        }),
      )
  }
}
