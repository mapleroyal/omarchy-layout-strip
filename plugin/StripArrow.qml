import QtQuick
import qs.Commons
import qs.Ui
import "HostAdapter.js" as HostAdapter

Item {
  id: arrow
  required property var controller
  objectName: direction < 0 ? "leftArrow" : "rightArrow"
  required property int direction
  required property bool available
  width: controller.arrowSize
  height: controller.barSize
  readonly property bool tooltipHovered: mouse.containsMouse
  readonly property bool wantsScroll: visible && available && !controller.menuOpen && !controller.resizing && !controller.dragging && (controller.arrowMode === "hover" ? mouse.containsMouse && controller.hoverArmed : mouse.pressed && mouse.holdReady && (mouse.pressedButtons & Qt.LeftButton))
  onWantsScrollChanged: {
    if (wantsScroll) {
      controller.stopGlide();
      controller.scrollDirection = direction;
    } else if (controller.scrollDirection === direction)
      controller.scrollDirection = 0;
  }
  function triggerPress(button) {
    if (button === Qt.RightButton)
      controller.openMenu(arrow);
    else if (button === Qt.LeftButton && controller.arrowMode === "click" && available && !controller.resizing && !controller.dragging)
      controller.setOffset(controller.scrollOffset + direction * controller.iconSize * 3, true);
  }
  property var registeredBar: null
  readonly property var hostBar: controller.bar
  function syncRegistration() {
    if (registeredBar)
      HostAdapter.unregisterClickTarget(registeredBar, arrow);
    registeredBar = hostBar;
    if (registeredBar && visible)
      HostAdapter.registerClickTarget(registeredBar, arrow);
  }
  onHostBarChanged: syncRegistration()
  onVisibleChanged: syncRegistration()
  Component.onCompleted: syncRegistration()
  Component.onDestruction: {
    if (registeredBar)
      HostAdapter.unregisterClickTarget(registeredBar, arrow);
    if (controller.scrollDirection === direction)
      controller.scrollDirection = 0;
  }
  OpticalGlyph {
    anchors.centerIn: parent
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    text: arrow.direction < 0 ? "\uf104" : "\uf105"
    color: controller.foreground
    opacity: arrow.available ? 0.85 : 0.25
    fontSize: Style.bar.iconFont
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    property bool holdReady: false
    Timer {
      id: holdDelay
      interval: 180
      onTriggered: mouse.holdReady = true
    }
    onEntered: {
      controller.hoverArmed = true;
      if (controller.bar)
        controller.showTooltip(arrow, (arrow.direction < 0 ? "Scroll left" : "Scroll right") + " · Right-click for settings");
    }
    onExited: if (controller.bar)
      controller.hideTooltip(arrow)
    onPressed: function (event) {
      holdReady = false;
      if (event.button === Qt.LeftButton && controller.arrowMode === "click")
        holdDelay.restart();
      if (event.button === Qt.RightButton) {
        controller.scrollDirection = 0;
        controller.openMenu(arrow);
      }
    }
    onReleased: {
      holdDelay.stop();
    }
    onCanceled: {
      holdDelay.stop();
      holdReady = false;
    }
    onClicked: function (event) {
      // A tap advances one icon; holding continuously scrolls until release.
      if (event.button === Qt.LeftButton && !holdReady)
        arrow.triggerPress(event.button);
    }
    onWheel: function (event) {
      controller.wheel(event);
    }
  }
}
