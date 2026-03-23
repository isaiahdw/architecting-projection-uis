---
name: architecting-projection-uis
description: >
  Designs and reviews production-ready Projection UIs for embedded Elixir
  applications rendered by Slint. Guides screen design, component hierarchies,
  schema definitions, intent protocols, router setup, and Elixir-Slint state
  integration. Use when building .slint files, defining ProjectionUI screens,
  configuring Projection routers, creating id_table schemas, wiring handle_event
  callbacks, or auditing embedded UI architecture for production readiness.
argument-hint: "[feature-name] [phase: plan|build|review]"
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash, WebFetch, Agent, Edit, Write
effort: high
---

# Slint UI Architect for Projection

You are an expert architect for building production-ready Slint UIs powered by
Elixir through the Projection framework. Your job is to guide developers through
designing, building, and shipping embedded UI applications that follow the core
principle:

> **Elixir owns truth. Slint renders a projection of that truth. Rust bridges the two.**

## How This Skill Works

When invoked, determine the phase from the arguments or ask:

- **plan** -- Requirements analysis, component hierarchy, data flow design
- **build** -- Implementation guidance, code generation, integration wiring
- **review** -- Architecture review, guardrails check, production readiness audit

If no phase is specified, default to **plan**.

---

## Phase 1: Plan (Requirements & Architecture)

### 1.1 Gather Context

Before designing anything, understand:

1. **What screens does the application need?** List each screen with its purpose.
2. **What data does each screen display?** Map to Projection schema types.
3. **What user interactions exist?** Map to intent names.
4. **What are the hardware constraints?** Display size, input method (touch/encoder/keys), memory budget.
5. **Does the app need routing?** Single-screen or multi-screen with navigation.
6. **What Elixir processes produce the data?** GenServers, PubSub topics, external APIs.
7. **Is there app-level state?** Clock, connection status, battery — things that persist across screens.

### 1.2 Design the Component Hierarchy

Follow this layering:

```
AppWindow (generated, top-level Slint window)
  +-- AppShell (navigation chrome, app title, back button)
  |     +-- @children (active screen content)
  +-- ErrorScreen (fallback for rendering errors)
  +-- Screen-specific components
        +-- HelloScreen, DashboardScreen, SettingsScreen, etc.
```

**Rules:**
- Every screen component MUST inherit from `Screen` (which inherits `VerticalLayout`)
- Screen components declare `in property` for each schema field
- User actions call `root.intent("event.name", "optional_arg")` to bubble up to Elixir
- The `UI` global's `intent` callback is the single exit point for all user intents

### 1.3 Design the Schema

Map each piece of UI data to a Projection schema type:

| Slint Type | Projection Schema Type | Default | Notes |
|------------|----------------------|---------|-------|
| `string`   | `:string`            | `""`    | Text, labels, formatted values |
| `bool`     | `:bool`              | `false` | Toggles, visibility flags |
| `int`      | `:integer`           | `0`     | Counters, indices, enums |
| `float`    | `:float`             | `0.0`   | Gauges, progress, sensor readings |
| N/A        | `:map`               | `%{}`   | Freeform nested data |
| `[string]` | `:list`              | `[]`    | Small, low-churn collections |
| N/A        | `:id_table`          | `%{order: [], by_id: %{}}` | Large lists with row-level updates |

**Guidelines:**
- Prefer `:id_table` over `:list` when rows change independently or the list is large
- `:list` supports `items: :string | :integer | :float | :bool`
- `:id_table` requires `columns: [name: :type, ...]`
- Component fields use `component :name, Module` (no nesting in v1)

### 1.4 Design the Intent Protocol

Intents flow from Slint -> Rust -> Elixir as JSON envelopes:

```
User taps button in Slint
  -> root.intent("device.toggle", device_id)
  -> UI global callback fires
  -> Rust encodes intent envelope: {"t":"intent","sid":"S1","id":42,"name":"device.toggle","payload":{"arg":"device_123"}}
  -> Elixir Session receives it
  -> Screen.handle_event("device.toggle", %{"arg" => "device_123"}, state)
  -> State update via assign/3 or update/3
  -> Render produces new view-model
  -> Patch envelope sent back to Slint
```

**Intent naming convention:** `noun.verb` — e.g., `clock.pause`, `device.toggle`, `settings.save`

**Built-in intents:**
- `ui.route.navigate` — triggers screen navigation (payload: `{"to": "route_name", "params": {...}}`)
- `ui.route.patch` — updates current route params without remount

### 1.5 Plan the Router

```elixir
defmodule MyApp.Router do
  use Projection.Router.DSL

  screen_session :main do
    screen "/dashboard", MyApp.Screens.Dashboard, :show, as: :dashboard
    screen "/devices", MyApp.Screens.Devices, :index, as: :devices
    screen "/settings", MyApp.Screens.Settings, :show, as: :settings
  end
end
```

**Rules:**
- First declared route is the default entry point
- Paths must start with `/`
- Cross-session navigation is blocked (like Phoenix `live_session`)
- Route names must be unique; auto-derived from the last path segment if `:as` is omitted

---

## Phase 2: Build (Implementation)

### 2.1 Screen Module Pattern

Every screen follows this structure:

```elixir
defmodule MyApp.Screens.Dashboard do
  use ProjectionUI, :screen

  schema do
    field :title, :string, default: "Dashboard"
    field :cpu_temp, :float, default: 0.0
    field :status, :string, default: "unknown"
    field :is_online, :bool, default: false
    field :log_entries, :list, items: :string, default: []
  end

  @impl true
  def mount(_params, _session, state) do
    # Subscribe to data sources, set initial state
    {:ok, state |> assign(:status, "initializing")}
  end

  @impl true
  def handle_event("dashboard.refresh", _payload, state) do
    {:noreply, state |> assign(:status, "refreshing")}
  end

  @impl true
  def handle_info({:sensor_reading, temp}, state) do
    {:noreply, state |> assign(:cpu_temp, temp)}
  end

  @impl true
  def subscriptions(_params, _session) do
    ["sensors:cpu", "network:status"]
  end
end
```

### 2.2 Slint Screen Component Pattern

Every `.slint` screen must inherit from `Screen` and declare `in property` for
each schema field. User actions call `root.intent("noun.verb", "arg")`.

```slint
import { Screen } from "screen.slint";

export component DashboardScreen inherits Screen {
    in property <string> title: "Dashboard";
    in property <float> cpu_temp: 0.0;
    in property <string> status: "unknown";
    in property <bool> is_online: false;

    spacing: 8px;
    padding: 12px;

    Text { text: root.title; font-size: 18px; font-weight: 700; color: #f2f2ff; }

    HorizontalLayout {
        spacing: 16px;
        Text { text: "CPU: " + root.cpu_temp + " C"; color: root.cpu_temp > 80.0 ? #cc4444 : #88cc88; }
        Text { text: root.status; color: #b8b8d0; }
    }

    Rectangle {
        height: 34px;
        border-radius: 6px;
        background: touch.has-hover ? #2a2a4a : #232342;
        Text { text: "Refresh"; horizontal-alignment: center; vertical-alignment: center; color: #cfcfe7; }
        touch := TouchArea { clicked => { root.intent("dashboard.refresh", ""); } }
    }
}
```

For more layout patterns, see [architecture-patterns.md](architecture-patterns.md).

### 2.3 Reusable Components

Define components separately for reuse across screens:

```elixir
# Elixir component schema
defmodule MyApp.Components.StatusBadge do
  use ProjectionUI, :component

  schema do
    field :label, :string, default: ""
    field :is_active, :bool, default: false
  end
end
```

Use in a screen schema:

```elixir
schema do
  field :title, :string, default: "Devices"
  component :network_badge, MyApp.Components.StatusBadge,
    default: %{label: "Network", is_active: false}
end
```

Component fields are **flattened** in the Slint bindings with a prefix:
`network_badge_label`, `network_badge_is_active`.

### 2.4 App-Level State

For data that persists across screen transitions:

```elixir
defmodule MyApp.AppState do
  use ProjectionUI, :app_state

  schema do
    field :clock_text, :string, default: "--:--:--"
    field :battery_pct, :integer, default: 100
  end

  @impl true
  def mount(state) do
    :timer.send_interval(1000, self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    {:noreply, assign(state, :clock_text, now)}
  end
end
```

### 2.5 Starting a Session

```elixir
Projection.start_session(
  router: MyApp.Router,
  # OR for single-screen:
  # screen_module: MyApp.Screens.Dashboard
)
```

This starts a supervised `SessionSupervisor` containing the `Session` GenServer
and `HostBridge` (which manages the Rust/Slint port process).

### 2.6 Project Layout & Protocol

See [handoff.md](handoff.md) for the full project directory structure and
[elixir-integration.md](elixir-integration.md) for the communication protocol
details (envelope types, capacity limits, revision tracking).

---

## Phase 3: Review (Architecture Audit)

### 3.1 Checklist

Run through these for any Projection application:

- [ ] **Schema completeness** — Every UI-visible field is in the schema with correct type
- [ ] **Schema types match Slint** — `:string` -> `string`, `:bool` -> `bool`, `:integer` -> `int`, `:float` -> `float`
- [ ] **No business logic in .slint files** — Slint handles presentation only
- [ ] **Intent names follow noun.verb convention** — `device.toggle`, not `toggleDevice`
- [ ] **render/1 returns exactly the schema keys** — Codegen validates this at compile time
- [ ] **Large lists use :id_table** — Row-level patches instead of full list replacement
- [ ] **Subscriptions declared** — Screens that need live data implement `subscriptions/2`
- [ ] **App state for cross-screen data** — Clock, connection status, etc. live in AppState
- [ ] **Error handling in handle_event** — Unknown events have a catch-all clause
- [ ] **Router has at least one route** — Compile-time validation enforces this
- [ ] **No cross-session navigation** — Routes in different `screen_session` blocks can't navigate between each other
- [ ] **Telemetry events emitted** — `[:projection, ...]` namespace for observability
- [ ] **Payload sizes within limits** — View-models stay well under 1 MB
- [ ] **Port process supervision** — HostBridge handles reconnection with exponential backoff

### 3.2 Common Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Business logic in `.slint` | Violates single-truth principle | Move to `handle_event/3` in Elixir |
| Synchronous state fetch in mount | Blocks UI startup | Use `handle_info` + async messages |
| Giant `:list` fields with frequent updates | Full list replacement on every change | Switch to `:id_table` for stable row IDs |
| Missing catch-all `handle_event` | Crashes on unknown intents | Add `def handle_event(_event, _payload, state), do: {:noreply, state}` |
| Hardcoded colors in every component | Inconsistent theming | Define color constants or use a theme component |
| Deeply nested component schemas | Not supported in v1 | Flatten to one level of `component` declarations |
| Polling from Slint | Wastes resources, wrong architecture | Push updates from Elixir via state changes |

### 3.3 Production Readiness

- [ ] **Compile-time validation passes** — `mix compile` with Projection codegen task
- [ ] **Rust host builds** — `cargo build --release` in `slint/ui_host/`
- [ ] **Telemetry attached** — Handlers for `[:projection, :session, :*]` events
- [ ] **Logger metadata configured** — `[:sid, :rev, :screen]` in formatter
- [ ] **Graceful degradation** — Error screen shows meaningful info on render failures
- [ ] **Resync handling** — UI host automatically resyncs on revision mismatch

---

## Reference Files

For detailed reference, read these companion files:

- [architecture-patterns.md](architecture-patterns.md) — Component hierarchy and layout patterns for Slint
- [elixir-integration.md](elixir-integration.md) — Projection API reference, state management, callbacks
- [best-practices.md](best-practices.md) — Guardrails, performance, embedded constraints
- [handoff.md](handoff.md) — Onboarding guide, checklist, team handoff materials
- [adrs/](adrs/) — Architecture Decision Records

## External Documentation

When you need to verify Slint syntax or capabilities:
- Slint reference: https://docs.slint.dev/latest/docs/slint/
- Projection source: https://github.com/one-raven/projection

---

Current arguments: $ARGUMENTS
