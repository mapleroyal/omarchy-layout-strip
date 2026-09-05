import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.mapleroyal.layout-strip"

  property var snapshot: ({columns: []})
  property bool backendEnabled: true
  property bool refreshPending: false
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
  property int scrollDirection: 0
  property double lastFrame: 0

  readonly property var columns: snapshot.columns || []
  readonly property var surface: root.QsWindow.window
  readonly property string monitorName: surface && surface.screen ? surface.screen.name : ""
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("backend/transport.py").toString().replace(/^file:\/\//, ""))
  readonly property string arrowMode: setting("arrowMode", "hover") === "click" ? "click" : "hover"
  readonly property string indicationMode: setting("indicationMode", "underlines") === "tiles" ? "tiles" : "underlines"
  readonly property real iconSize: Style.bar.iconCanvas
  readonly property real itemPadding: Style.space(6)
  readonly property real itemGap: Style.space(4)
  readonly property real arrowSize: Style.bar.statusSlot
  readonly property real naturalWidth: {
    var total = 0;
    for (var i = 0; i < columns.length; i++) total += tileWidth(columns[i]);
    return total + Math.max(0, columns.length - 1) * itemGap;
  }
  readonly property real capacity: Math.max(0, geometryGap * 0.85)
  readonly property bool overflow: naturalWidth > capacity + 0.5
  readonly property real stripWidth: Math.min(naturalWidth + (overflow ? arrowSize * 2 : 0), capacity)
  readonly property real viewportWidth: Math.max(0, stripWidth - (overflow ? arrowSize * 2 : 0))
  readonly property real maximumOffset: Math.max(0, naturalWidth - viewportWidth)
  readonly property color foreground: bar ? bar.barForeground : Color.foreground

  visible: !vertical
  implicitWidth: visible ? geometryGap : 0
  implicitHeight: barSize

  // This widget occupies a measured inter-section gap and cannot be reordered.
  // Keep its input above the host's module-drag MouseArea so holds and wheel
  // gestures reach the strip. The Loader remains in its normal layout slot.
  Binding { target: root.parent; property: "z"; value: 1; when: root.parent !== null }

  function tileWidth(column) {
    var factor = Model.sizeFactor(column.size);
    // Include the inset outside the scaled visual width so painted tiles have
    // exactly 1:1.5:2 widths, rather than scaling only their inner icon area.
    return indicationMode === "tiles"
      ? (iconSize + itemPadding * 2) * factor + Style.space(2)
      : iconSize * factor + itemPadding * 2;
  }

  function measureGap() {
    if (!bar || !surface || !bar.moduleSlots) { geometryGap = 0; return; }
    var left = 0;
    var center = surface.width / 2;
    var foundCenter = false;
    for (var i = 0; i < bar.moduleSlots.length; i++) {
      var slot = bar.moduleSlots[i];
      if (!slot || slot.moduleName === moduleName || !slot.activeItem ||
          !bar.targetBelongsToWindow(slot.activeItem, surface)) continue;
      if (!slot.visible || !slot.activeItem.visible || slot.width <= 0) continue;
      var p = slot.mapToItem(null, 0, 0);
      if (slot.region === "left") left = Math.max(left, p.x + slot.width);
      if (slot.region === "center") {
        center = foundCenter ? Math.min(center, p.x) : p.x;
        foundCenter = true;
      }
    }
    // The widget must be last in the left section. Center widgets retain
    // their existing anchor; the strip only consumes the gap before them.
    geometryGap = Math.max(0, center - left);
  }

  function requestRefresh() {
    if (!backendEnabled || !monitorName) return;
    if (query.running) { refreshPending = true; return; }
    refreshPending = false;
    query.command = ["python3", helper, "snapshot", "--monitor", monitorName];
    query.running = true;
  }

  function applySnapshot(data) {
    if (!data || !Array.isArray(data.columns)) return;
    var signature = JSON.stringify(data);
    if (signature === lastSnapshot) return;
    var changedWorkspace = data.workspaceId !== lastWorkspace;
    var changedFocus = data.activeAddress !== lastFocused;
    snapshot = data;
    lastSnapshot = signature;
    lastWorkspace = data.workspaceId || 0;
    lastFocused = data.activeAddress || "";
    Qt.callLater(function() {
      if (changedWorkspace) setOffset(0, false);
      if (changedWorkspace || changedFocus) revealFocused();
      else setOffset(scrollOffset, false);
    });
  }

  function focusColumn(column) {
    if (!backendEnabled || navigation.running || !column || !/^0x[0-9a-f]+$/i.test(column.address)) return;
    close();
    navigation.command = ["python3", helper, "focus", column.address, "--workspace", String(snapshot.workspaceId), "--monitor", monitorName];
    navigation.running = true;
  }

  function revealFocused() {
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
    if (!overflow) { event.accepted = true; return; }
    var delta = Model.wheelStep(event.pixelDelta.x, event.pixelDelta.y,
      event.angleDelta.x, event.angleDelta.y, event.inverted,
      !event.pixelDelta.x && !event.pixelDelta.y, iconSize * 3);
    if (delta) setOffset((glide.running ? scrollGoal : scrollOffset) + delta,
      !event.pixelDelta.x && !event.pixelDelta.y);
    event.accepted = true;
  }

  function openMenu(anchor) {
    scrollDirection = 0;
    hoverArmed = false;
    menuAnchor = anchor;
    menuCursor = arrowMode === "hover" ? 0 : 1;
    menuOpen = true;
  }
  function close() { menuOpen = false; }
  function closeForPopoutSwitch() { close(); }

  function persistSetting(settingName, value) {
    var entry = {id: moduleName};
    for (var existingKey in settings) if (existingKey !== "id") entry[existingKey] = settings[existingKey];
    entry[settingName] = value;
    settings = entry;
    close();
    if (bar && bar.shell && bar.shell.updateEntryInline)
      bar.shell.updateEntryInline(moduleName, entry);
  }

  function chooseMode(mode) {
    if (mode === "hover" || mode === "click") persistSetting("arrowMode", mode);
  }
  function chooseIndication(mode) {
    if (mode === "underlines" || mode === "tiles") persistSetting("indicationMode", mode);
  }
  function chooseMenuItem(index) {
    if (index < 2) chooseMode(index === 0 ? "hover" : "click");
    else chooseIndication(index === 2 ? "underlines" : "tiles");
  }
  function menuItemChecked(index) {
    return index < 2 ? (arrowMode === "hover") === (index === 0)
      : (indicationMode === "underlines") === (index === 2);
  }

  function appIcon(column) {
    var entries = DesktopEntries.applications.values;
    var klass = String(column.class || "");
    var entry = DesktopEntries.heuristicLookup(klass);
    var icon = entry ? entry.icon : klass;
    var library = bar && bar.shell ? bar.shell.appLibrary : null;
    return library ? library.iconSource(icon) : (Quickshell.iconPath(icon, true) || Quickshell.iconPath("application-x-executable", true));
  }

  function debugState() {
    return JSON.stringify({gap: geometryGap, width: stripWidth, viewport: viewportWidth,
      naturalWidth: naturalWidth, offset: scrollOffset, overflow: overflow, mode: arrowMode, indicationMode: indicationMode,
      menuOpen: menuOpen, backendError: snapshot.error || "", nativeBridge: snapshot.available === true,
      workspaceId: snapshot.workspaceId || 0, monitor: monitorName, columns: columns});
  }

  Component.onCompleted: { measureGap(); requestRefresh(); }
  onMonitorNameChanged: requestRefresh()
  onBarChanged: Qt.callLater(measureGap)
  onViewportWidthChanged: Qt.callLater(function() { setOffset(scrollOffset, false); revealFocused(); })
  onIndicationModeChanged: Qt.callLater(revealFocused)

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (/^(activewindow|openwindow|closewindow|movewindow|workspace|focusedmon|monitor|activespecial|fullscreen|changefloatingmode|configreloaded|windowtitle|togglegroup|moveintogroup|moveoutofgroup|custom)/.test(event.name))
        refreshSoon.restart();
    }
  }
  Timer { id: refreshSoon; interval: 45; onTriggered: root.requestRefresh() }
  // Column resizing/reordering has no comprehensive IPC event. This fallback
  // also recovers from compositor/config reloads without a resident daemon.
  Timer { interval: 1000; running: root.backendEnabled; repeat: true; onTriggered: root.requestRefresh() }
  Timer { interval: 250; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.measureGap() }
  Process {
    id: query
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.applySnapshot(JSON.parse(text)); }
        catch (e) { /* A compositor restart may interrupt a reply. Retry on the next tick. */ }
      }
    }
    onExited: if (root.refreshPending) Qt.callLater(root.requestRefresh)
  }
  Process { id: navigation; onExited: refreshSoon.restart() }
  NumberAnimation { id: glide; target: root; property: "scrollOffset"; duration: 140; easing.type: Easing.OutCubic }
  Timer {
    interval: 16
    running: root.scrollDirection !== 0 && root.overflow && !root.menuOpen
    repeat: true
    onRunningChanged: root.lastFrame = Date.now()
    onTriggered: {
      var now = Date.now();
      var delta = Math.min(50, now - root.lastFrame) / 1000;
      root.lastFrame = now;
      root.setOffset(root.scrollOffset + root.scrollDirection * Style.space(190) * delta, false);
    }
  }
  IpcHandler {
    target: "io.github.mapleroyal.layout-strip"
    function refresh(): void { root.broadcast("requestRefresh"); }
    function debug(): string { return root.debugState(); }
  }

  Item {
    id: strip
    anchors.centerIn: parent
    width: root.stripWidth
    height: root.barSize
    visible: root.columns.length > 0 && width > root.iconSize + (root.overflow ? root.arrowSize * 2 : 0)

    MouseArea {
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.RightButton
      onClicked: root.openMenu(strip)
      onWheel: function(event) { root.wheel(event); }
    }

    Arrow {
      id: leftArrow
      visible: root.overflow
      direction: -1
      available: root.scrollOffset > 0.5
      anchors.left: parent.left
    }
    Item {
      id: viewport
      x: root.overflow ? root.arrowSize : 0
      width: root.viewportWidth
      height: parent.height
      clip: true

      Row {
        x: -root.scrollOffset
        height: parent.height
        spacing: root.itemGap
        Repeater {
          model: root.columns
          Item {
            id: tile
            objectName: "layoutTile"
            required property var modelData
            width: root.tileWidth(modelData)
            height: root.barSize
            readonly property bool focused: modelData.focused === true
            readonly property bool tooltipHovered: hit.containsMouse
            // Register only completely visible tiles: bar popout forwarding
            // otherwise hits clipped icons underneath arrows or neighbours.
            readonly property bool interactive: x >= root.scrollOffset - 0.5 &&
              x + width <= root.scrollOffset + root.viewportWidth + 0.5
            property var registeredBar: null
            readonly property var hostBar: root.bar
            function syncRegistration() {
              if (registeredBar) registeredBar.unregisterClickTarget(tile);
              registeredBar = hostBar;
              if (registeredBar && interactive) registeredBar.registerClickTarget(tile);
            }
            function triggerPress(button) {
              if (button === Qt.LeftButton) root.focusColumn(modelData);
              else if (button === Qt.RightButton) root.openMenu(tile);
            }
            onHostBarChanged: syncRegistration()
            onInteractiveChanged: syncRegistration()
            Component.onCompleted: syncRegistration()
            Component.onDestruction: if (registeredBar) registeredBar.unregisterClickTarget(tile)

            BorderSurface {
              objectName: "tileSurface"
              anchors.fill: parent
              anchors.margins: Style.space(1)
              // Follow the appearance plugin's rounded/square switch, keeping
              // tile corners modest so wide columns remain rounded rectangles.
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(4)) : 0
              readonly property real strongAlpha: Math.min(0.65, Math.max(0.3, Style.selectedFillAlpha * 1.5))
              color: root.indicationMode === "tiles"
                ? Util.alpha(Style.selectedStateColor(root.foreground, Color.accent), tile.focused ? strongAlpha : strongAlpha * 0.25)
                : (tile.focused ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent")
              borderSpec: tile.focused ? Border.controlSpec("selected", root.foreground, Color.accent) : Border.none()
              Behavior on color { ColorAnimation { duration: 120 } }
            }
            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              y: Math.round((parent.height - height) / 2) - (root.indicationMode === "underlines" ? Style.space(1) : 0)
              width: root.iconSize
              height: root.iconSize
              source: root.appIcon(tile.modelData)
              sourceSize.width: Math.round(width * Screen.devicePixelRatio)
              sourceSize.height: Math.round(height * Screen.devicePixelRatio)
              fillMode: Image.PreserveAspectFit
            }
            Rectangle {
              objectName: "widthUnderline"
              visible: root.indicationMode === "underlines"
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.iconSize * Model.sizeFactor(tile.modelData.size)
              height: Style.space(2)
              y: parent.height - height - Style.space(2)
              radius: Style.cornerRadius > 0 ? Math.min(width, height) / 2 : 0
              color: Color.accent
              opacity: 0.9
            }
            MouseArea {
              id: hit
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(event) { tile.triggerPress(event.button); }
              onEntered: if (root.bar) root.bar.showTooltip(tile, String(tile.modelData.title || tile.modelData.class))
              onExited: if (root.bar) root.bar.hideTooltip(tile)
              onWheel: function(event) { root.wheel(event); }
            }
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
    Arrow {
      id: rightArrow
      visible: root.overflow
      direction: 1
      available: root.scrollOffset < root.maximumOffset - 0.5
      anchors.right: parent.right
    }
  }

  component Arrow: Item {
    id: arrow
    objectName: direction < 0 ? "leftArrow" : "rightArrow"
    required property int direction
    required property bool available
    width: root.arrowSize
    height: root.barSize
    readonly property bool tooltipHovered: mouse.containsMouse
    readonly property bool wantsScroll: visible && available && !root.menuOpen &&
      (root.arrowMode === "hover" ? mouse.containsMouse && root.hoverArmed : mouse.pressed && (mouse.pressedButtons & Qt.LeftButton))
    onWantsScrollChanged: {
      if (wantsScroll) { glide.stop(); root.scrollDirection = direction; }
      else if (root.scrollDirection === direction) root.scrollDirection = 0;
    }
    function triggerPress(button) {
      if (button === Qt.RightButton) root.openMenu(arrow);
      else if (button === Qt.LeftButton && root.arrowMode === "click" && available)
        root.setOffset(root.scrollOffset + direction * root.iconSize * 3, true);
    }
    property var registeredBar: null
    readonly property var hostBar: root.bar
    function syncRegistration() {
      if (registeredBar) registeredBar.unregisterClickTarget(arrow);
      registeredBar = hostBar;
      if (registeredBar && visible) registeredBar.registerClickTarget(arrow);
    }
    onHostBarChanged: syncRegistration()
    onVisibleChanged: syncRegistration()
    Component.onCompleted: syncRegistration()
    Component.onDestruction: {
      if (registeredBar) registeredBar.unregisterClickTarget(arrow);
      if (root.scrollDirection === direction) root.scrollDirection = 0;
    }
    OpticalGlyph {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      text: arrow.direction < 0 ? "\uf104" : "\uf105"
      color: root.foreground
      opacity: arrow.available ? 0.85 : 0.25
      fontSize: Style.bar.iconFont
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      property double pressedAt: 0
      onEntered: {
        root.hoverArmed = true;
        if (root.bar) root.bar.showTooltip(arrow, (arrow.direction < 0 ? "Scroll left" : "Scroll right") + " · Right-click for mode");
      }
      onExited: if (root.bar) root.bar.hideTooltip(arrow)
      onPressed: function(event) {
        pressedAt = Date.now();
        if (event.button === Qt.RightButton) { root.scrollDirection = 0; root.openMenu(arrow); }
      }
      onClicked: function(event) {
        // A tap advances one icon; holding continuously scrolls until release.
        if (event.button === Qt.LeftButton && Date.now() - pressedAt < 180) arrow.triggerPress(event.button);
      }
      onWheel: function(event) { root.wheel(event); }
    }
  }

  KeyboardPanel {
    id: menuPanel
    anchorItem: root.menuAnchor || strip
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menuPanel.fittedContentWidth(Style.space(235))
    contentHeight: menuPanel.fittedContentHeight(modeColumn.implicitHeight)
    focusTarget: modeKeys
    PanelKeyCatcher {
      id: modeKeys
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dx || dy) root.menuCursor = (root.menuCursor + (dy || dx) + 4) % 4; }
      onTabRequested: function(direction) { root.menuCursor = (root.menuCursor + direction + 4) % 4; }
      onActivateRequested: root.chooseMenuItem(root.menuCursor)
      Column {
        id: modeColumn
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: ["Scroll on hover", "Scroll on click", "Underlines", "Tiles"]
          Column {
            id: option
            required property string modelData
            required property int index
            width: parent.width
            spacing: Style.space(4)
            Text {
              visible: option.index === 0 || option.index === 2
              leftPadding: Style.space(8)
              topPadding: option.index === 2 ? Style.space(6) : 0
              text: option.index === 0 ? "Arrow scrolling" : "Appearance"
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            BorderSurface {
              width: parent.width
              height: Style.space(32)
              radius: Style.cornerRadius
              color: root.menuCursor === option.index ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                text: (root.menuItemChecked(option.index) ? "●  " : "○  ") + option.modelData
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.menuCursor = option.index
                onClicked: root.chooseMenuItem(option.index)
              }
            }
          }
        }
      }
    }
  }
}
