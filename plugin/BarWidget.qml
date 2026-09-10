import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Geometry.js" as Geometry
import "HostAdapter.js" as HostAdapter

BarWidget {
  id: root
  moduleName: "user1.layout-strip"

  property var snapshot: ({columns: []})
  property bool backendEnabled: true
  property string lastSnapshot: ""
  property string lastFocused: ""
  property int lastWorkspace: 0
  property bool menuOpen: false
  property var menuAnchor: null
  property int menuCursor: 0
  property bool hoverArmed: true
  property real scrollOffset: 0
  property real scrollGoal: 0
  property real geometryGap: 0
  property var placement: ({allocation: 0})
  property string menuKind: "general"
  property string menuAddress: ""
  property int menuWorkspace: 0
  property string menuMonitor: ""
  property string placementRegion: "left"
  property var placementChoices: []
  property var deferredSnapshot: null
  property int stateEpoch: 0
  property var lastCommand: []
  property string actionError: ""
  property string queryError: ""
  property bool backendStale: false
  property bool actionBusy: false
  property var pendingFocus: null
  property var registeredBackend: null
  readonly property var backendService: HostAdapter.service(bar, moduleName)
  readonly property bool globalBusy: backendEnabled && backendService ? backendService.busy : false
  readonly property bool operationBusy: actionBusy || globalBusy
  readonly property bool barHidden: HostAdapter.hidden(bar)
  readonly property var measuredInput: HostAdapter.geometryInput(root, bar, surface, Style.space(8))
  property int snapshotRevision: 0
  property real previousViewportWidth: 0
  property bool preserveVisibleFocus: false
  property bool viewportUpdatePending: false
  readonly property string statusMessage: operationBusy ? "Window action in progress" : (actionError || queryError || hostCapabilities.error || (backendService && backendService.regionError) || "")
  readonly property var hostCapabilities: HostAdapter.capabilities(bar, root, surface)
  readonly property Item stripItem: strip
  readonly property Item viewportItem: viewport
  property bool dragging: false
  property var dragColumn: null
  property int dragWorkspace: 0
  property string dragMonitor: ""
  property real dragX: 0
  property real dragY: 0
  property var dropTarget: null
  property bool resizing: false
  property real resizeWidth: 0
  property real resizeCenter: 0
  signal actionRequested(var command)
  property int scrollDirection: 0
  property double lastFrame: 0

  readonly property var columns: snapshot.columns || []
  property var surface: root.QsWindow.window
  readonly property string monitorName: surface && surface.screen ? surface.screen.name : ""
  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/hypr-tape-bar"
  readonly property string arrowMode: setting("arrowMode", "hover") === "click" ? "click" : "hover"
  readonly property string indicationMode: setting("indicationMode", "underlines") === "tiles" ? "tiles" : "underlines"
  readonly property real iconSize: Style.bar.iconCanvas
  readonly property real itemPadding: Style.space(6)
  readonly property real itemGap: Style.space(4)
  readonly property real arrowSize: Style.bar.statusSlot
  readonly property real edgeWidth: Style.space(4)
  readonly property bool compactStrip: capacity < (arrowSize + edgeWidth) * 2 + iconSize + itemPadding * 2
  readonly property real endSpace: compactStrip ? edgeWidth : arrowSize + edgeWidth
  readonly property bool arrowsShown: !compactStrip && (overflow || stripHover.hovered || menuOpen || dragging || resizing)
  readonly property bool canReorder: snapshot.reorderAvailable === true && columns.length > 1 && !operationBusy && !backendStale
  readonly property real contentInset: Math.max(0, (viewportWidth - naturalWidth) / 2)
  readonly property var menuItems: buildMenuItems()
  readonly property real naturalWidth: {
    var total = 0;
    for (var i = 0; i < columns.length; i++) total += tileWidth(columns[i]);
    return total + Math.max(0, columns.length - 1) * itemGap;
  }
  readonly property real capacity: Math.max(0, geometryGap * 0.85)
  readonly property real minimumWidth: Math.min(capacity, endSpace * 2 + iconSize + itemPadding * 2)
  readonly property real stripWidth: Math.max(minimumWidth, Math.min(capacity,
    resizing ? resizeWidth : geometryGap * Model.widthRatio(setting("widthRatio", 0.85))))
  readonly property real viewportWidth: Math.max(0, stripWidth - endSpace * 2)
  readonly property bool overflow: naturalWidth > viewportWidth + 0.5
  readonly property real maximumOffset: Math.max(0, naturalWidth - viewportWidth)
  readonly property color foreground: bar ? bar.barForeground : Color.foreground

  visible: !vertical
  implicitWidth: visible ? geometryGap : 0
  implicitHeight: barSize

  // App dragging and resizing own pointer input. Widget placement is offered
  // explicitly in the menu through the host's normal persistent move API.
  Binding { target: root.parent; property: "z"; value: 1; when: root.parent !== null }

  function tileWidth(column) {
    var factor = Model.sizeFactor(column.size);
    // Include the inset outside the scaled visual width so painted tiles have
    // exactly 1:1.5:2 widths, rather than scaling only their inner icon area.
    return indicationMode === "tiles"
      ? (iconSize + itemPadding * 2) * factor + Style.space(2)
      : iconSize * factor + itemPadding * 2;
  }

  ColumnModel { id: columnModel }
  Loader {
    id: fallbackIcons
    active: !root.backendService || !root.backendService.iconResolver
    sourceComponent: IconResolver {}
  }

  function syncColumns(next) { columnModel.synchronize(next); }

  function measureGap() {
    if (resizing || dragging) return;
    // Geometry reads other widgets' widths, never positions influenced by our
    // own width. The allocation stays fixed while the inner strip is resized.
    placement = Geometry.measure(measuredInput);
    geometryGap = placement.allocation || 0;
  }

  function syncBackend() {
    var next = backendEnabled ? backendService : null;
    if (registeredBackend !== next) {
      if (registeredBackend) registeredBackend.unregisterWidget(root);
      registeredBackend = next;
      actionBusy = false;
      pendingFocus = null;
      if (registeredBackend) registeredBackend.registerWidget(root);
    }
    if (registeredBackend) registeredBackend.updateRegion(root);
  }
  function requestRefresh() {
    if (!backendEnabled || !monitorName) return;
    syncBackend();
    if (registeredBackend) registeredBackend.requestRefresh(root);
    else onBackendError("The layout strip service is unavailable; reinstall or reload the plugin");
  }
  function refreshRegion() {
    if (registeredBackend) registeredBackend.updateRegion(root);
  }

  function protectedRegion() {
    if (!surface || !surface.screen || !root.visible || !strip.visible || barHidden) return [0, 0, 0, 0];
    var point = strip.mapToItem(surface.contentItem, 0, 0);
    var bottomOffset = bar && bar.position === "bottom" ? surface.screen.height - surface.height : 0;
    return [root.Screen.virtualX + point.x, root.Screen.virtualY + bottomOffset + point.y,
      strip.width, strip.height];
  }

  function applySnapshot(data) {
    if (!data || data.ok === false || !Array.isArray(data.columns)) {
      onBackendError(data && data.error || "Layout data is unavailable");
      return;
    }
    queryError = "";
    backendStale = false;
    if (dragging || resizing) {
      var sameWorkspace = data.workspaceId === snapshot.workspaceId;
      var sourceExists = !dragging || data.columns.some(function(column) { return column.address === dragColumn.address; });
      if (sameWorkspace && sourceExists) { deferredSnapshot = data; return; }
      deferredSnapshot = null;
      cancelDrag();
      finishResize(false);
    }
    var signature = JSON.stringify(data);
    if (signature === lastSnapshot) return;
    var changedWorkspace = data.workspaceId !== lastWorkspace;
    var changedFocus = data.activeAddress !== lastFocused;
    if (menuOpen && (changedWorkspace || (menuKind === "app" && !data.columns.some(function(column) {
      return column.address === menuAddress;
    })))) { close(); menuAnchor = null; }
    syncColumns(data.columns);
    snapshot = data;
    lastSnapshot = signature;
    lastWorkspace = data.workspaceId || 0;
    lastFocused = data.activeAddress || "";
    var revision = ++snapshotRevision;
    Qt.callLater(function() {
      if (revision !== root.snapshotRevision) return;
      if (changedWorkspace) setOffset(0, false);
      if (changedWorkspace || changedFocus) revealFocused();
      else reconcileOffset();
    });
  }

  function onBackendSnapshot(data) { applySnapshot(data); }
  function onBackendError(error) {
    queryError = String(error || "Layout data is unavailable");
    backendStale = true;
  }
  function onBackendActionFinished(result) {
    actionBusy = false;
    actionError = result && result.ok === false ? String(result.error || "Window action failed") : "";
    var pending = pendingFocus;
    pendingFocus = null;
    if (!backendEnabled && pending && pending[pending.indexOf("--workspace") + 1] === String(snapshot.workspaceId) &&
        pending[pending.indexOf("--monitor") + 1] === monitorName) runAction(pending);
  }
  function runAction(command) {
    if (backendEnabled && backendStale) {
      actionError = queryError || "Window data is stale; wait for the connection to recover";
      return;
    }
    // The shared service owns the live cross-monitor queue. The local queue
    // exists only for standalone/test controllers without a backend.
    if (!backendEnabled && actionBusy) {
      if (command[1] === "focus") pendingFocus = command;
      return;
    }
    if (operationBusy && command[1] !== "focus") {
      actionError = "Another window action is still finishing";
      return;
    }
    actionError = "";
    stateEpoch++;
    deferredSnapshot = null;
    lastCommand = command;
    actionRequested(command);
    if (!backendEnabled) return;
    if (!backendService) { onBackendError("The layout strip service is unavailable"); return; }
    actionBusy = true;
    backendService.runAction(root, command);
  }

  function focusColumn(column) {
    if (dragging || resizing || !column || !Model.validAddress(column.address)) return;
    close();
    runAction([helper, "focus", column.address, "--workspace", String(snapshot.workspaceId), "--monitor", monitorName]);
  }

  function closeColumn(column) {
    if (dragging || resizing) return;
    var address = column ? column.address : menuAddress;
    var workspace = column ? snapshot.workspaceId : menuWorkspace;
    var monitor = column ? monitorName : menuMonitor;
    close();
    if (!Model.validAddress(address)) return;
    runAction([helper, "close", address, "--workspace", String(workspace), "--monitor", monitor]);
  }

  function beginDrag(column, point) {
    if (!canReorder || resizing || menuOpen) return false;
    glide.stop();
    scrollDirection = 0;
    dragColumn = column;
    dragWorkspace = snapshot.workspaceId;
    dragMonitor = monitorName;
    dragging = true;
    updateDrag(point);
    return true;
  }

  function updateDrag(point) {
    if (!dragging) return;
    dragX = point.x;
    dragY = point.y;
    updateDropTarget();
  }

  function updateDropTarget() {
    if (!dragging) return;
    var inside = dragX >= 0 && dragX <= stripWidth && dragY >= 0 && dragY <= barSize;
    if (!inside) { dropTarget = null; return; }
    var widths = columns.map(function(column) { return tileWidth(column); });
    dropTarget = Model.dropTarget(columns, widths, itemGap, dragColumn.address,
      dragX - endSpace - contentInset + scrollOffset);
  }

  function finishDrag() {
    if (!dragging) return;
    var source = dragColumn.address, target = dropTarget;
    var workspace = dragWorkspace, monitor = dragMonitor;
    cancelDrag();
    if (target && target.changed) {
      runAction([helper, "reorder", source, "--target", target.address, "--side", target.side,
        "--workspace", String(workspace), "--monitor", monitor]);
    }
    else drainSnapshot();
  }

  function cancelDrag() {
    dragging = false;
    dropTarget = null;
    scrollDirection = 0;
    hoverArmed = false;
  }

  function drainSnapshot() {
    var pending = deferredSnapshot;
    deferredSnapshot = null;
    if (pending) applySnapshot(pending);
    else requestRefresh();
  }

  function beginResize() {
    if (dragging || operationBusy) return;
    close();
    glide.stop();
    scrollDirection = 0;
    resizeWidth = stripWidth;
    resizeCenter = strip.mapToItem(root, strip.width / 2, 0).x;
    resizing = true;
  }

  function updateResize(point) {
    if (resizing) resizeWidth = Math.max(minimumWidth, Math.min(capacity, Math.abs(point.x - resizeCenter) * 2));
  }

  function finishResize(save) {
    if (!resizing) return;
    var ratio = geometryGap > 0 ? resizeWidth / geometryGap : 0.85;
    if (save) persistSetting("widthRatio", Model.widthRatio(ratio));
    resizing = false;
    hoverArmed = false;
    Qt.callLater(function() { measureGap(); drainSnapshot(); });
  }

  function focusedExtent() {
    var start = 0;
    for (var i = 0; i < columns.length; i++) {
      var width = tileWidth(columns[i]);
      if (columns[i].focused) return {start: start, width: width};
      start += width + itemGap;
    }
    return null;
  }
  function reconcileOffset() {
    var current = Model.clampOffset(scrollOffset, naturalWidth, viewportWidth);
    var goal = Model.clampOffset(scrollGoal, naturalWidth, viewportWidth);
    if (glide.running) {
      if (Math.abs(current - scrollOffset) > 0.01 || Math.abs(goal - scrollGoal) > 0.01)
        setOffset(goal, true);
    } else if (Math.abs(current - scrollOffset) > 0.01) setOffset(current, false);
  }
  function viewportChanged() {
    var focused = focusedExtent();
    if (!viewportUpdatePending) {
      preserveVisibleFocus = !!focused && previousViewportWidth > 0 &&
        focused.start < scrollOffset + previousViewportWidth && focused.start + focused.width > scrollOffset;
      viewportUpdatePending = true;
    }
    previousViewportWidth = viewportWidth;
    Qt.callLater(function() {
      viewportUpdatePending = false;
      var focusedNow = focusedExtent();
      if (preserveVisibleFocus && focusedNow && !dragging)
        setOffset(Model.revealOffset(scrollOffset, viewportWidth, focusedNow.start, focusedNow.width, naturalWidth), false);
      else reconcileOffset();
    });
  }
  function stopGlide() { glide.stop(); }
  function revealFocused() {
    if (dragging || resizing || operationBusy) return;
    var start = 0;
    for (var i = 0; i < columns.length; i++) {
      var width = tileWidth(columns[i]);
      if (columns[i].focused) {
        setOffset(Model.revealOffset(scrollOffset, viewportWidth, start, width, naturalWidth), false);
        return;
      }
      start += width + itemGap;
    }
  }

  function setOffset(value, animate) {
    var next = Model.clampOffset(value, naturalWidth, viewportWidth);
    scrollGoal = next;
    glide.stop();
    if (animate) { glide.to = next; glide.start(); }
    else scrollOffset = next;
  }

  function wheel(event) {
    if (resizing) { event.accepted = true; return; }
    if (!overflow) { event.accepted = true; return; }
    var delta = Model.wheelStep(event.pixelDelta.x, event.pixelDelta.y,
      event.angleDelta.x, event.angleDelta.y, event.inverted,
      !event.pixelDelta.x && !event.pixelDelta.y, iconSize * 3);
    if (delta) setOffset((glide.running ? scrollGoal : scrollOffset) + delta,
      !event.pixelDelta.x && !event.pixelDelta.y);
    event.accepted = true;
  }

  function openMenu(anchor) {
    if (dragging || resizing) return;
    scrollDirection = 0;
    hoverArmed = false;
    menuKind = "general";
    menuAnchor = anchor;
    menuCursor = arrowMode === "hover" ? 0 : 1;
    menuOpen = true;
  }

  function openAppMenu(anchor, column) {
    if (dragging || resizing) return;
    scrollDirection = 0;
    hoverArmed = false;
    menuAddress = column.address;
    menuWorkspace = snapshot.workspaceId;
    menuMonitor = monitorName;
    menuKind = "app";
    menuAnchor = anchor;
    menuCursor = 0;
    menuOpen = true;
  }

  function close() { menuOpen = false; }
  function closeForPopoutSwitch() { close(); }

  function persistSetting(settingName, value) {
    var entry = {id: moduleName};
    for (var existingKey in settings) if (existingKey !== "id") entry[existingKey] = settings[existingKey];
    entry[settingName] = value;
    close();
    var result = HostAdapter.persistSetting(bar, moduleName, entry);
    if (result.ok) { settings = entry; actionError = ""; }
    else actionError = result.error;
  }

  function chooseMode(mode) {
    if (mode === "hover" || mode === "click") persistSetting("arrowMode", mode);
  }
  function chooseIndication(mode) {
    if (mode === "underlines" || mode === "tiles") persistSetting("indicationMode", mode);
  }
  function buildMenuItems() {
    if (menuKind === "app") return [{label: "Close", action: "close"}];
    if (menuKind === "regions") return [
      {label: "‹ Back", action: "back"},
      {label: "Left", action: "region", value: "left"},
      {label: "Center", action: "region", value: "center"},
      {label: "Right", action: "region", value: "right"}];
    if (menuKind === "positions") return placementChoices;
    return [
      {label: "Scroll on hover", action: "arrow", value: "hover", header: "Arrow scrolling", checked: arrowMode === "hover"},
      {label: "Scroll on click", action: "arrow", value: "click", checked: arrowMode === "click"},
      {label: "Underlines", action: "appearance", value: "underlines", header: "Appearance", checked: indicationMode === "underlines"},
      {label: "Tiles", action: "appearance", value: "tiles", checked: indicationMode === "tiles"},
      {label: "Reset width", action: "reset", header: "Widget"},
      {label: "Move widget…", action: "move"}];
  }
  function chooseMenuItem(index) {
    var item = menuItems[index];
    if (!item) return;
    if (item.action === "close") closeColumn();
    else if (item.action === "arrow") chooseMode(item.value);
    else if (item.action === "appearance") chooseIndication(item.value);
    else if (item.action === "reset") persistSetting("widthRatio", 0.85);
    else if (item.action === "move") { menuKind = "regions"; menuCursor = 0; }
    else if (item.action === "back") { menuKind = "general"; menuCursor = 5; }
    else if (item.action === "regions") { menuKind = "regions"; menuCursor = 0; }
    else if (item.action === "region") {
      placementRegion = item.value;
      placementChoices = HostAdapter.moveChoices(bar, moduleName, placementRegion);
      menuKind = "positions";
      menuCursor = 0;
    }
    else if (item.action === "place") {
      close();
      var result = HostAdapter.moveWidget(root, bar, surface, placementRegion, item.value);
      if (!result.ok) actionError = result.error;
    }
  }
  function menuItemChecked(index) { return !!(menuItems[index] && menuItems[index].checked); }

  function showTooltip(item, text) {
    if (bar && typeof bar.showTooltip === "function") bar.showTooltip(item, text);
  }
  function hideTooltip(item) {
    if (bar && typeof bar.hideTooltip === "function") bar.hideTooltip(item);
  }
  function appIcon(column) {
    var service = HostAdapter.service(bar, moduleName);
    var resolver = service && service.iconResolver ? service.iconResolver : fallbackIcons.item;
    return resolver ? resolver.iconFor(String(column.class || ""), HostAdapter.appLibrary(bar)) : "";
  }

  function debugState() {
    return JSON.stringify({gap: geometryGap, width: stripWidth, viewport: viewportWidth,
      naturalWidth: naturalWidth, offset: scrollOffset, overflow: overflow, mode: arrowMode, indicationMode: indicationMode,
      menuOpen: menuOpen, menuKind: menuKind, dragging: dragging, resizing: resizing,
      allocation: placement, protectedRegion: protectedRegion(), widthRatio: setting("widthRatio", 0.85), canReorder: canReorder, actionError: actionError, queryError: queryError, stale: backendStale, busy: operationBusy, monitorName: monitorName, workspaceId: snapshot.workspaceId || 0, backendProtocolVersion: snapshot.protocolVersion || 0, nativeProtocolVersion: snapshot.nativeProtocolVersion || 0, nativeCapabilities: snapshot.capabilities || {}, capabilities: hostCapabilities, lastCommand: lastCommand, columns: columns});
  }

  Component.onCompleted: { measureGap(); syncBackend(); requestRefresh(); }
  Component.onDestruction: if (registeredBackend) registeredBackend.unregisterWidget(root)
  onBackendServiceChanged: Qt.callLater(syncBackend)
  onBackendEnabledChanged: Qt.callLater(syncBackend)
  onVisibleChanged: { Qt.callLater(syncBackend); requestRefresh(); }
  onBarHiddenChanged: { refreshRegion(); requestRefresh(); }
  onMeasuredInputChanged: Qt.callLater(measureGap)
  onDraggingChanged: if (!dragging) Qt.callLater(measureGap)
  onMonitorNameChanged: { actionBusy = false; pendingFocus = null; refreshRegion(); cancelDrag(); finishResize(false); close(); stateEpoch++; requestRefresh(); }
  onBarChanged: Qt.callLater(measureGap)
  onViewportWidthChanged: viewportChanged()
  onStripWidthChanged: Qt.callLater(refreshRegion)
  onScrollOffsetChanged: updateDropTarget()
  onIndicationModeChanged: Qt.callLater(revealFocused)


  TransformWatcher {
    a: root.surface ? root.surface.contentItem : null
    b: strip
    onTransformChanged: Qt.callLater(root.refreshRegion)
  }

  NumberAnimation { id: glide; target: root; property: "scrollOffset"; duration: 140; easing.type: Easing.OutCubic }
  Timer {
    interval: 16
    running: (root.dragging || root.scrollDirection !== 0) && root.overflow && !root.menuOpen && !root.resizing
    repeat: true
    onRunningChanged: root.lastFrame = Date.now()
    onTriggered: {
      var now = Date.now();
      var delta = Math.min(50, now - root.lastFrame) / 1000;
      root.lastFrame = now;
      var direction = root.scrollDirection;
      if (root.dragging) direction = root.dragY < 0 || root.dragY > root.barSize ? 0
        : root.dragX < root.endSpace + root.iconSize ? -1
        : root.dragX > root.stripWidth - root.endSpace - root.iconSize ? 1 : 0;
      if (direction) root.setOffset(root.scrollOffset + direction * Style.space(190) * delta, false);
    }
  }

  Item {
    id: strip
    objectName: "layoutStrip"
    anchors.centerIn: parent
    anchors.alignWhenCentered: false
    width: root.stripWidth
    height: root.barSize
    clip: true
    visible: width > 0
    HoverHandler { id: stripHover }
    readonly property bool tooltipHovered: stripHover.hovered
    function triggerPress(button) { if (button === Qt.RightButton) root.openMenu(strip); }
    // Padding and empty workspaces retain a menu target, including while a
    // different popup forwards clicks back to the bar.
    property var registeredBar: null
    readonly property var hostBar: root.bar
    function syncRegistration() {
      if (registeredBar) HostAdapter.unregisterClickTarget(registeredBar, strip);
      registeredBar = hostBar;
      if (registeredBar && visible) HostAdapter.registerClickTarget(registeredBar, strip);
      Qt.callLater(function() {
        // Host forwarding chooses the most recently registered hit target.
        // The broad padding target must remain below apps and endcaps.
        for (var i = 0; i < tileRepeater.count; i++) {
          var tile = tileRepeater.itemAt(i);
          if (tile) tile.syncRegistration();
        }
        leftArrow.syncRegistration();
        rightArrow.syncRegistration();
      });
    }
    onHostBarChanged: syncRegistration()
    onVisibleChanged: syncRegistration()
    Component.onCompleted: syncRegistration()
    Component.onDestruction: if (registeredBar) HostAdapter.unregisterClickTarget(registeredBar, strip)

    MouseArea {
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(event) { if (event.button === Qt.RightButton) root.openMenu(strip); }
      onWheel: function(event) { root.wheel(event); }
    }

    StripArrow {
      controller: root
      id: leftArrow
      visible: root.arrowsShown
      direction: -1
      available: root.scrollOffset > 0.5
      anchors.left: parent.left
      anchors.leftMargin: root.edgeWidth
    }
    Item {
      id: viewport
      x: root.endSpace
      width: root.viewportWidth
      height: parent.height
      clip: true

      Row {
        x: root.contentInset - root.scrollOffset
        height: parent.height
        spacing: root.itemGap
        Repeater {
          id: tileRepeater
          model: columnModel
          StripTile {
            controller: root
            strip: root.stripItem
            viewport: root.viewportItem
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.NoButton
        onWheel: function(event) { root.wheel(event); }
      }
    }
    StripArrow {
      controller: root
      id: rightArrow
      visible: root.arrowsShown
      direction: 1
      available: root.scrollOffset < root.maximumOffset - 0.5
      anchors.right: parent.right
      anchors.rightMargin: root.edgeWidth
    }
    Rectangle {
      objectName: "dropMarker"
      visible: root.dragging && root.dropTarget !== null
      x: root.dropTarget ? Math.max(root.endSpace, Math.min(root.stripWidth - root.endSpace,
        root.endSpace + root.contentInset + root.dropTarget.position - root.scrollOffset)) - width / 2 : 0
      y: Style.space(3)
      width: Style.space(2)
      height: parent.height - Style.space(6)
      color: Color.accent
      z: 5
    }
    BorderSurface {
      objectName: "dragGhost"
      visible: root.dragging
      x: Math.max(0, Math.min(parent.width - width, root.dragX - width / 2))
      width: root.dragColumn ? root.tileWidth(root.dragColumn) - Style.space(2) : 0
      height: parent.height - Style.space(2)
      y: Style.space(1)
      radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(4)) : 0
      color: Style.selectedFillFor(root.foreground, Color.accent)
      borderSpec: Border.controlSpec("selected", root.foreground, Color.accent)
      opacity: root.dropTarget ? 0.9 : 0.45
      z: 6
      Image {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: root.dragColumn ? root.appIcon(root.dragColumn) : ""
        fillMode: Image.PreserveAspectFit
      }
    }
    StripResizeEdge { controller: root; objectName: "leftResizeEdge"; anchors.left: parent.left }
    StripResizeEdge { controller: root; objectName: "rightResizeEdge"; anchors.right: parent.right }
  }



  Text {
    id: statusBadge
    objectName: "layoutStatus"
    readonly property bool tooltipHovered: statusHit.containsMouse
    visible: !!root.statusMessage
    text: root.operationBusy ? "…" : "!"
    color: root.operationBusy ? root.foreground : Color.accent
    font.pixelSize: Style.font.caption
    font.bold: true
    x: Math.min(root.width - width, strip.x + strip.width + Style.space(2))
    anchors.verticalCenter: parent.verticalCenter
    Accessible.name: root.statusMessage
    MouseArea {
      id: statusHit
      anchors.fill: parent
      hoverEnabled: true
      onEntered: if (root.bar) root.showTooltip(statusBadge, root.statusMessage)
      onExited: if (root.bar) root.hideTooltip(statusBadge)
      onClicked: if (!root.operationBusy) root.requestRefresh()
    }
  }
  StripMenu { controller: root }

}
