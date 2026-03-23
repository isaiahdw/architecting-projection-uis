# Slint UI Architect

This project contains a Claude Code skill for architecting production-ready
Slint UIs for embedded Elixir applications using the Projection framework.

## Skill: `/architecting-projection-uis`

Invoke with `/architecting-projection-uis [feature-name] [phase]` where phase is one of:

- **plan** (default) — Requirements, component hierarchy, schema design
- **build** — Implementation guidance, code generation, wiring
- **review** — Architecture audit, guardrails check, production readiness

### Example Usage

```
/architecting-projection-uis thermostat-control plan
/architecting-projection-uis device-list build
/architecting-projection-uis review
```

## Architecture Principle

> Elixir owns truth. Slint renders a projection of that truth. Rust bridges the two.

## Key References

- **Slint docs:** https://docs.slint.dev/latest/docs/slint/
- **Projection source:** https://github.com/one-raven/projection
- **Skill files:** `skills/architecting-projection-uis/`

## Skill File Structure

```
skills/architecting-projection-uis/
  SKILL.md                    # Main skill (phases, workflows, reference)
  architecture-patterns.md    # Slint component hierarchy and layout patterns
  elixir-integration.md       # Projection API, state management, protocol
  best-practices.md           # Guardrails, performance, security, testing
  handoff.md                  # Onboarding, production checklist, troubleshooting
  adrs/
    001-state-ownership.md    # Elixir-authoritative state
    002-communication-protocol.md  # stdio + JSON framing
    003-patch-based-updates.md     # RFC 6902 incremental updates
    004-screen-lifecycle.md        # LiveView-inspired callbacks
    005-error-recovery.md          # Automatic resync
  examples/
    thermostat-screen.ex      # Full Elixir screen example
    thermostat.slint          # Corresponding Slint component
    device-list-screen.ex     # id_table example with row-level updates
```

## Conventions

- Screen names: `MyApp.Screens.FeatureName` (Elixir), `FeatureNameScreen` (Slint)
- Intent names: `noun.verb` — e.g., `thermostat.temp_up`, `device.select`
- Schema types must match: `:string`->`string`, `:bool`->`bool`, `:integer`->`int`, `:float`->`float`
- All `.slint` screen components inherit from `Screen`
- All user actions go through `root.intent(name, arg)`
