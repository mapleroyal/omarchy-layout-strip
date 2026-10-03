# Native checks

The small C++ tests compile against the headers in `native/` and exercise the production reorder planner, inhibitor lease, and region-owner registry. `test-bar-press.cpp` also links `hyprutils` and `wayland-server` to check both real signal-listener orderings.

`headless.py --plugin /absolute/staged/tape.so --output /absolute/work/results` creates an owned runtime directory and compositor with two headless outputs. It refuses the login compositor's instance signature and never connects to its IPC socket. Native render-only backend initialization can fail on systems where Aquamarine requires a parent graphics allocator; startup failure does not trigger a visible fallback.

For such systems, `--parent-display /absolute/private/headless-parent/socket` accepts an explicitly owned headless Wayland parent outside the login runtime. A private GL Weston parent can provide the render-node allocator without a physical display. Some Aquamarine releases bind protocol versions without clamping to the parent's advertised version; use a compatible parent/client build for testing. Keep test graphics libraries confined to the test process's `LD_LIBRARY_PATH`, never install or preload them into the login compositor.

The baseline behavioral cases cover protocol bulk snapshots, nonfocused-output camera control, leading/trailing close preservation, floating-focus close preservation, addressed reorder, deferred-token invalidation, stale context rejection, and replacement-service lease ownership. The harness cleans up its child compositor and clients in `finally`, and saves results and startup logs to the requested output directory.

The fullscreen regressions call the real Lua smooth-gesture methods in that private compositor, measure the fullscreen client's movement after event-loop processing, and verify cancellation, animated regrab, navigation away and back, multiple fullscreen columns, preserved internal/client fullscreen modes, and unsafe default fullscreen rejection. They do not inject physical touchpad input or run YouTube.

`private_parent.py --weston-build /absolute/private/weston-build --aquamarine-build /absolute/private/aquamarine-build --plugin /absolute/staged/tape.so --output /absolute/work/results` starts and cleans up an owned Weston GL parent for this harness. It requires already built transport dependencies and never installs them or falls back to the login session. Keep generated binaries and results outside the repository. See [native validation](../../docs/native-validation.md) for measured results and graphics transport provenance.


## Floating windows and stacked columns

Pass `--cycle-bindings /absolute/user/bindings.lua` to add nine real compositor
lifecycle regressions to the normal suite. The harness reads that file and copies
only the contiguous cycle implementation, from
`local floating_width_cycle_state = {}` up to
`local function cycle_focused_window_width()`, into its private output directory.
It loads that copy into its own compositor. It never sources the rest of the
user's bindings, edits their configuration, or dispatches a login-session key.
The supplied file must contain those explicit boundaries; no synthetic cycle
state is substituted when they are missing.

The checks call the same cycle functions used by Super+O and strip scrolling.
They cover app launch while floating, lost cycle state, a full private config
reload, nonfocused strip cycles, native stack ordering and member focus, stable
column identity, whole-stack reorder, floating/restoring one stack member, and a
900×1440 portrait output. Monitor modes must reach their requested dimensions
before geometry assertions run. These are compositor/backend integration tests;
physical key presses, touchpad gestures, and the live QML bar are not exercised.

For a direct regression comparison, save a previous revision's `tape-bar.lua`
outside the repository and supply `--baseline-bar /absolute/work/old-tape-bar.lua`.
The harness verifies that both implementations retain a cycle-floated window on
ordinary app launch, then confirms that the previous implementation drops its
tile after the copied cycle implementation loses its local state while the new
implementation retains it. This proves the state dependency, without asserting
that a normal app launch itself causes state loss.

```sh
python3 tests/native/private_parent.py \
  --weston-build /absolute/private/weston-build \
  --aquamarine-build /absolute/private/aquamarine-build \
  --plugin /absolute/staged/tape.so \
  --output /absolute/work/native-results \
  --cycle-bindings /absolute/user/bindings.lua \
  --baseline-bar /absolute/work/old-tape-bar.lua
```

Add `--collections-only` to run just these nine cases. Both extra switches
require `--cycle-bindings`. Keep extracted bindings and generated configurations
outside the repository; they contain machine-specific user source.

On a multi-GPU machine, the private parent's allocator must support actual GBM
buffers. The October 3 validation used an AMD Mesa render node, selected only for
the test command with `__EGL_VENDOR_LIBRARY_FILENAMES` pointing at Mesa's EGL
vendor JSON and `DRI_PRIME` selecting that GPU. A failed NVIDIA allocation left
headless outputs at 0×0 and was rejected by the dimension checks. Select a
working private renderer for the machine rather than bypassing those checks.
