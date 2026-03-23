# ADR-005: Automatic Resync Error Recovery

## Status

Accepted

## Context

Communication between Elixir and the Rust host can fail due to:
- Payload corruption or truncation
- Process crashes and restarts
- Revision sequence breaks
- JSON decode errors

The system needs a recovery mechanism that does not require manual intervention,
especially on unattended embedded devices.

## Decision

**Implement automatic resync** triggered by sending a fresh `ready` envelope
from the Rust host. The Elixir Session responds with a full `render` envelope,
effectively resetting the UI to current state.

## Resync Triggers

The Rust host requests resync when:
- `decode_error` — Malformed JSON received
- `frame_too_large` — Payload exceeds capacity limit
- `invalid_envelope` — Missing required fields
- `resync_required` — Explicit server request
- `rev_mismatch` — Revision number out of sequence
- `patch_apply_error` — JSON Patch operation failed

The Rust host does NOT resync for:
- `validation_warning` — Non-fatal advisory messages

## Recovery Flow

```
1. Error detected (e.g., rev mismatch)
2. Rust host resets local UI model state to default
3. Rust host sends {t: "ready", sid: "S1"} (same as initial handshake)
4. Elixir Session receives ready -> treats as reconnection
5. Session remounts current screen -> full render envelope sent
6. Rust host applies full render -> UI restored to current state
```

## Rationale

- **Self-healing** — No human intervention needed on embedded devices
- **Simple** — Reuses the existing `ready` -> `render` handshake
- **Bounded** — Resync is deduplicated (one pending at a time via AtomicBool)
- **Observable** — All resync events are logged with reason strings
- **Graceful** — HostBridge reconnection uses bounded exponential backoff

## Consequences

- Resync causes a brief visual "flash" as the full VM is reapplied
- During resync, in-flight intents may be lost (acceptable for UI interactions)
- Frequent resyncs indicate a systematic issue — monitor and alert on resync rate
- The Session's revision counter resets, which is fine since both sides reset together
