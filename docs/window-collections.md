# Floating windows and stacked columns

The strip enumerates mapped, non-hidden windows on its displayed scrolling
workspace. Floating windows remain present even when the optional Super+O
restoration helper is absent, loses its saved state, or returns invalid metadata.
A remembered tiled window retains its logical strip position; floats without a
remembered tiled origin follow the tiled columns. Floating a member out of a
stack creates a separate marked tile next to the surviving column.

Each real tiled column has one tile. A stack badge opens its members in native
top-to-bottom order, with individual focus and close actions. Its representative
is the focused member, then the last represented member still in that column.
Membership-based column identities keep the tile and popup anchor stable across
focus changes and whole-column moves. They are local to the running backend,
not persistent identifiers across compositor configuration reloads.

Window actions remain addressed to a specific member. In particular, successive
wheel notches follow the window floated out of a stack, and mouse presses retain
their initial window target if focus changes before release. The backend checks
workspace, monitor and current window membership before dispatching an action.
Column width changes and reordering still require tiled windows; reordering is
paused while floating entries are present.

## Validation on 3 October 2026

The private compositor suite passed all **71 cases**, including nine new window
collection cases. It loaded the production Lua backend and a freshly built
native library matching Hyprland 0.56.2, and extracted only the Super+O functions
from the supplied bindings file into its private configuration. It did not load
the user's full configuration or connect to the login compositor.

- A Super+O float remained visible and retained its tile identity and position
  after another client opened and received focus.
- Reinitializing the cycle helper reproduced the old backend losing the tile;
  the updated backend retained it. A complete configuration reload followed by
  another client launch also retained the floating entry.
- Bar-driven cycling returned a reloaded floating window to tiling while
  preserving the previously focused window.
- Real native stacks exposed the correct vertical member order, kept their
  identity and last-used representative across focus changes, and reordered
  as whole columns.
- A member floated out of a stack, survived another launch and rejoined in the
  correct order. Stacking also passed on a verified 900×1440 portrait output.

An ordinary new-client launch alone retained the tile with both the old and new
backends. The confirmed regression is dependence on lost cycle state; these
tests do not establish which event caused that state loss in the original
desktop report.

The test compositor used two owned virtual outputs, initially 1440×900, with
their dimensions checked before any geometry assertions. A private Weston GL
parent and a test-only Aquamarine transport provided buffers. On this dual-GPU
machine the parent required the Mesa EGL vendor and AMD render device; the
NVIDIA path failed allocation and was rejected. No graphics libraries were
installed or replaced. All test processes were cleaned up.

See [private test instructions](../tests/native/README.md) and
[offscreen input coverage](../tests/qml/README.md) for reproducible checks.
