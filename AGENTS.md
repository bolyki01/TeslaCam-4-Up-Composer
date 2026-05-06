# AGENTS.md

Read in this order:

- [Root AGENTS](/Users/bolyki/dev/source/AGENTS.md)
- [Agent index](/Users/bolyki/dev/source/AGENT_INDEX.md)
- [README](./README.md)
- [Runbook](./RUNBOOK.md)
- [pyproject.toml](./pyproject.toml)
- `TeslaCam.xcodeproj`

Rules:

- Keep the macOS app and Python CLI docs aligned.
- Treat generated exports, build output, and work directories as derived.
- Use `/Users/bolyki/dev/source/build-env.sh` before native Swift builds, or point `TESLACAM_BUILD_ENV` at a compatible local override.
- Leave `TeslaCam/Resources/LICENSES.md` and other vendor or runtime assets alone unless the task is about licensing or packaging.
- Native export is the shipping app path. Do not reintroduce a CLI-only export assumption into the mac app.
- `_legacy/` stays reference-only unless the task explicitly targets it.

## Telemetry

- Do not add Sentry or external crash telemetry. Keep diagnostics local unless a repo runbook says otherwise.
