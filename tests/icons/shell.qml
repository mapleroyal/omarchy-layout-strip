import QtQuick
import Quickshell
import "../../plugin" as Strip

ShellRoot {
  id: root
  property int failures: 0
  property string source: resolver.iconFor("chrome-chat.example.test__channels_@me-Default", library)
  property string nativeSource: resolver.iconFor("CustomNative", library)
  Strip.IconResolver { id: resolver }
  QtObject {
    id: library
    property int generation: 1
    function iconSource(name) { return "theme" + generation + ":" + name; }
  }
  function check(condition, label) {
    if (!condition) { failures++; console.error("ICON_FAIL", label); }
  }
  Timer {
    interval: 40
    running: true
    onTriggered: {
      var entries = DesktopEntries.applications.values;
      var entry = null;
      for (var i = 0; i < entries.length; i++) if (entries[i].id === "test-chat") entry = entries[i];
      root.check(!!entry, "fixture desktop entry loaded");
      root.check(entry && entry.execString.indexOf("omarchy-launch-webapp") >= 0, "DesktopEntry.execString exists at runtime");
      root.check(entry && entry.command.length === 2, "DesktopEntry.command exposes parsed URL argument");
      root.check(root.source === "theme1:test-chat-icon", "generic webapp class resolved through real desktop metadata");
      root.check(root.nativeSource === "theme1:test-native-icon", "StartupWMClass resolved through real desktop metadata");
      library.generation = 2;
      Qt.callLater(function() {
        root.check(root.source === "theme2:test-chat-icon", "cached icon names retain live library/theme binding");
        resolver.entries = [{id:"test-chat",icon:"updated-chat-icon",execString:"omarchy-launch-webapp https://chat.example.test/channels/@me"}];
        Qt.callLater(function() {
          root.check(root.source === "theme2:updated-chat-icon", "desktop metadata changes invalidate class cache");
          console.log("ICON_RESULTS", JSON.stringify({failures:root.failures}));
          Qt.quit();
        });
      });
    }
  }
}
