import QtQuick
import qs.Commons

// The suite exercises real QtQuick input on an offscreen Window. Only the
// Wayland layer-shell container is replaced; popup coordination is preserved.
QtObject {
  id: root
  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property bool open: false
  property int padding: Style.spacing.popupPadding
  property int contentWidth: 250
  property int contentHeight: 200
  property Item focusTarget: null
  readonly property var coordinatorKey: owner || root
  property Item holder: Item { width: root.contentWidth; height: root.contentHeight }
  default property alias contentItem: root.holder.children
  function fittedContentWidth(value) { return value; }
  function fittedContentHeight(value) { return value + padding * 2; }
  onOpenChanged: {
    if (!bar) return;
    if (open) bar.requestPopout(coordinatorKey);
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey);
  }
}
