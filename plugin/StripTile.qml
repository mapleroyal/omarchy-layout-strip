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
  required property var columnData
  readonly property var modelData: columnData
  width: controller.tileWidth(modelData)
  height: controller.barSize
  readonly property bool focused: modelData.focused === true
  opacity: controller.dragging && controller.dragColumn.address === modelData.address ? 0.25 : 1
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
  property var registeredBar: null
  readonly property var hostBar: controller.bar
  function syncRegistration() {
    if (registeredBar)
      HostAdapter.unregisterClickTarget(registeredBar, forwardedHit);
    registeredBar = hostBar;
    if (registeredBar && interactive)
      HostAdapter.registerClickTarget(registeredBar, forwardedHit);
  }
  function triggerPress(button) {
    if (button === Qt.LeftButton)
      controller.focusColumn(modelData);
    else if (button === Qt.MiddleButton)
      controller.closeColumn(modelData);
    else if (button === Qt.RightButton)
      controller.openAppMenu(tile, modelData);
  }
  onModelDataChanged: {
    if (hit.containsMouse && !controller.dragging)
      controller.showTooltip(tile, String(modelData.title || modelData.class) + (controller.statusMessage ? " · " + controller.statusMessage : ""));
  }
  onHostBarChanged: syncRegistration()
  onInteractiveChanged: syncRegistration()
  Component.onCompleted: syncRegistration()
  Component.onDestruction: if (registeredBar)
    HostAdapter.unregisterClickTarget(registeredBar, forwardedHit)

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
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round((parent.height - height) / 2) - (controller.indicationMode === "underlines" ? Style.space(1) : 0)
    width: controller.iconSize
    height: controller.iconSize
    source: controller.appIcon(tile.modelData)
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
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
      }
    }
    onPositionChanged: function (event) {
      if (!(pressedButtons & Qt.LeftButton))
        return;
      var point = mapToItem(strip, event.x, event.y);
      if (!dragged && Math.abs(point.x - pressedPoint.x) + Math.abs(point.y - pressedPoint.y) >= Style.space(6)) {
        suppressClick = true;
        dragged = controller.beginDrag(tile.modelData, point);
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
      if (!dragged && !suppressClick)
        tile.triggerPress(event.button);
    }
    onEntered: if (controller.bar && !controller.dragging)
      controller.showTooltip(tile, String(tile.modelData.title || tile.modelData.class) + (controller.statusMessage ? " · " + controller.statusMessage : ""))
    onExited: if (controller.bar)
      controller.hideTooltip(tile)
    onWheel: function (event) {
      controller.wheel(event);
    }
  }
}
