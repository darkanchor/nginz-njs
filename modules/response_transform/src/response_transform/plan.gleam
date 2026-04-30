import gleam/list
import gleam/string

pub type Operation {
  MaskField(path: String)
  DropField(path: String)
  RenameField(from: String, to: String)
}

pub type Plan {
  Plan(name: String, operations: List(Operation))
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
  }
}

pub fn summary(plan: Plan) -> String {
  let parts = list.map(plan.operations, operation_text)
  plan.name <> " [" <> string.join(parts, ", ") <> "]"
}
