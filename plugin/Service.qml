import QtQuick
import Quickshell.Io

// The Omarchy service lifecycle gives every monitor the same backend instance.
Backend {
  id: root
  property alias iconResolver: icons
  IconResolver { id: icons }
  IpcHandler {
    target: "user1.layout-strip"
    function refresh(): void { root.requestRefresh(null); root.updateRegion(null); }
    function debug(): string { return JSON.stringify(root.diagnostics()); }
    function monitor(name: string): string {
      return JSON.stringify(root.diagnostics().instances.filter(function(w) { return w.monitorName === name; }));
    }
  }
}
