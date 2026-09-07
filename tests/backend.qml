import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: test
  property int checks: 0
  property int failures: 0
  property int stage: 0
  property int ticks: 0
  property int hiddenRequests: 0
  property bool timeoutDone: false
  property bool missingDone: false
  property bool chaining: false
  function check(ok, description) {
    checks++;
    if (!ok) { failures++; console.error("FAIL", description); }
  }
  function command(widget, address) {
    widget.stateEpoch++;
    return ["unused", "focus", address, "--workspace", String(widget.snapshot.workspaceId), "--monitor", widget.monitorName];
  }
  Plugin.Backend { id: backend; enabled: true }
  component FakeWidget: Item {
    property bool backendEnabled: true
    property string monitorName: "eDP-1"
    property var bar: ({barHidden:false})
    property int stateEpoch: 0
    property var snapshot: ({workspaceId:1,columns:[]})
    property int reads: 0
    property var actions: []
    property string error: ""
    function protectedRegion() { return [0,0,120,26]; }
    function onBackendSnapshot(data) { snapshot=data; reads++; }
    function onBackendError(value) { error=value; }
    function onBackendActionFinished(value) { actions=actions.concat([value]); }
    function debugState() { return JSON.stringify({monitorName:monitorName,workspaceId:snapshot.workspaceId}); }
  }
  FakeWidget { id: first }
  FakeWidget { id: second; monitorName:"DP-2"; snapshot:({workspaceId:2,columns:[]}) }
  Plugin.RpcProcess {
    id: timeoutProbe
    timeoutMs: 70
    onCompleted: function(context, output, error, exitCode) {
      if (!test.chaining) {
        test.check(error.indexOf("timed out") >= 0 && !busy, "hung requests terminate and release busy state");
        test.chaining=true;
        var retired=requestSerial;
        start(["/usr/bin/true"],"new request");
        finish(-1,retired);
        test.check(busy && timeoutProbe.context === "new request", "late completion cannot finish a newer RPC");
      } else {
        test.check(exitCode === 0, "completion callback may start another request");
        test.timeoutDone=true;
      }
    }
  }
  Plugin.RpcProcess {
    id: missingProbe
    timeoutMs: 70
    onCompleted: function(context, output, error, exitCode) {
      test.check(exitCode !== 0 && !busy, "missing command releases busy state");
      test.missingDone=true;
    }
  }
  Component.onCompleted: {
    backend.registerWidget(first);
    backend.registerWidget(second);
    timeoutProbe.start(["/usr/bin/sleep","30"],null);
    missingProbe.start(["/does/not/exist/layout-strip-test"],null);
  }
  Timer {
    interval: 80
    running: true
    repeat: true
    onTriggered: {
      test.ticks++;
      if (test.ticks > 110) { console.error("BACKEND_TEST_TIMEOUT",test.stage); Qt.exit(1); return; }
      if (test.stage === 0 && first.reads && second.reads) {
        test.check(backend.stateRequests===1,"two monitor instances share one bulk snapshot request");
        test.check(first.snapshot.monitorName==="eDP-1" && second.snapshot.monitorName==="DP-2","bulk snapshots route to the correct monitor");
        var record={widget:first,monitor:first.monitorName,epoch:first.stateEpoch};
        first.stateEpoch++;
        test.check(!backend.current(record),"a pre-action response cannot overwrite a newer widget epoch");
        backend.runAction(first,test.command(first,"0x1"));
        backend.runAction(first,test.command(first,"0x2"));
        backend.runAction(second,test.command(second,"0x3"));
        test.check(backend.pendingFocus.widget===second,"newest focus replaces queued focus across monitors");
        backend.runAction(second,["unused","close","0x3","--workspace","2","--monitor","DP-2"]);
        test.check(second.actions.some(function(r){return r.ok===false;}),"destructive actions are never queued while busy");
        test.stage=1;
      } else if (test.stage===1 && backend.actionRequests===2 && !backend.busy) {
        test.check(first.actions.some(function(r){return r.superseded===true;}),"superseded focus request receives completion");
        test.check(second.actions.some(function(r){return r.ok===true && r.address==="0x3";}),"latest queued focus is the action actually dispatched");
        first.visible=false;
        second.visible=false;
        backend.updateRegion(null);
        test.stage=2;
      } else if (test.stage===2 && !Object.keys(backend.ownedMonitors).length) {
        test.hiddenRequests=backend.stateRequests;
        test.ticks=0;
        test.stage=3;
      } else if (test.stage===3 && test.ticks>18) {
        test.check(backend.stateRequests===test.hiddenRequests,"hidden widgets stop state polling");
        test.check(!Object.keys(backend.ownedMonitors).length,"hidden widgets explicitly clear owned native regions");
        test.check(test.timeoutDone && test.missingDone,"request watchdog handles timeout and launch failure");
        backend.unregisterWidget(first);
        backend.unregisterWidget(second);
        console.log("BACKEND_RESULTS",JSON.stringify({checks:test.checks,failures:test.failures}));
        Qt.exit(test.failures ? 1 : 0);
      }
    }
  }
}
