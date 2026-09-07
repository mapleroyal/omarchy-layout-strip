# Native validation — 2026-09-07

The staged native bridge passed **10 behavioral cases in a private Hyprland with two headless outputs**. The native plugin was built against installed Hyprland 0.56.2 (`efb50993780079460b0cbed1363e2166a2de1d9f`), GCC 16.2.1 and Lua 5.5.1. [Results](native-results.json) preserve the case outcomes and measured positions.

| Case | Checked behavior |
|---|---|
| 1 | Protocol-v2 snapshots for both outputs, including native camera capability |
| 2 | Addressed pan on the nonfocused output without changing focus |
| 3 | Close leading offscreen column on nonfocused output; interior anchor 725→725px |
| 4 | Close trailing offscreen column on nonfocused output; interior anchor 725→725px |
| 5 | Addressed camera with a floating focused window |
| 6 | Close offscreen column while floating window retains focus; interior anchor 725→725px |
| 7 | Addressed native reorder while floating window retains focus and visible anchor stays put |
| 8 | Successful reorder invalidates a previously captured close-repair token |
| 9 | Stale monitor/workspace camera context is rejected without mutation |
| 10 | Clearing an old service's lease leaves its successor's registration active |

Configuration errors were empty. The harness cleaned up all its application clients, child compositor and private runtime; both temporary Weston parents were stopped afterward. **No live compositor input was tested.** The test never sent input or dispatches to the login compositor, and no physical-output backend was enabled. Native press/release protection is covered separately by production-header tests using actual Wayland event-loop idle dispatch and both Hyprutils signal-listener orders; no real mouse gesture was injected into the desktop.

A native boundary change can widen/reposition a newly first or last column by the configured 3px inner gap. The close tests therefore check an interior visible anchor and the native camera, rather than treating native edge-gap recalculation as a scrolling defect.

## Reproduction

Run the deterministic checks from the repository root with `python3 tests/run.py`. The final backend pass included 5 Lua suites, 13 Python CLI tests, and 3 C++ suites, including 1704 reorder geometry cases. The native library is built separately:

```sh
mkdir -p work/native-validation
native/build.sh "$PWD/work/native-validation/tape.so"
python3 tests/native/headless.py \
  --plugin "$PWD/work/native-validation/tape.so" \
  --output "$PWD/work/native-validation/results"
```

The harness creates and verifies its own compositor instance. If render-only initialization fails, it stops; it never opens a window in the login session as a fallback. On this machine, testing needed a separately owned headless GL Weston parent:

```sh
LD_LIBRARY_PATH="/absolute/private/aquamarine-build" \
python3 tests/native/headless.py \
  --plugin "$PWD/work/native-validation/tape.so" \
  --output "$PWD/work/native-validation/results" \
  --parent-display "/absolute/private/runtime/layout-strip-parent"
```

The parent used the unmodified upstream Weston 16.0.90 source, built with only the headless backend, GL renderer and kiosk shell; no input seat was requested. Its command was `weston --backend=headless --renderer=gl --shell=kiosk-shell.so --width=1600 --height=1000 --socket=layout-strip-parent --idle-time=0 --no-config`. Run it in a fresh 0700 `XDG_RUNTIME_DIR`, after removing inherited `WAYLAND_DISPLAY`, `WAYLAND_SOCKET`, `DISPLAY`, and `HYPRLAND_INSTANCE_SIGNATURE`. An uninstalled build also needs its `libweston` and `frontend` directories in the parent's private `LD_LIBRARY_PATH` and a `WESTON_MODULE_MAP` mapping each module filename to its absolute built `.so` path. Stop that exact owned parent process after the child harness finishes.

[Runtime provenance](native-runtime-provenance.json) records official source URLs, archive SHA-256 hashes, all Weston Meson options and the four explicit build targets. The Weston archive did not identify a commit; the archive hash records the exact source tested.

## Test-only graphics transport caveat

Installed Aquamarine 0.14 hardcodes Wayland bind versions that these Weston builds do not advertise. The private test process therefore used a matching Aquamarine 0.14 build with [three bind-version clamps](../tests/native/aquamarine-test-transport.patch), each changing the request to `min(advertised, supported)`. It does not advertise nonexistent server capabilities. No Hyprland layout code, native bridge code, rendering policy or input action was patched.

To rebuild that private compatibility library, unpack the exact Aquamarine archive in the provenance file, apply the patch with `patch -p1`, configure with `cmake -S source -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF`, then run `cmake --build build --target aquamarine -j4`. Scope its `LD_LIBRARY_PATH` to the private test command only. The validation is not a claim that installed Aquamarine can nest into Weston unmodified; the production compositor and system libraries were unchanged throughout.
