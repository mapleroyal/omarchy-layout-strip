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
  QtObject {
    id: inputWidget
    property bool backendEnabled: true
    property bool visible: true
    property string monitorName: "isolated-test"
    property int stateEpoch: 0
    property var bar: null
    property bool inputStateValid: false
    property int invalidations: 0
    property int snapshots: 0
    property int errors: 0
    property var snapshot: ({workspaceId:7})
    function invalidateInputState() { inputStateValid = false; invalidations++; }
    function onBackendSnapshot(data, inputFresh) {
      snapshot = data;
      snapshots++;
      inputStateValid = inputFresh === true;
    }
    function onBackendError(reason) { errors++; invalidateInputState(); }
  }
  function checkInputFreshness() {
    // Complete these deterministic callbacks in one event-loop turn, before
    // the service's timers can start any RPC. The runner also removes access
    // to the login compositor. All state below is an in-memory host fixture.
    service.enabled = true;
    service.registerWidget(inputWidget);
    var data = [{ok:true,monitorName:inputWidget.monitorName,workspaceId:7,
      workspaceHasFullscreen:false,columns:[]}];
    var pending = service.queryContext();
    service.applySnapshots(pending, data);
    check(inputWidget.inputStateValid, "An uninterrupted fresh snapshot authorizes input state");
    var generation = service.inputGeneration;
    service.handleEvent({name:"windowtitlev2"});
    service.requestRefresh(null);
    check(service.inputGeneration === generation && inputWidget.inputStateValid,
      "Title events and fallback refreshes preserve known input state");

    pending = service.queryContext();
    service.handleEvent({name:"fullscreen"});
    check(!inputWidget.inputStateValid && service.inputGeneration === generation + 1,
      "Fullscreen event immediately invalidates input before its query completes");
    service.refreshPending = false; // Model the queued read having been consumed.
    var delivered = inputWidget.snapshots;
    service.applySnapshots(pending, data);
    check(inputWidget.snapshots === delivered + 1 && !inputWidget.inputStateValid,
      "Stale in-flight reply updates ordinary data without authorizing input");
    check(service.refreshPending, "A stale in-flight reply schedules a newer state read");
    service.applySnapshots(service.queryContext(), data);
    check(inputWidget.inputStateValid, "Latest generation can authorize input again");

    pending = service.queryContext();
    inputWidget.visible = false;
    check(!service.hasVisibleWidgets && !inputWidget.inputStateValid,
      "Hiding the last widget revokes input authority before disconnecting events");
    inputWidget.visible = true;
    check(service.hasVisibleWidgets && !inputWidget.inputStateValid,
      "Revealing a widget cannot reuse pre-hide fullscreen coverage");
    service.applySnapshots(pending, data);
    check(!inputWidget.inputStateValid,
      "A pre-hide reply arriving after reveal cannot authorize input");
    service.applySnapshots(service.queryContext(), data);
    check(inputWidget.inputStateValid,
      "A new-generation reply after reveal restores input authority");

    ["activewindowv2", "openwindow", "closewindow", "movewindowv2", "workspacev2",
     "focusedmon", "monitoraddedv2", "activespecialv2", "changefloatingmode",
     "configreloaded", "togglegroup", "moveintogroup", "moveoutofgroup", "custom"].forEach(function(name) {
      service.applySnapshots(service.queryContext(), data);
      var before = service.inputGeneration;
      service.handleEvent({name:name});
      check(service.inputGeneration === before + 1 && !inputWidget.inputStateValid,
        name + " invalidates prior geometry authority");
    });
    service.applySnapshots(service.queryContext(), data);
    service.applySnapshots(service.queryContext(), [{ok:false,monitorName:inputWidget.monitorName,error:"unavailable"}]);
    check(!inputWidget.inputStateValid && inputWidget.errors === 1,
      "Unavailable monitor snapshot revokes input authority");
    service.unregisterWidget(inputWidget);
    service.enabled = false;
    console.log("INPUT_FRESHNESS_READY", selectedId);
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
      checkInputFreshness();
      console.log("SERVICE_READY", selectedId);
    } catch (error) {
      console.error("SERVICE_FAIL", error.stack || error);
      Qt.exit(1);
    }
  }
  Timer { interval: 12000; running: true; onTriggered: Qt.exit(2) }
}
