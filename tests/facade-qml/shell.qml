import QtQuick
import QtQuick.Window
import Quickshell
import "Plugin/HostAdapter.js" as Host
import "Plugin/Geometry.js" as Geometry

ShellRoot {
  id: harness
  property int stage: 0
  property int checks: 0
  property int failures: 0
  property int measurements: 0
  property int priorMeasurements: 0
  property var addedSlot: null
  readonly property var measured: Host.geometryInput(strip, facade, panel, 8)
  readonly property var placement: Geometry.measure(measured)
  readonly property var capabilities: Host.capabilities(facade, strip, panel)
  readonly property bool hidden: Host.hidden(facade)
  onMeasuredChanged: measurements++

  function check(condition, name) {
    checks++;
    if (!condition) {
      failures++;
      console.error("FAIL " + name + " | " + JSON.stringify(measured) + " | " + JSON.stringify(placement));
    } else console.log("PASS " + name);
  }
  function allocation(value, name) { check(Math.abs(placement.allocation - value) < 0.001, name); }

  QtObject {
    id: barState
    property bool barHidden: false
  }
  QtObject {
    id: shellApi
    property var bar: barState
    property var barConfig: ({centerAnchor: "clock"})
    function updateEntryInline(id, settings) { return true; }
  }
  QtObject {
    id: facade
    property var shell: shellApi
    property var layoutConfig: ({
      left: [{id: "workspaces"}, {id: "strip"}, {id: "extra"}],
      center: [{id: "clock"}, {id: "badge"}], right: []
    })
    function targetBelongsToWindow(target, window) { return target && target.Window.window === window; }
    function run(command) { }
    function registerClickTarget(target) { }
    function unregisterClickTarget(target) { }
  }

  component Slot: Item {
    required property var entry
    property string moduleName: entry.id
    property string region: "left"
    property var activeItem: null
    height: 30
  }

  Component {
    id: extraComponent
    Slot {
      entry: ({id: "extra"})
      width: 40
      activeItem: extraContent
      Item { id: extraContent; anchors.fill: parent }
    }
  }

  Window {
    id: panel
    width: 1000
    height: 30
    visible: true
    Item {
      id: wrapper
      anchors.fill: parent
      Item {
        id: leftRegion
        Slot {
          id: workspaceSlot
          entry: ({id: "workspaces"})
          width: 30
          activeItem: workspaceContent
          Item { id: workspaceContent; anchors.fill: parent }
        }
        Slot {
          id: ownSlot
          entry: ({id: "strip"})
          width: 0
          activeItem: strip
          Item {
            id: strip
            property string moduleName: "strip"
            // A fake slot inside the widget must not be discovered.
            Slot {
              entry: ({id: "extra"})
              width: 999
              activeItem: nestedContent
              Item { id: nestedContent }
            }
          }
        }
      }
      Item {
        id: centerRegion
        Slot {
          id: clockSlot
          entry: ({id: "clock"})
          region: "center"
          width: 100
          activeItem: clockLoader.item
          Loader {
            id: clockLoader
            active: false
            sourceComponent: Item { }
          }
        }
        Slot {
          entry: ({id: "badge"})
          region: "center"
          width: 40
          activeItem: badgeContent
          Item { id: badgeContent }
        }
      }
    }
  }

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      switch (harness.stage++) {
      case 0:
        check(capabilities.layout && capabilities.move, "facade capabilities discover own slot");
        check(Host.findSlot(strip, facade, panel) === ownSlot, "own slot found through nested Item children");
        check(measured.sections.left[2].width === 0, "nested fake slot is pruned");
        check(measured.sections.center[0].width === 0, "unloaded activeItem starts at zero width");
        allocation(462, "initial allocation before delayed Loader");
        clockLoader.active = true;
        break;
      case 1:
        check(measured.sections.center[0].width === 100, "delayed Loader completion updates binding");
        allocation(412, "allocation reacts to delayed activeItem");
        clockSlot.width = 150;
        break;
      case 2:
        allocation(387, "allocation reacts to sibling slot width");
        clockLoader.item.visible = false;
        break;
      case 3:
        allocation(462, "allocation reacts to activeItem visibility");
        clockLoader.item.visible = true;
        clockSlot.visible = false;
        break;
      case 4:
        allocation(462, "hidden parent slot contributes zero width");
        clockSlot.visible = true;
        break;
      case 5:
        allocation(387, "allocation reacts when slot becomes visible");
        workspaceSlot.width = 70;
        break;
      case 6:
        allocation(347, "allocation reacts to left sibling width");
        addedSlot = extraComponent.createObject(leftRegion);
        check(addedSlot !== null, "dynamic sibling slot created");
        break;
      case 7:
        check(measured.sections.left[2].width === 40, "child addition invalidates binding");
        allocation(307, "new child reduces allocation");
        addedSlot.destroy();
        addedSlot = null;
        break;
      case 8:
        check(measured.sections.left[2].width === 0, "child removal invalidates binding");
        allocation(347, "removed child restores allocation");
        shellApi.barConfig = {centerAnchor: "badge"};
        break;
      case 9:
        check(measured.centerAnchor === "badge", "facade config centerAnchor stays reactive");
        allocation(252, "new center anchor changes allocation");
        shellApi.barConfig = {centerAnchor: "absent"};
        break;
      case 10:
        allocation(327, "missing anchor uses centered row");
        shellApi.barConfig = {centerAnchor: "clock"};
        panel.width = 1200;
        break;
      case 11:
        allocation(447, "surface resize updates allocation");
        barState.barHidden = true;
        priorMeasurements = measurements;
        ownSlot.width = 777;
        strip.width = 555;
        break;
      case 12:
        check(hidden, "facade hidden state stays reactive");
        allocation(447, "own width never feeds back into allocation");
        check(measurements === priorMeasurements, "own width does not invalidate geometry binding");
        clockLoader.active = false;
        break;
      case 13:
        allocation(522, "Loader unload updates activeItem and allocation");
        console.log("FACADE_GEOMETRY_RESULTS " + JSON.stringify({checks: checks, failures: failures, measurements: measurements}));
        Qt.quit();
        break;
      }
    }
  }
  Timer {
    interval: 5000
    running: true
    onTriggered: { console.error("FACADE_TEST_TIMEOUT"); Qt.quit(); }
  }
}
