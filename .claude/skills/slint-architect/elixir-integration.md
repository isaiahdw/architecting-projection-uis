# Projection Elixir Integration Reference

## Overview

Projection provides a LiveView-inspired API for building native/embedded UIs.
Elixir processes own all state; Slint receives a "projection" of that state as
a view-model, rendered via a Rust bridge process communicating over stdio.

## Core Modules

### `Projection` — Entry Point

```elixir
Projection.start_session(opts \\ [])
```

Starts a supervised session. Options must include either:
- `:router` — a module using `Projection.Router.DSL` (multi-screen)
- `:screen_module` — a single screen module (single-screen mode)

Delegates to `ProjectionUI.SessionSupervisor.start_link/1`.

### `ProjectionUI` — Behaviour Macros

Three usage modes:

```elixir
use ProjectionUI, :screen      # Full screen with lifecycle callbacks
use ProjectionUI, :component   # Reusable schema-only component
use ProjectionUI, :app_state   # Session-level persistent state
```

### `ProjectionUI.Screen` — Screen Behaviour

Callbacks (all optional except schema):

| Callback | Signature | Called When |
|----------|-----------|------------|
| `schema/0` | `-> map()` | Compile-time, returns `%{field => default}` |
| `mount/3` | `(params, session, state) -> {:ok, state}` | Screen first loaded or navigated to |
| `handle_event/3` | `(event, params, state) -> {:noreply, state}` | User intent from UI host |
| `handle_params/2` | `(params, state) -> {:noreply, state}` | Route patch (param change, no remount) |
| `handle_info/2` | `(message, state) -> {:noreply, state}` | Internal messages (timer, PubSub, etc.) |
| `render/1` | `(assigns) -> map()` | Produces view-model from current assigns |
| `subscriptions/2` | `(params, session) -> [term()]` | Declares PubSub topics on mount/navigation |

**Default implementations** are provided for all optional callbacks via the
`use ProjectionUI, :screen` macro. Override only what you need.

### `ProjectionUI.State` — State Container

The state struct holds `assigns` (a map) and `changed` (a MapSet for tracking).

```elixir
# Set a value (only marks changed if value actually differs)
state = assign(state, :title, "Hello")

# Update via function
state = update(state, :count, &(&1 + 1))

# Introspection (used internally by Session for patch generation)
ProjectionUI.State.changed_fields(state)  # [:title, :count]
ProjectionUI.State.clear_changed(state)   # resets change tracking
```

**Key detail:** `assign/3` uses strict equality (`===`) — assigning the same
value is a no-op. This is critical for efficient patch generation.

### `ProjectionUI.Schema` — Schema DSL

Declare typed fields inside a `schema` block:

```elixir
schema do
  field :name, :string, default: "untitled"
  field :active, :bool
  field :count, :integer, default: 42
  field :ratio, :float, default: 0.5
  field :meta, :map
  field :tags, :list, items: :string, default: ["default"]
  field :rows, :id_table, columns: [name: :string, status: :string]
  component :badge, MyApp.Components.StatusBadge
end
```

**Supported types:**

| Type | Default | Options |
|------|---------|---------|
| `:string` | `""` | — |
| `:bool` | `false` | — |
| `:integer` | `0` | — |
| `:float` | `0.0` | — |
| `:map` | `%{}` | — |
| `:list` | `[]` | `items: :string \| :integer \| :float \| :bool` |
| `:id_table` | `%{order: [], by_id: %{}}` | `columns: [name: :type, ...]` (required) |

**Component fields:**

```elixir
component :status, MyApp.Components.StatusBadge
component :status, MyApp.Components.StatusBadge, default: %{label: "Custom"}
```

- Component module must `use ProjectionUI, :component`
- Component fields are flattened with prefix: `status_label`, `status_active`
- Nested components are NOT supported in v1
- Component types limited to: `:string`, `:bool`, `:integer`, `:float`, `:list`, `:id_table`

**Compile-time validation:**
- Duplicate field names raise `CompileError`
- Missing `schema do ... end` block raises `CompileError`
- `validate_render!/1` checks that `render/1` output matches schema keys and types

### `ProjectionUI.AppState` — Cross-Screen State

For data that persists across screen transitions:

```elixir
defmodule MyApp.AppState do
  use ProjectionUI, :app_state

  schema do
    field :clock, :string, default: "--:--"
    field :wifi_strength, :integer, default: 0
  end

  @impl true
  def mount(state) do
    :timer.send_interval(1000, self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    {:noreply, assign(state, :clock, now)}
  end
end
```

AppState has only `mount/1` and `handle_info/2` — no event handling, no
params, no subscriptions, no render override.

### `Projection.Router.DSL` — Routing

```elixir
defmodule MyApp.Router do
  use Projection.Router.DSL

  screen_session :main do
    screen "/", MyApp.Screens.Home, :show, as: :home
    screen "/settings", MyApp.Screens.Settings, :show, as: :settings
  end

  screen_session :onboarding do
    screen "/welcome", MyApp.Screens.Welcome, :show, as: :welcome
  end
end
```

**Generated functions on the router module:**

| Function | Returns | Purpose |
|----------|---------|---------|
| `default_route_name/0` | `"home"` | First declared route |
| `route_defs/0` | `%{name => route_def}` | All routes by name |
| `route_keys/0` | `[:home, :settings, ...]` | Declaration-order atoms |
| `route_names/0` | `["home", "settings", ...]` | Declaration-order strings |
| `route_name/1` | `"home"` | Key atom -> name string |
| `route_path/1` | `"/"` | Key atom -> path string |
| `resolve/1` | `{:ok, route_def}` | Look up by name |
| `initial_nav/2` | `{:ok, nav}` | Create nav state |
| `current/1` | `route_entry` | Top of nav stack |
| `navigate/3` | `{:ok, nav}` | Push new route |
| `back/1` | `{:ok, nav}` | Pop stack |
| `patch/2` | `nav` | Merge params into current |
| `screen_session_transition?/2` | `{:ok, bool}` | Cross-session check |
| `to_vm/1` | `map` | Nav state as view-model |

**Navigation from Slint:**
```slint
// In a .slint file — triggers ui.route.navigate intent
root.intent("ui.route.navigate", "{\"to\":\"settings\",\"params\":{}}");

// Or via the generated navigate callback (preferred):
// navigate("settings", "{}");
```

### `Projection.Patch` — JSON Patch Utilities

Used internally by the Session to generate incremental updates:

```elixir
Projection.Patch.replace("/clock_text", "10:42:18")
# => %{"op" => "replace", "path" => "/clock_text", "value" => "10:42:18"}

Projection.Patch.add("/items/3", "new_item")
Projection.Patch.remove("/items/2")

Projection.Patch.pointer(["screen", "vm", "title"])
# => "/screen/vm/title"
```

JSON Pointer escaping: `~` -> `~0`, `/` -> `~1`

### `Projection.Protocol` — Envelope Encoding

```elixir
# Capacity constants
Projection.Protocol.inbound_cap()   # 65_536 bytes (UI -> Elixir)
Projection.Protocol.outbound_cap()  # 1_048_576 bytes (Elixir -> UI)

# Envelope builders
Projection.Protocol.render_envelope(sid, rev, vm, route_info)
Projection.Protocol.patch_envelope(sid, rev, ops, ack)
Projection.Protocol.error_envelope(sid, rev, code, message)

# Decode/encode
Projection.Protocol.decode_inbound(binary)   # -> {:ok, map} | {:error, reason}
Projection.Protocol.encode_outbound(map)     # -> {:ok, binary} | {:error, reason}
```

### `Projection.Telemetry` — Observability

```elixir
Projection.Telemetry.execute([:session, :mount], %{duration: 1234}, %{sid: "S1"})
```

All events under `[:projection, ...]` namespace. Gracefully no-ops if `:telemetry`
dependency is not loaded.

## Session Lifecycle

```
1. Projection.start_session(router: MyApp.Router)
   |
   v
2. SessionSupervisor starts Session GenServer + HostBridge
   |
   v
3. HostBridge opens port to Rust ui_host binary
   |
   v
4. Rust ui_host sends {t: "ready", sid: "S1", capabilities: {m1: true, transport: "stdio-packet-4"}}
   |
   v
5. Session receives ready -> mounts default route screen
   |
   v
6. Session calls screen.mount/3 -> render/1 -> produces view-model
   |
   v
7. Session sends {t: "render", sid: "S1", rev: 1, vm: {...}}
   |
   v
8. Rust applies properties to Slint components -> UI visible
   |
   v
9. User taps button -> Slint calls root.intent("hello.click", "")
   |
   v
10. Rust sends {t: "intent", sid: "S1", id: 1, name: "hello.click", payload: {}}
    |
    v
11. Session calls screen.handle_event("hello.click", %{}, state)
    |
    v
12. State changes tracked -> diff computed -> patch sent
    |
    v
13. {t: "patch", sid: "S1", rev: 2, ack: 1, ops: [{op: "replace", path: "/message", value: "Hello!"}]}
```

## HostBridge Details

The `ProjectionUI.Runtime.HostBridge` GenServer manages the Rust port:

- **Port config:** Binary mode, `{:packet, 4}` framing, exit status monitoring
- **Reconnection:** Bounded exponential backoff: 100ms, 200ms, 500ms, 1s, 2s, 5s
- **Backoff reset:** When connection stable for 2+ seconds
- **Envelope dispatch:** `HostBridge.send_envelope/2` casts outbound data
- **Error handling:** Malformed inbound data triggers error envelope back to Session

## State Management Patterns

### Pattern: Periodic Refresh

```elixir
def mount(_params, _session, state) do
  :timer.send_interval(5000, self(), :refresh)
  {:ok, state |> assign(:data, fetch_data())}
end

def handle_info(:refresh, state) do
  {:noreply, state |> assign(:data, fetch_data())}
end
```

### Pattern: PubSub Integration

```elixir
def subscriptions(_params, _session) do
  ["sensors:temperature", "network:status"]
end

def handle_info({:sensor_update, %{temp: t}}, state) do
  {:noreply, state |> assign(:temperature, t)}
end
```

### Pattern: Async Data Loading

```elixir
def mount(_params, _session, state) do
  send(self(), :load_data)
  {:ok, state |> assign(:loading, true)}
end

def handle_info(:load_data, state) do
  data = MyApp.DataSource.fetch()
  {:noreply, state |> assign(:loading, false) |> assign(:data, data)}
end
```

### Pattern: Intent with Payload Parsing

```elixir
def handle_event("device.toggle", %{"arg" => device_id}, state) do
  new_status = toggle_device(device_id)
  {:noreply, state |> assign(:device_status, new_status)}
end

# Always have a catch-all
def handle_event(_event, _payload, state), do: {:noreply, state}
```

### Pattern: id_table Management

```elixir
schema do
  field :devices, :id_table, columns: [name: :string, status: :string]
end

def mount(_params, _session, state) do
  devices = %{
    order: ["d1", "d2"],
    by_id: %{
      "d1" => %{name: "Sensor A", status: "online"},
      "d2" => %{name: "Sensor B", status: "offline"}
    }
  }
  {:ok, state |> assign(:devices, devices)}
end

# Update a single row — only that row's patch is sent
def handle_event("device.toggle", %{"arg" => id}, state) do
  {:noreply,
   update(state, :devices, fn table ->
     update_in(table, [:by_id, id, :status], fn
       "online" -> "offline"
       "offline" -> "online"
     end)
   end)}
end
```

## Configuration

### mix.exs

```elixir
defp deps do
  [
    {:projection, "~> 0.1.0"},
    {:jason, "~> 1.4"},
    {:telemetry, "~> 1.2"}
  ]
end
```

### config/config.exs

```elixir
import Config

# Logger metadata for structured logging
config :logger, :default_formatter, metadata: [:sid, :rev, :screen]

# Point to your router module
config :projection, router: MyApp.Router
```

### Application Supervisor

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # ... other children
      {Projection, router: MyApp.Router}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Codegen

The `mix compile` step runs `Projection.Codegen` which:

1. Reads all screen modules' `__projection_schema__/0`
2. Validates `render/1` output matches schema (keys + types)
3. Generates Rust source in `slint/ui_host/src/generated/`:
   - Type-safe setter functions per screen per field
   - `ScreenId` enum for screen switching
   - `apply_render` / `apply_patch` dispatchers

After codegen, rebuild the Rust host: `cargo build --release -p ui_host`

## Error Handling

The protocol defines these error codes:

| Code | Meaning | Triggers Resync |
|------|---------|-----------------|
| `decode_error` | Malformed JSON | Yes |
| `frame_too_large` | Payload exceeds capacity | Yes |
| `invalid_envelope` | Missing required fields | Yes |
| `resync_required` | Explicit resync request | Yes |
| `rev_mismatch` | Revision out of sequence | Yes |
| `patch_apply_error` | Patch operation failed | Yes |
| `validation_warning` | Non-fatal issue | No |

On resync, the Rust host sends a fresh `ready` envelope and the Session
responds with a full `render` envelope (revision reset).
