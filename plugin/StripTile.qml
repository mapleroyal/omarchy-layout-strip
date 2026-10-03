import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "HostAdapter.js" as HostAdapter

Item {
  id: tile
  required property var controller
  required property Item strip
  required property Item viewport
  objectName: "layoutTile"
  required property string columnJson
  // Preserve nested members as plain immutable JS values: ListModel otherwise
  // converts arrays/objects to nested roles that can change under a pointer grab.
  readonly property var modelData: JSON.parse(columnJson)
  readonly property int memberCount: Model.members(modelData).length
  readonly property real badgeWidth: controller.stackBadgeWidth(modelData)
  readonly property string tooltipText: String(modelData.title || modelData.class)
    + (memberCount > 1 ? " · " + memberCount + " windows in this column" : "")
    + (modelData.floating ? " · Floating" : "")
    + (controller.statusMessage ? " · " + controller.statusMessage : "")
  width: controller.tileWidth(modelData)
  height: controller.barSize
  readonly property bool focused: modelData.focused === true
  opacity: controller.dragging && Model.columnKey(controller.dragColumn) === Model.columnKey(modelData) ? 0.25 : 1
  readonly property bool tooltipHovered: hit.containsMouse
  readonly property bool interactive: forwardedHit.width > 0
  Item {
    id: forwardedHit
    objectName: "layoutTileTarget"
    parent: viewport
    property var tileItem: tile
    readonly property bool interactive: width > 0
    x: Math.max(0, tile.x + controller.contentInset - controller.scrollOffset)
    width: Math.max(0, Math.min(viewport.width, tile.x + controller.contentInset - controller.scrollOffset + tile.width) - x)
    height: tile.height
    function triggerPress(button) {
      tile.triggerPress(button);
    }
  }
  Item {
    id: forwardedBadge
    objectName: "layoutStackTarget"
    parent: viewport
    property var tileItem: tile
    readonly property bool interactive: tile.memberCount > 1 && width > 0
    readonly property real start: tile.x + controller.contentInset - controller.scrollOffset + badge.x
    x: Math.max(0, start)
    width: tile.memberCount > 1 ? Math.max(0, Math.min(viewport.width, start + badge.width) - x) : 0
    height: tile.height
    function triggerPress(button) { tile.triggerBadgePress(button); }
    onInteractiveChanged: {
      if (!interactive && controller.menuAnchor === forwardedBadge) controller.close();
      tile.syncRegistration();
    }
  }
  property var registeredBar: null
  readonly property var hostBar: controller.bar
  function syncRegistration() {
    if (registeredBar) {
      HostAdapter.unregisterClickTarget(registeredBar, forwardedHit);
      HostAdapter.unregisterClickTarget(registeredBar, forwardedBadge);
    }
    registeredBar = hostBar;
    if (registeredBar && interactive)
      HostAdapter.registerClickTarget(registeredBar, forwardedHit);
    // Popup forwarding picks the last registered matching target.
    if (registeredBar && forwardedBadge.interactive)
      HostAdapter.registerClickTarget(registeredBar, forwardedBadge);
  }
  function triggerPress(button, column) {
    column = column || modelData;
    if (button === Qt.LeftButton)
      controller.focusColumn(column);
    else if (button === Qt.MiddleButton)
      controller.closeColumn(column);
    else if (button === Qt.RightButton)
      controller.cycleColumnWidth(column);
  }
  function triggerBadgePress(button) {
    if (button === Qt.LeftButton) {
      controller.hideTooltip(tile);
      controller.openStack(forwardedBadge, modelData);
    } else triggerPress(button);
  }
  onModelDataChanged: {
    if (hit.containsMouse && !controller.dragging)
      controller.showTooltip(tile, tooltipText);
  }
  onHostBarChanged: syncRegistration()
  onInteractiveChanged: syncRegistration()
  Component.onCompleted: syncRegistration()
  Component.onDestruction: if (registeredBar) {
    HostAdapter.unregisterClickTarget(registeredBar, forwardedHit);
    HostAdapter.unregisterClickTarget(registeredBar, forwardedBadge);
  }

  BorderSurface {
    objectName: "tileSurface"
    anchors.fill: parent
    anchors.margins: Style.space(1)
    // Follow the appearance plugin's rounded/square switch, keeping
    // tile corners modest so wide columns remain rounded rectangles.
    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(4)) : 0
    readonly property real strongAlpha: Math.min(0.65, Math.max(0.3, Style.selectedFillAlpha * 1.5))
    color: controller.indicationMode === "tiles" ? Util.alpha(Style.selectedStateColor(controller.foreground, Color.accent), tile.focused ? strongAlpha : strongAlpha * 0.25) : (tile.focused ? Style.selectedFillFor(controller.foreground, Color.accent) : "transparent")
    borderSpec: tile.focused ? Border.controlSpec("selected", controller.foreground, Color.accent) : Border.none()
    Behavior on color {
      ColorAnimation {
        duration: 120
      }
    }
  }
  Image {
    id: appImage
    x: (parent.width - tile.badgeWidth - width) / 2
    y: Math.round((parent.height - height) / 2) - (controller.indicationMode === "underlines" ? Style.space(1) : 0)
    width: controller.iconSize
    height: controller.iconSize
    source: controller.appIcon(tile.modelData)
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
  }
  Item {
    id: badge
    objectName: "stackBadge"
    visible: tile.memberCount > 1
    x: parent.width - tile.badgeWidth
    width: tile.badgeWidth
    height: parent.height
    Accessible.name: tile.memberCount + " windows in this column; show windows"
    Accessible.role: Accessible.Button
    Accessible.onPressAction: tile.triggerBadgePress(Qt.LeftButton)
    Row {
      anchors.centerIn: parent
      spacing: Style.space(2)
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Repeater {
          model: 2
          Rectangle {
            width: Style.space(4)
            height: Style.space(4)
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: controller.foreground
          }
        }
      }
      Text {
        text: tile.memberCount > 9 ? "9+" : String(tile.memberCount)
        color: controller.foreground
        font.family: Style.font.family
        font.pixelSize: Style.space(10)
        font.bold: true
      }
    }
  }
  Rectangle {
    objectName: "floatingMarker"
    visible: tile.modelData.floating === true
    x: appImage.x + appImage.width - width / 2
    y: Style.space(2)
    width: Style.space(7)
    height: Style.space(6)
    color: Color.bar.background
    border.color: controller.foreground
    border.width: Math.max(1, Style.space(1))
    Accessible.name: "Floating window"
  }
  Rectangle {
    objectName: "widthUnderline"
    visible: controller.indicationMode === "underlines"
    anchors.horizontalCenter: parent.horizontalCenter
    width: controller.iconSize * Model.sizeFactor(tile.modelData.size)
    height: Style.space(2)
    y: parent.height - height - Style.space(2)
    radius: Style.cornerRadius > 0 ? Math.min(width, height) / 2 : 0
    color: Color.accent
    opacity: 0.9
  }
  MouseArea {
    id: hit
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: controller.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    preventStealing: true
    property point pressedPoint: Qt.point(0, 0)
    property bool dragged: false
    property bool suppressClick: false
    property var pressedColumn: null
    property bool pressedBadge: false
    onPressed: function (event) {
      if (controller.dragging) {
        if (event.button === Qt.RightButton) {
          controller.cancelDrag();
          controller.drainSnapshot();
        }
        suppressClick = true;
        return;
      }
      if (event.button === Qt.LeftButton || !pressedButtons || pressedButtons === event.button) {
        dragged = false;
        suppressClick = false;
        pressedPoint = mapToItem(strip, event.x, event.y);
        pressedColumn = tile.modelData;
        pressedBadge = tile.memberCount > 1 && event.x >= badge.x;
      }
    }
    onPositionChanged: function (event) {
      if (!(pressedButtons & Qt.LeftButton))
        return;
      var point = mapToItem(strip, event.x, event.y);
      if (!dragged && Math.abs(point.x - pressedPoint.x) + Math.abs(point.y - pressedPoint.y) >= Style.space(6)) {
        suppressClick = true;
        dragged = controller.beginDrag(pressedColumn, point);
        if (dragged && controller.bar)
          controller.hideTooltip(tile);
      }
      if (dragged)
        controller.updateDrag(point);
    }
    onReleased: function (event) {
      if (dragged && event.button === Qt.LeftButton) {
        controller.updateDrag(mapToItem(strip, event.x, event.y));
        controller.finishDrag();
      }
    }
    onCanceled: {
      if (dragged) {
        controller.cancelDrag();
        controller.drainSnapshot();
      }
    }
    onClicked: function (event) {
      if (!dragged && !suppressClick) {
        if (pressedBadge && event.button === Qt.LeftButton) tile.triggerBadgePress(event.button);
        else tile.triggerPress(event.button, pressedColumn);
      }
    }
    onEntered: if (controller.bar && !controller.dragging)
      controller.showTooltip(tile, tile.tooltipText)
    onExited: if (controller.bar)
      controller.hideTooltip(tile)
    onWheel: function (event) {
      controller.wheel(event, hit, tile.modelData);
    }
  }
}
