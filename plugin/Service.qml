import QtQuick
import Quickshell.Io

// The Omarchy service lifecycle gives every monitor the same backend instance.
Backend {
  id: root
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "user1.layout-strip"
  property alias iconResolver: icons
  IconResolver { id: icons }
  IpcHandler {
    target: root.pluginId
    function refresh(): void { root.requestRefresh(null); root.updateRegion(null); }
    function debug(): string { return JSON.stringify(root.diagnostics()); }
    function monitor(name: string): string {
      return JSON.stringify(root.diagnostics().instances.filter(function(w) { return w.monitorName === name; }));
    }
  }
}
