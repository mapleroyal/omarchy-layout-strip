# Native checks

The small C++ tests compile against the headers in `native/` and exercise the production reorder planner, inhibitor lease, and region-owner registry. `test-bar-press.cpp` also links `hyprutils` and `wayland-server` to check both real signal-listener orderings.

`headless.py --plugin /absolute/staged/tape.so --output /absolute/work/results` creates an owned runtime directory and compositor with two headless outputs. It refuses the login compositor's instance signature and never connects to its IPC socket. Native render-only backend initialization can fail on systems where Aquamarine requires a parent graphics allocator; startup failure does not trigger a visible fallback.

For such systems, `--parent-display /absolute/private/headless-parent/socket` accepts an explicitly owned headless Wayland parent outside the login runtime. A private GL Weston parent can provide the render-node allocator without a physical display. Some Aquamarine releases bind protocol versions without clamping to the parent's advertised version; use a compatible parent/client build for testing. Keep test graphics libraries confined to the test process's `LD_LIBRARY_PATH`, never install or preload them into the login compositor.

The baseline behavioral cases cover protocol bulk snapshots, nonfocused-output camera control, leading/trailing close preservation, floating-focus close preservation, addressed reorder, deferred-token invalidation, stale context rejection, and replacement-service lease ownership. The harness cleans up its child compositor and clients in `finally`, and saves results and startup logs to the requested output directory.

The fullscreen regressions call the real Lua smooth-gesture methods in that private compositor, measure the fullscreen client's movement after event-loop processing, and verify cancellation, animated regrab, navigation away and back, multiple fullscreen columns, preserved internal/client fullscreen modes, and unsafe default fullscreen rejection. They do not inject physical touchpad input or run YouTube.

`private_parent.py --weston-build /absolute/private/weston-build --aquamarine-build /absolute/private/aquamarine-build --plugin /absolute/staged/tape.so --output /absolute/work/results` starts and cleans up an owned Weston GL parent for this harness. It requires already built transport dependencies and never installs them or falls back to the login session. Keep generated binaries and results outside the repository. See [native validation](../../docs/native-validation.md) for measured results and graphics transport provenance.
