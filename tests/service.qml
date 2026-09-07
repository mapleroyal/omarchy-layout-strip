import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: test
  property var service: null
  property var widget: null
  property string selectedId: Quickshell.env("STRIP_PLUGIN_ID")
  function check(value, message) {
    if (!value) throw new Error(message);
  }
  QtObject {
    id: shell
    function serviceFor(id) { return test.service && id === test.service.pluginId ? test.service : null; }
  }
  QtObject {
    id: bar
    property var shell: shell
    property bool vertical: false
    property int barSize: 26
  }
  Component { id: serviceComponent; Plugin.Service { enabled: false } }
  Component { id: widgetComponent; Plugin.BarWidget { backendEnabled: false } }
  Component.onCompleted: {
    try {
      service = serviceComponent.createObject(test);
      check(service !== null, "Service component loads");
      check(service.pluginId === "user1.layout-strip", "Service retains local fallback before host injection");
      // Match ensureService() and ModuleSlot.injectProps() in the real host:
      // create first, then inject manifest / bar / moduleName.
      service.manifest = {id: selectedId};
      check(service.pluginId === selectedId, "Service follows injected manifest identity");
      widget = widgetComponent.createObject(test);
      check(widget !== null, "Nested widget component loads");
      widget.bar = bar;
      widget.moduleName = selectedId;
      check(widget.moduleName === selectedId, "Widget accepts host identity injection");
      check(widget.backendService === service, "Widget resolves the service under injected identity");
      console.log("SERVICE_READY", selectedId);
    } catch (error) {
      console.error("SERVICE_FAIL", error.stack || error);
      Qt.exit(1);
    }
  }
  Timer { interval: 12000; running: true; onTriggered: Qt.exit(2) }
}
