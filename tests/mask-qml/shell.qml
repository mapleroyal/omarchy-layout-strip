import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: root
  property int checks: 0
  property int failures: 0
  property int stage: 0
  property bool allowed: false
  property bool hostDrag: false
  property bool hostFullscreen: true
  property var alternateMask: null
  property var selectedSurface: strip.QsWindow.window
  property var selectedStrip: strip
  property var repair: null

  function check(condition, label) {
    checks++;
    if (!condition) { failures++; console.error("MASK_FAIL", label); }
    else console.log("MASK_PASS", label);
  }

  Component {
    id: repairFactory
    Plugin.StripInputMask {
      surface: root.selectedSurface
      stripItem: root.selectedStrip
      enabled: root.allowed
    }
  }

  // Real Quickshell window/Region objects keep mask semantics in the test;
  // QPA offscreen creates no surface on the user's display.
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 320
    implicitHeight: 120
    mask: root.alternateMask ? root.alternateMask
      : root.hostDrag ? null : root.hostFullscreen ? emptyRegion : normalRegion
    Item { id: barStrip; width: parent.width; height: 26 }
    Item { id: strip; x: 48; width: 160; height: 26 }
  }
  FloatingWindow {
    id: secondWindow
    visible: true
    implicitWidth: 240
    implicitHeight: 100
    mask: secondEmptyRegion
    Item { id: secondStrip; x: 30; width: 100; height: 26 }
  }
  Region { id: emptyRegion }
  Region { id: secondEmptyRegion }
  Region { id: normalRegion; item: barStrip }
  Region { id: customRegion; x: 1; y: 2; width: 3; height: 4 }
  Region { id: compoundRegion; Region { x: 3; y: 4; width: 5; height: 6 } }

  Component.onCompleted: repair = repairFactory.createObject(strip)
  Timer {
    interval: 35
    repeat: true
    running: true
    onTriggered: {
      try {
        switch(root.stage++) {
        case 0:
          check(!!repair,"Production mask component loads");
          check(!repair.repairActive && emptyRegion.item===null,"Unknown/fullscreen state leaves empty mask untouched");
          root.allowed=true;
          break;
        case 1:
          check(repair.repairActive && emptyRegion.item===strip,"Offscreen fullscreen recovery enables only the strip item");
          check(window.mask===emptyRegion && emptyRegion.regions.length===0,"Repair preserves the host mask binding and region identity");
          check(strip.width===160 && strip.height===26,"Recovery stays bounded to the plugin rectangle");
          root.hostDrag=true;
          break;
        case 2:
          check(window.mask===null,"Host drag retains full-surface input");
          check(!repair.repairActive && emptyRegion.item===null,"Leaving empty mask restores its original item");
          root.hostDrag=false;
          break;
        case 3:
          check(repair.repairActive && emptyRegion.item===strip,"Finishing host drag reacquires empty-mask recovery");
          root.allowed=false;
          break;
        case 4:
          check(!repair.repairActive && emptyRegion.item===null,"Visible fullscreen or stale state immediately releases recovery");
          root.allowed=true;
          root.hostFullscreen=false;
          break;
        case 5:
          check(window.mask===normalRegion && normalRegion.item===barStrip,"Ordinary bar input keeps its original region");
          check(!repair.repairActive && emptyRegion.item===null,"Normal mask is never narrowed to the plugin");
          root.hostFullscreen=true;
          break;
        case 6:
          check(repair.repairActive && emptyRegion.item===strip,"Host switching back to empty mask recovers the strip");
          root.alternateMask=customRegion;
          break;
        case 7:
          check(!repair.repairActive && emptyRegion.item===null,"Switching masks releases previous region ownership");
          check(customRegion.item===null && customRegion.width===3 && customRegion.height===4,"Nonempty custom mask remains unchanged");
          root.alternateMask=compoundRegion;
          break;
        case 8:
          check(!repair.repairActive && compoundRegion.item===null && compoundRegion.regions.length===1,"Compound masks remain unchanged");
          root.alternateMask=null;
          break;
        case 9:
          check(repair.repairActive,"Recovery returns after custom mask is removed");
          root.selectedSurface=secondStrip.QsWindow.window;
          root.selectedStrip=secondStrip;
          break;
        case 10:
          check(emptyRegion.item===null,"Moving to another window restores the first window's mask");
          check(repair.repairActive && secondEmptyRegion.item===secondStrip,"Moving to another window acquires only its own strip");
          root.selectedStrip=null;
          break;
        case 11:
          check(!repair.repairActive && secondEmptyRegion.item===null,"Losing the strip releases its mask");
          root.selectedStrip=secondStrip;
          break;
        case 12:
          check(repair.repairActive && secondEmptyRegion.item===secondStrip,"Reattaching the strip restores recovery");
          repair.destroy();
          root.repair=null;
          break;
        case 13:
          check(secondWindow.mask===secondEmptyRegion && secondEmptyRegion.item===null,"Destroying the repair restores the host's original empty mask");
          console.log("MASK_RESULTS",JSON.stringify({checks:checks,failures:failures}));
          Qt.quit();
          break;
        }
      } catch(error) {
        console.error("MASK_HARNESS_ERROR",String(error),error.stack||"");
        Qt.quit();
      }
    }
  }
  Timer { interval: 5000; running: true; onTriggered: { console.error("MASK_TIMEOUT"); Qt.quit(); } }
}
