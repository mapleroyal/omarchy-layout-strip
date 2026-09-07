# Development

The maintained source lives in `plugin/`, `backend/`, `native/`, and `bin/`.
The root manifest publishes `io.github.mapleroyal.layout-strip` using the QML
entry points under `plugin/`. The installer also supports the existing personal
`user1.layout-strip` alias without changing its settings or bar entry.

The shared Omarchy service owns typed RPC transport, monitor batching, input
leases and action serialization. Each bar widget owns its stable column model,
scroll position and pointer interactions. `HostAdapter.js` is the boundary to
Omarchy's layout, settings, placement and forwarded-click APIs. Lua owns scrolling
policy and workspace repair; the versioned native library supplies compositor
operations. Keyboard and gesture controls share this backend.

See the [architecture and installation guide](README.md),
[host integration contract](docs/host-integration.md),
[Lua bootstrap](backend/README.md), and [native API](native/README.md).

## Validation

```sh
omarchy plugin validate .
python3 tests/run.py
```

The default suite runs deterministic models, typed protocol and scheduling
contracts, installer/doctor tests, Lua policies, native geometry/ownership tests,
and offscreen QML input. It does not dispatch actions to the login desktop.
See [QML scope](tests/qml/README.md) and
[private two-output native validation](docs/native-validation.md) for precise
coverage and the private graphics-transport requirements.

Read-only diagnostics:

```sh
hypr-tape-doctor
omarchy shell io.github.mapleroyal.layout-strip debug
hypr-tape-bar snapshot --monitor eDP-1
```

Use `user1.layout-strip` in the IPC command for the personal alias. Debug snapshots
include window titles and addresses; inspect them before sharing. Source API
research for possible previews is recorded in [preview feasibility](docs/preview-feasibility.md);
no preview feature has been implemented.

Keep generated libraries, private compositor runtimes and temporary test results
outside the source tree. Published native binaries are not supplied: rebuild
against the exact running compositor as documented in the README.
