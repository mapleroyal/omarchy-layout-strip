import QtQuick

MouseArea {
  required property var controller
  width: Math.min(controller.edgeWidth, controller.stripWidth / 2)
  height: controller.barSize
  z: 10
  hoverEnabled: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  cursorShape: Qt.SizeHorCursor
  preventStealing: true
  onPressed: function (event) {
    if (event.button === Qt.LeftButton)
      controller.beginResize();
    else
      controller.openMenu(controller.stripItem);
  }
  onPositionChanged: function (event) {
    if (pressedButtons & Qt.LeftButton)
      controller.updateResize(mapToItem(root, event.x, event.y));
  }
  onReleased: function (event) {
    if (event.button === Qt.LeftButton)
      controller.finishResize(true);
  }
  onCanceled: controller.finishResize(false)
  onWheel: function (event) {
    controller.wheel(event);
  }
}
