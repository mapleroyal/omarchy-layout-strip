# Omarchy host integration

The widget targets Omarchy's built-in horizontal bar. It shares its theme,
popup coordinator, icon library, persistent shell settings and loaded service.
It does not modify package-owned Omarchy files. Native tape navigation is shared
with keyboard/gesture controls; disabling the widget must not unload that bridge.

## Compatibility boundary

`plugin/HostAdapter.js` owns reads and calls into the host's implementation. The
rest of the plugin consumes its functions and the pure `Geometry.measure(input)`.

| Capability | Host surface | Behavior if unavailable |
| --- | --- | --- |
| Bar allocation | `moduleSlots`, `layoutEntries` or `layoutConfig`, `centerAnchor`, slot `entry`/`activeItem`/width/visibility, window ownership helper | Explicit compatibility error; no guessed neighbor geometry |
| Settings | `bar.shell.updateEntryInline(id, entry)` | A failed result with an explanatory message |
| Placement | `bar.dropBarModule(slot, region, beforeId)` | A failed result; no direct shell.json write |
| Popup click forwarding | `registerClickTarget` and `unregisterClickTarget` | Skip registration; ordinary widget mouse handlers continue working |
| Shared backend | `bar.shell.serviceFor(id)` | Null service; the widget reports backend unavailability |
| Icons | `bar.shell.appLibrary.iconSource(name)` | Quickshell's icon lookup and generic application fallback |

These allocation and forwarding facilities exceed the documented basic widget
contract in `/usr/share/omarchy/shell/plugins/bar/README.md`. They are deliberately
isolated here rather than described as stable Omarchy APIs. Capabilities are
checked by shape, avoiding an arbitrary version gate. If Omarchy changes its
layout model, update this adapter and its regression tests together. A future
upstream allocation/entry-identity API would replace most of the adapter.

Geometry pairs each configured entry with one unused slot on the same bar
surface. It prefers actual entry identity, then equal entry values when QML has
wrapped them, then occurrence order for older/fake hosts. Repeated spacer or
indicator IDs therefore retain their own widths. Opacity-hidden widgets still
reserve width; invisible widgets reserve none. Tests include reverse registration
order, repeated IDs, hidden entries and foreign-monitor slots.

The host placement API addresses the first occurrence of a destination ID. The
menu offers each destination ID once; it does not pretend that a second identical
ID is separately addressable. Fine placement among repeated IDs remains available
through Omarchy's index-based CLI or direct configuration.

## Shared icon resolution

`IconResolver.qml` is instantiated by the shared service. It builds one index of
desktop entry IDs, `startupClass`, icon names and parsed launch commands, then
caches resolved class-to-icon names outside app delegates. The installed
Quickshell metadata exposes `DesktopEntry.execString`, `command`, `startupClass`
and `icon`; the isolated QML test validates these properties at runtime.

For Omarchy webapps, the resolver reads URLs from `omarchy-launch-webapp` launch
commands, or Chromium-family `--app` arguments. It matches `chrome-URL-Profile`
classes using the host/path app name; there are no application-specific icon
overrides. Chromium constructs URL app names from host and path, excluding query
and fragment ([Chromium source](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/web_applications/web_app_helpers.cc)).
Desktop entry ID/startup-class matches take precedence; unmatched classes retain
Quickshell's heuristic lookup. Ambiguous entries for the same URL choose the first
desktop ID in sorted order.

Only icon names are cached. Each image binding still resolves its name through
the host's `appLibrary.iconSource`, preserving live icon-index/theme changes.
Desktop metadata changes rebuild the index and invalidate cached names.

## Validation

```sh
node --test tests/Geometry.test.cjs tests/HostAdapter.test.cjs tests/IconModel.test.cjs
python3 tests/icons/run.py
```

The icon test uses temporary desktop files, configuration/cache directories and
Qt's offscreen platform. It creates no live bar, navigation, or persistent user
configuration. The separate full widget harness exercises the adapter together
with the supported bar/popup components.
