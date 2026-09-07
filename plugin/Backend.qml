import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Protocol.js" as Protocol

// One host-owned controller for all monitor instances. State reads and input
// protection have independent schedules; neither process starts Python.
Item {
  id: root
  property var shell: null
  enabled: true
  property var widgets: []
  property bool busy: false
  property var pendingFocus: null
  property bool refreshPending: false
  property bool regionPending: false
  property var ownedMonitors: ({})
  property string leaseOwner: "layout-strip:" + Quickshell.processId + ":" + Date.now() + ":" + Math.random()
  property string backendError: ""
  property string regionError: ""
  property double lastSuccess: 0
  property int stateRequests: 0
  property int leaseRequests: 0
  property int actionRequests: 0
  readonly property bool hasVisibleWidgets: widgets.some(isActive)

  function isActive(widget) {
    return !!(widget && widget.backendEnabled && widget.visible && widget.monitorName &&
      !(widget.bar && widget.bar.barHidden === true));
  }
  function registered(widget) { return widget && widgets.indexOf(widget) !== -1; }
  function registerWidget(widget) {
    if (!widget || registered(widget)) return;
    widgets = widgets.concat([widget]);
    requestRefresh(widget);
    updateRegion(widget);
  }
  function unregisterWidget(widget) {
    widgets = widgets.filter(function(item) { return item && item !== widget; });
    if (pendingFocus && pendingFocus.widget === widget) pendingFocus = null;
    updateRegion(null);
  }
  function requestRefresh(widget) {
    if (!enabled) return;
    refreshPending = true;
    if (!refreshSoon.running) refreshSoon.start(); // throttle; title streams cannot starve refreshes
  }
  function updateRegion(widget) {
    if (!enabled) return;
    regionPending = true;
    if (!regionSoon.running) regionSoon.start();
  }
  function queryContext() {
    var records = [], monitors = [];
    widgets.forEach(function(widget) {
      if (!isActive(widget)) return;
      records.push({widget:widget,monitor:widget.monitorName,epoch:widget.stateEpoch});
      if (monitors.indexOf(widget.monitorName) < 0) monitors.push(widget.monitorName);
    });
    return {records:records,monitors:monitors};
  }
  function current(record) {
    return enabled && registered(record.widget) && isActive(record.widget) && record.widget.monitorName === record.monitor &&
      record.widget.stateEpoch === record.epoch;
  }
  function flushRefresh() {
    if (!enabled || !refreshPending) return;
    if (stateRpc.busy || busy) return;
    var ctx = queryContext();
    refreshPending = false;
    if (!ctx.monitors.length) return;
    stateRequests++;
    stateRpc.start(Protocol.snapshots(ctx.monitors), ctx);
  }
  function desiredRegions() {
    var regions = {}, remembered = Object.assign({}, ownedMonitors);
    Object.keys(remembered).forEach(function(name) { regions[name] = {monitor:name,x:0,y:0,width:0,height:0}; });
    widgets.forEach(function(widget) {
      if (!isActive(widget)) return;
      var rect = widget.protectedRegion();
      if (!rect || rect.length !== 4) return;
      remembered[widget.monitorName] = true;
      regions[widget.monitorName] = {monitor:widget.monitorName,x:rect[0],y:rect[1],width:rect[2],height:rect[3]};
    });
    ownedMonitors = remembered;
    return Object.keys(regions).map(function(name) { return regions[name]; });
  }
  function flushRegions() {
    if (!enabled || !regionPending || leaseRpc.busy) return;
    regionPending = false;
    var regions = desiredRegions();
    if (!regions.length) return;
    leaseRequests++;
    leaseRpc.start(Protocol.regions(regions, leaseOwner), {regions:regions});
  }
  function clearRegions() {
    var regions = Object.keys(ownedMonitors).map(function(name) { return {monitor:name,x:0,y:0,width:0,height:0}; });
    if (regions.length) Quickshell.execDetached(Protocol.regions(regions, leaseOwner));
  }
  function notifyError(ctx, reason) {
    backendError = reason;
    ctx.records.forEach(function(record) { if (current(record)) record.widget.onBackendError(reason); });
  }
  function completeRequest(request, result) {
    var widget = request && request.widget;
    if (registered(widget) && widget.stateEpoch === request.epoch) widget.onBackendActionFinished(result);
  }
  function runAction(widget, args) {
    var action;
    try { action = Protocol.parseAction(args); }
    catch (error) { completeRequest({widget:widget,epoch:widget.stateEpoch},{ok:false,error:String(error.message || error)}); return; }
    var request = {widget:widget,args:args,action:action,epoch:widget.stateEpoch};
    if (busy) {
      if (action.kind === "focus") {
        var old = pendingFocus;
        pendingFocus = request;
        if (old) completeRequest(old,{ok:true,changed:false,superseded:true});
      } else completeRequest(request,{ok:false,error:"Another window action is still finishing"});
      return;
    }
    startAction(request);
  }
  function startAction(request) {
    if (busy || actionRpc.busy) return false;
    var widget = request.widget, action = request.action;
    if (!registered(widget) || !isActive(widget) || action.monitorName !== widget.monitorName ||
        action.workspaceId !== widget.snapshot.workspaceId || request.epoch !== widget.stateEpoch) {
      completeRequest(request,{ok:false,error:"The displayed workspace changed; select the window again"});
      return false;
    }
    busy = true;
    actionRequests++;
    if (!actionRpc.start(action.command, request)) {
      busy = false;
      completeRequest(request,{ok:false,error:"Another window action is still finishing"});
      return false;
    }
    return true;
  }
  function finishAction(context, result) {
    // Callbacks can enqueue a newer intent synchronously. Keep ownership until
    // they finish, then take the latest shared queue exactly once.
    completeRequest(context, result);
    var next = pendingFocus;
    pendingFocus = null;
    busy = false;
    if (next && startAction(next)) return;
    requestRefresh(null);
    updateRegion(null);
  }
  function diagnostics() {
    return {protocolVersion:Protocol.VERSION,backendError:backendError,regionError:regionError,
      lastSuccess:lastSuccess,busy:busy,queuedFocus:!!pendingFocus,
      requests:{state:stateRequests,regions:leaseRequests,actions:actionRequests},
      instances:widgets.filter(function(w){return !!w;}).map(function(w){return JSON.parse(w.debugState());})};
  }
  onHasVisibleWidgetsChanged: { requestRefresh(null); updateRegion(null); }
  onEnabledChanged: if (!enabled) clearRegions()
  Component.onDestruction: clearRegions()
  Connections {
    target: Hyprland
    enabled: root.enabled && root.hasVisibleWidgets
    function onRawEvent(event) {
      if (/^(activewindow|openwindow|closewindow|movewindow|workspace|focusedmon|monitor|activespecial|fullscreen|changefloatingmode|configreloaded|windowtitle|togglegroup|moveintogroup|moveoutofgroup|custom)/.test(event.name))
        root.requestRefresh(null);
    }
  }
  Timer { id: refreshSoon; interval: 45; onTriggered: root.flushRefresh() }
  Timer { id: regionSoon; interval: 30; onTriggered: root.flushRegions() }
  Timer { interval: 1000; running: root.enabled && root.hasVisibleWidgets; repeat: true; onTriggered: root.requestRefresh(null) }
  Timer { interval: 1500; running: root.enabled && root.hasVisibleWidgets; repeat: true; onTriggered: root.updateRegion(null) }
  RpcProcess {
    id: stateRpc
    onCompleted: function(ctx, output, error, code) {
      try {
        if (code || error) throw new Error(error || "Could not read the layout backend");
        var data = Protocol.reply(output);
        if (!data.ok) throw new Error(data.error || "Layout backend unavailable");
        if (!Array.isArray(data.snapshots)) throw new Error("Layout backend returned invalid monitor snapshots");
        var byMonitor = {};
        data.snapshots.forEach(function(snapshot) { byMonitor[snapshot.monitorName] = snapshot; });
        root.backendError = "";
        root.lastSuccess = Date.now();
        ctx.records.forEach(function(record) {
          if (!root.current(record)) return;
          var snapshot = byMonitor[record.monitor];
          if (!snapshot || snapshot.ok !== true || !Array.isArray(snapshot.columns))
            record.widget.onBackendError(snapshot && snapshot.error || "The monitor snapshot is unavailable");
          else record.widget.onBackendSnapshot(snapshot);
        });
      } catch (failure) { root.notifyError(ctx, String(failure.message || failure)); }
      if (root.refreshPending) refreshSoon.restart();
    }
  }
  RpcProcess {
    id: leaseRpc
    onCompleted: function(ctx, output, error, code) {
      try {
        if (code || error) throw new Error(error || "Input protection registration failed");
        var result = Protocol.reply(output);
        if (!result.ok) throw new Error(result.error || "Input protection unavailable");
        root.regionError = "";
        var remembered = Object.assign({}, root.ownedMonitors);
        ctx.regions.forEach(function(r) { if (!r.width && !r.height) delete remembered[r.monitor]; });
        root.ownedMonitors = remembered;
      } catch (failure) { root.regionError = String(failure.message || failure); }
      if (root.regionPending) regionSoon.restart();
    }
  }
  RpcProcess {
    id: actionRpc
    onCompleted: function(ctx, output, error, code) {
      var result;
      try {
        if (code || error) throw new Error(error || "Window action failed");
        result = Protocol.reply(output);
      } catch (failure) { result = {ok:false,error:String(failure.message || failure)}; }
      root.finishAction(ctx,result);
    }
  }
}
