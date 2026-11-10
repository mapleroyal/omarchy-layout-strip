import QtQuick
import Quickshell

// Omarchy can select an empty input region for an offscreen fullscreen column.
// Borrow only that empty region while the compositor proves it is not covering
// the workspace. Keep the host's mask binding intact (including null for drag).
Item {
  id: root
  property var surface: null
  property Item stripItem: null
  property var emptyMask: null
  readonly property bool repairActive: enabled && !!surface && !!emptyMask &&
    surface.mask === emptyMask && !!stripItem && stripItem.visible &&
    emptyMask.width === 0 && emptyMask.height === 0 &&
    emptyMask.regions.length === 0 && emptyMask.intersection === Intersection.Combine

  function observeMask() {
    var mask = surface && "mask" in surface ? surface.mask : null;
    if (mask === emptyMask) return;
    // Save its identity before binding item; reading our own item assignment
    // as a new nonempty mask would otherwise make the binding oscillate.
    emptyMask = mask && mask.item === null && mask.width === 0 && mask.height === 0 &&
      mask.regions.length === 0 && mask.intersection === Intersection.Combine ? mask : null;
  }

  onSurfaceChanged: observeMask()
  Component.onCompleted: observeMask()
  // Binding restores on deactivation, but not when destroyed while active.
  Component.onDestruction: root.enabled = false
  function refreshGeometry() {
    if (repairActive) emptyMask.changed();
  }
  onRepairActiveChanged: if (repairActive) Qt.callLater(refreshGeometry)
  // Region watches its item's geometry, but not the pooled ancestors that
  // place it in the bar. Refresh after those transforms settle as well.
  TransformWatcher {
    a: root.surface ? root.surface.contentItem : null
    b: root.stripItem
    onTransformChanged: Qt.callLater(root.refreshGeometry)
  }
  Connections {
    target: root.surface
    ignoreUnknownSignals: true
    function onMaskChanged() { root.observeMask(); }
  }
  Binding {
    target: root.emptyMask
    property: "item"
    value: root.stripItem
    when: root.repairActive
  }
}
