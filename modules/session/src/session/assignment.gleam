import session/store

/// Sticky rollout assignment for a session.
/// Stored as a separate key "{session_id}:canary" in the same shared dict.
pub type CanaryAssignment {
  Assigned(Bool)
  Unassigned
}

/// Serialize a canary bool to its storage string.
pub fn canary_to_string(assigned: Bool) -> String {
  case assigned {
    True -> "1"
    False -> "0"
  }
}

/// Deserialize a stored canary string back to a CanaryAssignment.
pub fn canary_from_string(raw: String) -> CanaryAssignment {
  case raw {
    "1" -> Assigned(True)
    "0" -> Assigned(False)
    _ -> Unassigned
  }
}

/// Parse a write-time canary input value.
/// Only explicit "1" and "0" are accepted; anything else is invalid.
pub fn parse_canary_input(raw: String) -> Result(Bool, Nil) {
  case raw {
    "1" -> Ok(True)
    "0" -> Ok(False)
    _ -> Error(Nil)
  }
}

/// Load the sticky canary assignment for this session.
/// Returns Unassigned when no assignment has been persisted.
pub fn load_canary(dict_name: String, session_id: String) -> CanaryAssignment {
  case store.load(dict_name, session_id <> ":canary") {
    Ok(raw) -> canary_from_string(raw)
    Error(_) -> Unassigned
  }
}

/// Persist a sticky canary assignment for this session with the same TTL as the session.
pub fn save_canary(
  dict_name: String,
  session_id: String,
  assigned: Bool,
  ttl_s: Int,
) -> Nil {
  store.save(
    dict_name,
    session_id <> ":canary",
    canary_to_string(assigned),
    ttl_s,
  )
}

/// Remove the canary assignment for this session.
pub fn delete_canary(dict_name: String, session_id: String) -> Nil {
  store.delete(dict_name, session_id <> ":canary")
}
