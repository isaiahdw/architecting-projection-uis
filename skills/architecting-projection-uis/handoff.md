# Handoff & Onboarding Guide

## Quick Start for New Developers

### Prerequisites

- Elixir >= 1.19
- Rust toolchain (rustup, cargo)
- Slint (installed via Cargo.toml dependency)

### Bootstrap a New Project

```bash
# Install the generator
mix archive.install hex projection_new

# Scaffold a new project
mix projection.new my_device_ui

# Build and run
cd my_device_ui
mix deps.get
mix compile                          # Runs Projection codegen
cd slint/ui_host && cargo build --release && cd ../..
mix run --no-halt
```

### What the Generator Creates

```
my_device_ui/
  config/config.exs                  # Logger metadata config
  lib/
    my_device_ui.ex                  # Application module
    my_device_ui/
      application.ex                 # Supervisor with session start
      router.ex                      # Router with one route
      screens/
        hello.ex                     # Sample screen
      ui/
        ui.slint                     # UI global (intent callback)
        screen.slint                 # Base Screen component
        app_shell.slint              # Navigation chrome
        error.slint                  # Error fallback
        hello.slint                  # Sample screen UI
  slint/
    ui_host/
      Cargo.toml                     # Rust dependencies (slint, serde_json)
      src/
        main.rs                      # app_main! macro invocation
        generated/.gitkeep           # Codegen output directory
  mix.exs
  test/
```

---

## Mental Model

Think of Projection like Phoenix LiveView, but instead of rendering HTML in a
browser, you render native UI via Slint on an embedded display.

| LiveView | Projection |
|----------|-----------|
| Browser + WebSocket | Slint + stdio port |
| HEEx templates | `.slint` files |
| `assign/2` -> DOM diff | `assign/3` -> JSON Patch |
| `handle_event/3` (JS event) | `handle_event/3` (intent) |
| `push_navigate` | `root.intent("ui.route.navigate", ...)` |
| LiveComponent | `use ProjectionUI, :component` |
| `on_mount` hooks | AppState module |

### Data Flow Diagram

```
                    Elixir (BEAM)                          Rust (ui_host)
               ┌─────────────────────┐              ┌─────────────────────┐
               │   Session GenServer  │              │    Slint Runtime    │
               │                     │   render     │                     │
  mount/3 ──>  │  State + Schema  ────────────────>  │  Properties set     │
               │                     │   patch      │  on Slint components│
  handle_*──>  │  assign/3 tracks ────────────────>  │                     │
               │  changed fields     │              │  TouchArea clicked  │
               │                     │   intent     │         │           │
               │  handle_event/3  <────────────────  │  root.intent()     │
               │                     │              │                     │
               └─────────────────────┘              └─────────────────────┘
                        │                                     │
                   HostBridge                           stdio {:packet,4}
                   (port mgmt)                        JSON envelopes
```

---

## Development Workflow

### Adding a New Screen

1. **Create the Elixir screen module:**

```elixir
# lib/my_app/screens/devices.ex
defmodule MyApp.Screens.Devices do
  use ProjectionUI, :screen

  schema do
    field :title, :string, default: "Devices"
    field :device_count, :integer, default: 0
    field :devices, :id_table, columns: [name: :string, status: :string]
  end

  @impl true
  def mount(_params, _session, state) do
    devices = MyApp.DeviceManager.list_devices()
    {:ok, state |> assign(:devices, devices) |> assign(:device_count, map_size(devices.by_id))}
  end

  @impl true
  def handle_event("device.select", %{"arg" => id}, state) do
    # Handle device selection
    {:noreply, state}
  end

  def handle_event(_event, _payload, state), do: {:noreply, state}
end
```

2. **Create the `.slint` component:**

```slint
// lib/my_app/ui/devices.slint
import { Screen } from "screen.slint";

export component DevicesScreen inherits Screen {
    in property <string> title: "Devices";
    in property <int> device_count: 0;
    // id_table fields are handled by codegen setters

    padding: 12px;
    spacing: 8px;

    Text {
        text: root.title + " (" + root.device_count + ")";
        font-size: 18px;
        color: #f2f2ff;
    }

    // Device list rendering handled by generated code
}
```

3. **Add the route:**

```elixir
# In your router module
screen_session :main do
  screen "/devices", MyApp.Screens.Devices, :index, as: :devices
end
```

4. **Rebuild:**

```bash
mix compile        # Regenerates Rust bindings
cd slint/ui_host && cargo build --release
```

### Adding a Reusable Component

1. **Create the component module:**

```elixir
defmodule MyApp.Components.StatusBadge do
  use ProjectionUI, :component

  schema do
    field :label, :string, default: ""
    field :is_active, :bool, default: false
  end
end
```

2. **Use it in a screen:**

```elixir
schema do
  field :title, :string, default: "Dashboard"
  component :network, MyApp.Components.StatusBadge, default: %{label: "WiFi", is_active: false}
end
```

3. **In the .slint file, use flattened property names:**

```slint
in property <string> network_label: "";
in property <bool> network_is_active: false;
```

### Adding App-Level State

```elixir
defmodule MyApp.AppState do
  use ProjectionUI, :app_state

  schema do
    field :clock, :string, default: "--:--"
  end

  @impl true
  def mount(state) do
    :timer.send_interval(1000, self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, assign(state, :clock, Calendar.strftime(DateTime.utc_now(), "%H:%M:%S"))}
  end
end
```

---

## Production Readiness Checklist

### Build & Deploy

- [ ] `mix compile` passes with no warnings
- [ ] Codegen produces valid Rust bindings
- [ ] `cargo build --release` succeeds for `ui_host`
- [ ] Binary size acceptable for target hardware
- [ ] Application starts cleanly with `mix run --no-halt`

### Architecture

- [ ] Every screen has a corresponding `.slint` component
- [ ] Schema types match between Elixir and Slint declarations
- [ ] All user interactions go through the intent system
- [ ] No business logic in `.slint` files
- [ ] Catch-all `handle_event` on every screen
- [ ] AppState used for cross-screen persistent data
- [ ] Router configured with proper screen sessions

### Reliability

- [ ] Error screen shows meaningful information
- [ ] HostBridge reconnection tested (kill and restart ui_host)
- [ ] Resync recovery verified (corrupt a frame, observe recovery)
- [ ] Session crash recovery tested
- [ ] Memory stable over time (no view-model growth leaks)

### Performance

- [ ] View-model sizes measured and within target
- [ ] Patch frequency measured under typical usage
- [ ] Intent queue not saturating (no drop logs)
- [ ] Startup time acceptable for use case
- [ ] Animations smooth on target hardware

### Observability

- [ ] Telemetry handlers attached
- [ ] Logger metadata configured: `[:sid, :rev, :screen]`
- [ ] Error codes monitored
- [ ] Resync frequency tracked

### Testing

- [ ] Unit tests for all screen handle_event callbacks
- [ ] Schema validation tests (validate_render!/1)
- [ ] Integration test: session starts and renders
- [ ] Visual review on target display

---

## Troubleshooting

### "Schema field type mismatch" at compile time

Your `render/1` output doesn't match the declared schema. Check:
- All schema fields are present in the render output
- Types match (e.g., don't return an integer for a `:string` field)
- No extra keys in the render output

### UI host crashes immediately

- Check `cargo build` succeeded
- Verify the binary path matches what HostBridge expects
- Check `PROJECTION_SID` env var if using custom session IDs
- Look at stderr output from the Rust process

### Intents not reaching Elixir

- Verify the intent name matches your `handle_event` pattern
- Check the intent callback chain: `root.intent()` -> `UI.intent()` -> Rust -> Elixir
- Look for "intent queue full" in Rust stderr logs
- Ensure HostBridge port is connected

### Patches not updating UI

- Check revision numbers are sequential (look for rev_mismatch errors)
- Verify `assign/3` is actually changing the value (same value = no change tracked)
- Check Rust stderr for patch apply errors
- Verify Slint property names match codegen expectations

### High memory usage

- Measure view-model size (JSON encode and check byte length)
- Switch large `:list` fields to `:id_table`
- Reduce update frequency for high-churn fields
- Check for state accumulation (growing lists, maps without cleanup)

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/*/router.ex` | Route definitions |
| `lib/*/screens/*.ex` | Screen modules |
| `lib/*/components/*.ex` | Reusable component schemas |
| `lib/*/app_state.ex` | Cross-screen persistent state |
| `lib/*/ui/*.slint` | Slint UI components |
| `slint/ui_host/src/main.rs` | Rust host entry point |
| `slint/ui_host/src/generated/` | Codegen output (do not edit) |
| `config/config.exs` | Logger + Projection config |
