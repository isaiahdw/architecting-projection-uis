# Architecting Projection UIs

A Claude Code skill for designing production-ready [Projection](https://github.com/one-raven/projection) UIs — embedded Elixir applications rendered natively by [Slint](https://slint.dev).

> **Elixir owns truth. Slint renders a projection of that truth. Rust bridges the two.**

## What This Is

A comprehensive Claude Code skill that guides you through architecting, building, and reviewing embedded UIs where:

- **Elixir** manages all application state and business logic
- **Slint** handles native rendering on embedded Linux displays
- **Rust** bridges the two via length-prefixed JSON over stdio

The skill encodes the Projection framework's patterns, the Slint language reference (focused on embedded), and production guardrails into a reusable `/architecting-projection-uis` command.

## Installation

Clone into a project that uses Projection, or into its own directory:

```bash
git clone git@github.com:isaiahdw/architecting-projection-uis.git
```

The skill lives in `.claude/skills/slint-architect/` and is automatically discovered by Claude Code when working in this directory.

To use the skill in another project, copy the `.claude/skills/slint-architect/` directory into that project's `.claude/skills/` folder.

## Usage

```
/architecting-projection-uis                          # Plan phase (default)
/architecting-projection-uis thermostat plan          # Design a specific feature
/architecting-projection-uis device-list build        # Implementation guidance
/architecting-projection-uis review                   # Architecture audit
```

### Phases

| Phase | What It Does |
|-------|-------------|
| **plan** | Requirements analysis, component hierarchy, schema design, intent protocol, router planning |
| **build** | Screen module scaffolding, `.slint` component patterns, state wiring, codegen workflow |
| **review** | Architecture audit checklist, anti-pattern detection, production readiness verification |

The skill also auto-triggers when conversations involve Slint UI design, Projection screens, schema definitions, or embedded UI architecture.

## What's Included

```
.claude/skills/slint-architect/
  SKILL.md                      Main skill — 3-phase workflow, schema mapping, intent protocol
  architecture-patterns.md      Slint component hierarchy, layouts, colors, focus, fonts, debugging
  elixir-integration.md         Projection API reference — all modules, callbacks, session lifecycle
  best-practices.md             Guardrails, performance, accessibility, i18n, security, testing
  handoff.md                    Onboarding guide, production checklist, troubleshooting
  adrs/
    001-state-ownership.md      Elixir-authoritative state
    002-communication-protocol.md   stdio + JSON framing
    003-patch-based-updates.md      RFC 6902 incremental updates
    004-screen-lifecycle.md         LiveView-inspired callbacks
    005-error-recovery.md           Automatic resync
  examples/
    thermostat-screen.ex        Full Elixir screen with PubSub, async loading, intents
    thermostat.slint            Corresponding Slint component for 480x320 embedded display
    device-list-screen.ex       id_table example with row-level updates
```

## Key Concepts

### Schema Type Mapping

| Elixir Schema | Slint Property | Default |
|--------------|---------------|---------|
| `:string` | `string` | `""` |
| `:bool` | `bool` | `false` |
| `:integer` | `int` | `0` |
| `:float` | `float` | `0.0` |
| `:list` | `[string]`, `[int]`, etc. | `[]` |
| `:id_table` | codegen setters | `%{order: [], by_id: %{}}` |

### Intent Flow

```
User taps button in Slint
  → root.intent("device.toggle", device_id)
  → Rust encodes intent envelope
  → Elixir Screen.handle_event("device.toggle", payload, state)
  → State update via assign/3
  → Patch envelope sent back to Slint
```

### Screen Lifecycle (LiveView-inspired)

```elixir
defmodule MyApp.Screens.Dashboard do
  use ProjectionUI, :screen

  schema do
    field :title, :string, default: "Dashboard"
    field :temperature, :float, default: 0.0
  end

  def mount(_params, _session, state), do: {:ok, state}
  def handle_event("refresh", _payload, state), do: {:noreply, state}
  def handle_info({:sensor, temp}, state), do: {:noreply, assign(state, :temperature, temp)}
end
```

## References

- [Slint Documentation](https://docs.slint.dev/latest/docs/slint/)
- [Projection Framework](https://github.com/one-raven/projection)

## License

MIT
