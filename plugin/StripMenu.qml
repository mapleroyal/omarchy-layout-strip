import QtQuick
import qs.Commons
import qs.Ui

KeyboardPanel {
  id: menuPanel
  required property var controller
  property QtObject contextMenuOwner: QtObject {
    function close() {
      controller.close();
    }
    function closeForPopoutSwitch() {
      controller.close();
    }
  }
  anchorItem: controller.menuAnchor || controller.stripItem
  bar: controller.bar
  owner: contextMenuOwner
  open: controller.menuOpen
  contentWidth: menuPanel.fittedContentWidth(Style.space(controller.menuKind === "stack" ? 310 : 250))
  contentHeight: menuPanel.fittedContentHeight(modeColumn.implicitHeight)
  focusTarget: modeKeys
  property Connections cursorConnection: Connections {
    target: controller
    function onMenuCursorChanged() {
      Qt.callLater(menuPanel.revealCursor);
    }
    function onMenuKindChanged() {
      menuScroll.contentY = 0;
      Qt.callLater(menuPanel.revealCursor);
    }
    function onMenuItemsChanged() { Qt.callLater(menuPanel.revealCursor); }
  }
  function revealCursor() {
    var item = menuRepeater.itemAt(controller.menuCursor);
    if (!item)
      return;
    if (item.y < menuScroll.contentY)
      menuScroll.contentY = item.y;
    else if (item.y + item.height > menuScroll.contentY + menuScroll.height)
      menuScroll.contentY = Math.max(0, item.y + item.height - menuScroll.height);
  }
  PanelKeyCatcher {
    id: modeKeys
    anchors.fill: parent
    onCloseRequested: controller.close()
    onMoveRequested: function (dx, dy) {
      if ((dx || dy) && controller.menuItems.length)
        controller.menuCursor = (controller.menuCursor + (dy || dx) + controller.menuItems.length) % controller.menuItems.length;
    }
    onTabRequested: function (direction) {
      if (controller.menuItems.length)
        controller.menuCursor = (controller.menuCursor + direction + controller.menuItems.length) % controller.menuItems.length;
    }
    onActivateRequested: controller.chooseMenuItem(controller.menuCursor)
    Flickable {
      id: menuScroll
      anchors.fill: parent
      contentHeight: modeColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: modeColumn
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          id: menuRepeater
          model: controller.menuItems
          Column {
            id: option
            objectName: "menuOption"
            required property var modelData
            required property int index
            width: parent.width
            spacing: Style.space(4)
            Text {
              visible: !!option.modelData.header
              leftPadding: Style.space(8)
              topPadding: option.index > 0 ? Style.space(6) : 0
              text: option.modelData.header || ""
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            BorderSurface {
              objectName: "menuOptionHit"
              width: parent.width
              height: Style.space(32)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(4)) : 0
              color: controller.menuCursor === option.index ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
              Image {
                id: memberIcon
                visible: option.modelData.action === "member"
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(8)
                width: Style.space(18)
                height: width
                source: visible ? controller.appIcon({class: option.modelData.className}) : ""
                fillMode: Image.PreserveAspectFit
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space(8)
                anchors.leftMargin: memberIcon.visible ? memberIcon.x + memberIcon.width + Style.space(8) : Style.space(8)
                anchors.rightMargin: memberIcon.visible ? Style.space(32) : Style.space(8)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: (option.modelData.checked === undefined ? "" : option.modelData.checked ? "●  " : "○  ") + option.modelData.label
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                property string pressedAddress: ""
                onPressed: pressedAddress = option.modelData.action === "member" ? option.modelData.address : ""
                onEntered: controller.menuCursor = option.index
                onClicked: {
                  if (pressedAddress) controller.focusStackMember(pressedAddress);
                  else controller.chooseMenuItem(option.index);
                }
              }
              Item {
                objectName: "stackMemberClose"
                visible: option.modelData.action === "member"
                anchors.right: parent.right
                width: Style.space(28)
                height: parent.height
                Accessible.name: "Close " + option.modelData.label
                Accessible.role: Accessible.Button
                Accessible.onPressAction: controller.closeStackMember(option.modelData.address)
                Text {
                  anchors.centerIn: parent
                  text: "×"
                  color: Color.popups.text
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  property string pressedAddress: ""
                  onPressed: pressedAddress = option.modelData.address
                  onClicked: controller.closeStackMember(pressedAddress)
                }
              }
            }
          }
        }
      }
    }
  }
}
