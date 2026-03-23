# ADR-004: LiveView-Inspired Screen Lifecycle

## Status

Accepted

## Context

Developers building Projection UIs need a familiar, productive programming
model for defining screens. The Elixir ecosystem has a well-understood pattern
in Phoenix LiveView.

## Decision

**Model the screen lifecycle after Phoenix LiveView** with adaptations for
native/embedded rendering:

| LiveView Callback | Projection Equivalent | Notes |
|-------------------|----------------------|-------|
| `mount/3` | `mount/3` | Identical — params, session, state |
| `handle_event/3` | `handle_event/3` | Intent name instead of form event |
| `handle_params/2` | `handle_params/2` | Route patch without remount |
| `handle_info/2` | `handle_info/2` | Identical — PubSub, timers, etc. |
| `render/1` | `render/1` | Returns map (not HEEx template) |
| N/A | `subscriptions/2` | Explicit PubSub topic declaration |
| `use Phoenix.LiveView` | `use ProjectionUI, :screen` | Macro setup |
| `assign/2,3` | `assign/3` | State helpers |
| `update/3` | `update/3` | Function-based assign |

## Rationale

- **Familiar to Elixir developers** — Drastically reduces learning curve
- **Proven patterns** — LiveView's lifecycle is battle-tested at scale
- **Testable** — Screens are plain Elixir modules with predictable callbacks
- **Composable** — Components (`use ProjectionUI, :component`) mirror LiveComponent schemas
- **Explicit subscriptions** — Unlike LiveView's socket-level handling, Projection
  declares subscriptions per-screen for clear data flow

## Differences from LiveView

- `render/1` returns a `map()`, not a HEEx template — Slint is the template engine
- No `assign_new` — use pattern matching in `mount/3` instead
- No `push_event` — Slint has no JS hooks; use schema fields for all data
- No `push_navigate`/`push_patch` from server — navigation is intent-driven from UI
- Components use flattened field prefixing instead of nested assigns

## Consequences

- Elixir developers with LiveView experience can be productive immediately
- The screen behaviour is enforced at compile time via `@behaviour ProjectionUI.Screen`
- Schema validation ensures `render/1` output matches declared fields
- Screens are easily unit-testable without the Slint runtime
