# Best Practices & Guardrails

## The Golden Rule

> **Elixir owns truth. Slint renders a projection of that truth. Rust bridges the two.**

Every architectural decision should reinforce this separation:
- **Slint** = presentation layer (rendering, animations, input capture)
- **Elixir** = authority (state, business logic, data validation, routing decisions)
- **Rust** = transport (envelope encoding, property application, no policy)

---

## Do's

### Architecture

- **DO** keep screens single-responsibility — one screen, one concern
- **DO** use the schema DSL for every field the UI displays
- **DO** use `assign/3` for state updates (change tracking is automatic)
- **DO** add a catch-all `handle_event/3` clause to every screen
- **DO** use `subscriptions/2` for PubSub-driven data
- **DO** use AppState for data that crosses screen boundaries (clock, connectivity)
- **DO** use the router for multi-screen apps — avoid manual screen switching
- **DO** let the codegen task validate schema/render alignment at compile time

### Slint Components

- **DO** inherit from `Screen` for every screen component
- **DO** use `in property` for all data flowing from Elixir
- **DO** use `root.intent("noun.verb", "arg")` for user actions
- **DO** keep Slint components purely presentational
- **DO** use `animate` sparingly and keep durations short (<300ms)
- **DO** test on target hardware early — rendering budgets differ widely
- **DO** use conditional `if` blocks for show/hide patterns
- **DO** use consistent color tokens across components
- **DO** declare accessibility properties on custom interactive components
- **DO** use `@tr("...")` for all user-visible strings from the start (i18n)

### Data Flow

- **DO** prefer push-based updates (PubSub, timers, handle_info) over polling
- **DO** use `:id_table` for collections with row-level updates
- **DO** keep view-model payloads small — stay well under the 1 MB limit
- **DO** use `:list` only for small, infrequently changing collections
- **DO** format data in Elixir before sending (e.g., format temperatures as strings)

### Error Handling

- **DO** implement meaningful error screens with descriptive messages
- **DO** handle HostBridge reconnection gracefully (it has built-in backoff)
- **DO** monitor telemetry events in production
- **DO** log with `[:sid, :rev, :screen]` metadata

---

## Don'ts

### Architecture

- **DON'T** put business logic in `.slint` files — no calculations, no data transformations
- **DON'T** use Slint for state management — no `two-way` bindings to Elixir state
- **DON'T** bypass the intent system — all user actions go through `root.intent()`
- **DON'T** nest component schemas — v1 supports only one level of `component` declarations
- **DON'T** use `:map` type for structured data — use typed fields or `:id_table` instead
- **DON'T** skip compile-time validation — always run codegen before building the Rust host

### Slint Components

- **DON'T** poll or fetch data from within Slint — it has no network/IO capabilities
- **DON'T** animate layout-affecting properties (width, height) in complex trees
- **DON'T** use absolute positioning when layouts work — embedded displays need adaptability
- **DON'T** hardcode display dimensions — use relative sizing or layout properties
- **DON'T** create deeply nested component trees — keep the hierarchy flat
- **DON'T** concatenate strings with `+` for user-visible text — use `@tr("Hello, {}", name)` instead (allows translators to reorder)

### Data Flow

- **DON'T** send large blobs in intent payloads — the UI->Elixir cap is 64 KB
- **DON'T** do synchronous work in `mount/3` — it blocks the first render
- **DON'T** ignore the `ack` field in patches — it's used for intent delivery confirmation
- **DON'T** manually construct protocol envelopes — use the Protocol module helpers
- **DON'T** share mutable state between screens — use AppState instead

---

## Accessibility (from Slint Official Best Practices)

Declare accessibility properties early on every custom interactive component.
At minimum, provide a role and label:

```slint
component CustomButton inherits Rectangle {
    in property <string> text;

    // Accessibility — declare these on ALL interactive components
    accessible-role: button;
    accessible-label: self.text;
    accessible-action-default => {
        // Simulate the click action for screen readers
        root.clicked();
    }

    callback clicked();

    TouchArea { clicked => { root.clicked(); } }
    Text { text: root.text; }
}
```

**Minimum accessibility properties for common roles:**

| Role | Required Properties |
|------|-------------------|
| `button` | `accessible-label`, `accessible-action-default` |
| `slider` | `accessible-label`, `accessible-value`, `accessible-value-minimum`, `accessible-value-maximum` |
| `checkbox` | `accessible-label`, `accessible-checked` |
| `text` | `accessible-label` (if dynamic or truncated) |
| `list` | `accessible-label` on the container |

**Testing tools:**
- macOS: Accessibility Inspector (requires app bundle)
- Windows: Accessibility Insights
- Linux: Accerciser

---

## Internationalization (i18n)

Mark **all** user-visible strings as translatable from day one using `@tr()`:

```slint
// WRONG — not translatable, breaks with concatenation
Text { text: "Temperature: " + root.temp + " C"; }

// RIGHT — translatable with substitutions
Text { text: @tr("Temperature: {} C", root.temp); }

// RIGHT — allows translators to reorder arguments
Text { text: @tr("Hello, {name}!", name: root.user_name); }
```

**Plural forms:**
```slint
// Pipe separates singular/plural; % binds the count variable
Text { text: @tr("I have {n} item" | "I have {n} items" % count); }
```

**Context disambiguation** (same string, different meaning):
```slint
Text { text: @tr("Menu" => "Open the {}", menu_name); }
```

**Rules:**
- Use `@tr("...")` on every string shown to the user
- Use `{}` substitution instead of `+` concatenation — translators need to reorder
  arguments for natural phrasing in different languages
- Use indexed placeholders `{0}`, `{1}` when argument order may vary by language
- Internal debug strings and log messages do not need `@tr()`
- Slint's translation system integrates with gettext-compatible tooling

**Translation workflow:**
1. Extract: `find -name "*.slint" | xargs slint-tr-extractor -o PROJECT.pot`
2. Translate: Convert `.pot` to `.po` files per language (use poedit, Transifex, etc.)
3. Deploy: Either runtime gettext (`.mo` files) or **bundled translations** (embedded in binary)

**For embedded targets:** Use bundled translations (`CompilerConfiguration::with_bundled_translations()`
in Rust `build.rs`) — no filesystem needed at runtime.

**For Projection specifically:** Since Elixir owns the state, you can also do
translations in Elixir (via Gettext) and send pre-translated strings. Choose
one approach per project:

1. **Translate in Slint** (`@tr()`) — keeps translations in the UI layer, good
   when the Slint UI is reused across backends
2. **Translate in Elixir** (Gettext) — keeps translations in the authority layer,
   good when Elixir already has a Gettext setup and locale management

---

## Performance Guardrails for Embedded

### View-Model Size

The Elixir-to-UI payload cap is 1 MB, but aim much lower:

| Target | Recommended Max VM Size |
|--------|------------------------|
| Embedded Linux (RPi, etc.) | < 64 KB |
| Desktop/kiosk | < 256 KB |

**Mitigation strategies:**
- Use `:id_table` to send row-level patches instead of full lists
- Pre-format display strings in Elixir (send `"23.4 C"` not `23.4`)
- Split large screens into multiple screens with navigation

### Patch Frequency

- **Target:** < 30 patches/second for smooth UI
- **Risk zone:** > 60 patches/second may cause queue pressure
- **Mitigation:** Batch rapid state changes — the Session already batches within
  a single process turn, but throttle external data sources if needed

### Intent Queue

The Rust host has a bounded intent queue (default 256 entries):

- Intents are dropped silently when the queue is full (logged at power-of-two counts)
- Set `PROJECTION_UI_OUTBOUND_QUEUE_CAP` env var to tune
- If you see "intent queue full" logs, reduce UI interaction frequency or increase cap

### Startup Time

For embedded targets where boot time matters:

1. Minimize work in `mount/3` — defer to `handle_info`
2. Send initial render with defaults immediately
3. Load real data asynchronously after first paint
4. Keep the Rust binary size small — use `--release` with LTO

### Memory

- Each Session process holds the full view-model in memory
- HostBridge holds a port reference to the Rust process
- Rust host holds a copy of the current VM state (for patch application)
- **Total per-session:** ~3x the view-model size across the three layers

### Renderer Selection

For Projection on embedded Linux, **FemtoVG** (OpenGL ES 2.0+) is the default
renderer. All Slint features — drop shadows, rotation, clipping, `Layer` — work
fully. **Skia** is an alternative with higher rendering quality but a larger
binary footprint.

### Embedded Linux Platform Notes

- Requires modern Linux userspace with OpenGL ES 2.0+ or Vulkan
- Supported on Yocto, BuildRoot, Torizon OS 6.0+
- GPU-optimized containers available for i.MX8, AM62, i.MX95
- Use `@image-url()` at compile time to embed image assets in the binary
- Import custom fonts explicitly — don't rely on system fonts being present

---

## Testing Strategy

### Unit Testing Screens

```elixir
defmodule MyApp.Screens.DashboardTest do
  use ExUnit.Case

  alias MyApp.Screens.Dashboard
  alias ProjectionUI.State

  test "mount sets initial status" do
    state = State.new()
    {:ok, state} = Dashboard.mount(%{}, %{}, state)
    assert state.assigns[:status] == "initializing"
  end

  test "handle_event updates count" do
    state = State.new(%{click_count: 0, message: ""})
    {:noreply, state} = Dashboard.handle_event("hello.click", %{}, state)
    assert state.assigns[:click_count] == 1
  end

  test "render returns all schema keys" do
    defaults = Dashboard.schema()
    rendered = Dashboard.render(defaults)
    assert Map.keys(rendered) |> Enum.sort() == Map.keys(defaults) |> Enum.sort()
  end

  test "schema validation passes" do
    assert :ok == ProjectionUI.Schema.validate_render!(Dashboard)
  end
end
```

### Integration Testing with HostBridge

```elixir
defmodule MyApp.SessionIntegrationTest do
  use ExUnit.Case

  test "session starts and produces render envelope" do
    {:ok, _pid} = Projection.start_session(
      screen_module: MyApp.Screens.Dashboard
    )
    # Assert session is alive, telemetry events fired, etc.
  end
end
```

### Slint Visual Testing

- Use `slint-viewer` CLI to preview `.slint` files without Elixir
- Compare screenshots across commits for regression testing
- Test on actual target hardware — simulator rendering may differ

---

## Security Considerations

### Input Validation

- **All intent payloads are untrusted** — validate in `handle_event/3`
- Intent names are strings — match explicitly, never dynamically dispatch
- The `"arg"` field in payloads is always a string — parse and validate before use

### Payload Size

- Inbound (UI->Elixir): 64 KB hard cap — enforced by Protocol module
- Outbound (Elixir->UI): 1 MB hard cap — enforced by Protocol module
- Warning logged at 80% capacity

### Process Isolation

- Each session runs in its own supervised process tree
- HostBridge crash restarts the Rust port process automatically
- Session crash triggers a full resync on reconnection

### No Direct Elixir Execution from UI

The intent system is the only path from UI to Elixir logic. There is no
`eval` or dynamic code execution — intents are always dispatched through
explicit `handle_event/3` pattern matching.

---

## Observability Checklist

- [ ] Telemetry handlers attached for `[:projection, :session, :*]` events
- [ ] Logger configured with `metadata: [:sid, :rev, :screen]`
- [ ] HostBridge reconnection attempts logged
- [ ] Intent queue drop counts monitored
- [ ] View-model size tracked (especially for `:id_table` growth)
- [ ] Patch frequency measured under load
- [ ] Error envelope codes tracked for resync patterns
