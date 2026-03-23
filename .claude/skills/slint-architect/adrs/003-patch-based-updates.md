# ADR-003: RFC 6902 JSON Patch for Incremental Updates

## Status

Accepted

## Context

After the initial `render` envelope sends a full view-model snapshot, subsequent
updates need a mechanism. Options:

1. **Full render every time** — Simple but wasteful, especially for large VMs
2. **Custom diff format** — Flexible but non-standard, hard to debug
3. **RFC 6902 JSON Patch** — Standard format, well-tooled, path-based addressing

## Decision

**Use RFC 6902 JSON Patch** (subset: `add`, `replace`, `remove`) for
incremental view-model updates after the initial render.

## How It Works

1. Elixir's `State` container tracks changed fields via `MapSet`
2. Session computes a diff between previous and current render output
3. Diff is encoded as JSON Patch operations with RFC 6901 JSON Pointer paths
4. Patch envelope includes `rev` (monotonic) and optional `ack` (intent delivery)

Example patch:
```json
{
  "t": "patch",
  "sid": "S1",
  "rev": 5,
  "ack": 3,
  "ops": [
    {"op": "replace", "path": "/temperature", "value": "24.1"},
    {"op": "replace", "path": "/status", "value": "online"}
  ]
}
```

## Rationale

- **Bandwidth efficient** — Only changed fields are sent over the wire
- **Standard format** — RFC 6902 is widely understood and debuggable
- **Row-level updates** — `:id_table` fields enable paths like `/devices/by_id/d1/status`
- **Change tracking is automatic** — `assign/3` only marks fields whose values actually differ
- **Resync safety** — Revision mismatch triggers a full re-render, recovering from any state

## Consequences

- Patch computation adds CPU work per state change — negligible for typical UIs
- The Rust host must maintain a shadow copy of the VM to apply patches correctly
- Patch ordering matters — out-of-order delivery triggers resync
- `:list` type sends full list replacement (not individual element patches) — use `:id_table` for large mutable collections
