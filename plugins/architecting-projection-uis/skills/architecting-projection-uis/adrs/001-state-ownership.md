# ADR-001: Elixir-Authoritative State Ownership

## Status

Accepted

## Context

Building UI for embedded/native applications requires a clear decision about
where application state lives. Options include:

1. **UI-owned state** — Slint holds the truth, Elixir reacts to changes
2. **Shared state** — Both sides maintain state with synchronization
3. **Backend-owned state** — Elixir holds the truth, UI is a pure projection

## Decision

**Elixir owns all application state.** Slint is a stateless renderer that
receives view-model snapshots and emits user intents. The Rust host is a
dumb bridge with no policy decisions.

## Rationale

- **Single source of truth** eliminates sync bugs between UI and backend
- **BEAM reliability** — OTP supervision, process isolation, fault tolerance
- **Testability** — Screen logic is pure Elixir, testable without a UI runtime
- **Embedded fit** — Elixir processes can be tuned for memory/CPU constraints
- **Hot code reload** — Elixir state survives code upgrades; UI state does not need to

## Consequences

- Slint cannot independently decide what to display — every visible change
  must originate from an Elixir state update
- User interactions have inherent round-trip latency (UI -> Rust -> Elixir -> Rust -> UI)
- Optimistic UI updates are not natively supported (would require Slint-side state)
- The view-model must be serializable as JSON
