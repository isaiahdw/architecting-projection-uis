# ADR-002: Length-Prefixed JSON over Stdio

## Status

Accepted

## Context

The Elixir BEAM and Rust Slint host are separate OS processes. We need a
reliable, low-overhead IPC mechanism for bidirectional communication.

Options considered:

1. **TCP socket** — Flexible but adds networking complexity on embedded
2. **Unix domain socket** — Platform-specific, harder on some embedded targets
3. **NIF** — Shares BEAM scheduler, risky for UI rendering (can block schedulers)
4. **Port with line protocol** — Simple but fragile for binary/JSON data
5. **Port with `{:packet, 4}` framing** — Length-prefixed frames, built into OTP

## Decision

**Use OTP ports with `{:packet, 4}` framing** for stdio-based communication
between Elixir and the Rust host. Payloads are JSON-encoded envelopes.

## Protocol

- **Framing:** 4-byte big-endian length prefix followed by JSON payload
- **Direction:** Bidirectional over stdin/stdout of the Rust child process
- **Envelope types:**
  - UI -> Elixir: `ready`, `intent`
  - Elixir -> UI: `render`, `patch`, `error`
- **Capacity limits:**
  - UI -> Elixir: 64 KB
  - Elixir -> UI: 1 MB

## Rationale

- **OTP-native** — `{:packet, 4}` is handled by the BEAM VM, zero-copy framing
- **No external dependencies** — No gRPC, protobuf, or networking libraries needed
- **Embedded friendly** — Stdio works everywhere, no port allocation needed
- **JSON** — Human-readable, debuggable, sufficient performance for UI updates
- **Revision tracking** — Monotonic `rev` field enables ordering and resync

## Consequences

- JSON parsing adds CPU overhead vs binary protocols — acceptable for UI update rates
- Payload size limits constrain view-model size — mitigated by patch-based updates
- Rust host must manage its own event loop threading (reader, writer, Slint UI loop)
- Port crashes are detectable and recoverable via HostBridge supervision
