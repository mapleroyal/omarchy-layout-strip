import QtQuick
import QtTest 1.2
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "LayoutStrip" as LayoutStrip

ShellRoot {
  id: harness
  property int checks: 0
  property int failures: 0
  property int stage: 0
  property real heldOffset: 0
  property var rightArrow: null
  property var leftArrow: null
  property var writes: []
  property int hostPresses: 0
  property int priorRounding: 0
  property real priorCenter: 0
  property real priorWidth: 0
  property var priorTile: null
  property point pressPosition: Qt.point(0,0)
  property var requestedCommands: []
  property var movedWidget: null
  readonly property bool capturePopup: Quickshell.env("STRIP_TEST_POPUP")==="1"
  readonly property var widget: loader.item

  function check(condition, name) {
    checks++;
    if (!condition) { failures++; console.error("FAIL", name, widget ? widget.debugState() : "no widget"); }
    else console.log("PASS", name);
  }
  function closeEnough(a,b) { return Math.abs(a-b) < 0.6; }
  function descendants(item, result) {
    if (!item) return result;
    result.push(item);
    if (item.children) for (var i=0; i<item.children.length; i++) descendants(item.children[i], result);
    return result;
  }
  function named(name) {
    var all=descendants(widget, []);
    for(var i=0;i<all.length;i++) if(all[i].objectName===name) return all[i];
    return null;
  }
  function snapshot(count, focus, workspace) {
    var columns=[];
    for(var i=0;i<count;i++) columns.push({address:"0x"+(i+1).toString(16),class:["chatgpt","google-chrome","md.obsidian.Obsidian"][i%3],title:"Test app "+(i+1),size:["small","medium","large"][i%3],focused:i===focus});
    return {reorderAvailable:true,workspaceId:workspace||1,activeAddress:focus>=0?columns[focus].address:"",columns:columns};
  }
  function move(item,x,y) { check(events.mouseMove(item,x,y,1,Qt.NoButton,Qt.NoModifier),"QTest mouse move delivered"); }
  function away() { move(canvas,2,2); }
  Connections { target: widget; function onActionRequested(command) { harness.requestedCommands.push(command); } }
  function tileFor(address) { return allTiles().filter(function(tile) { return tile.modelData.address === address; })[0]; }
  function allTiles() { return descendants(widget,[]).filter(function(item){return item.objectName==="layoutTile";}); }
  function surfaces() { return descendants(widget,[]).filter(function(item){return item.objectName==="tileSurface";}); }
  function underlines() { return descendants(widget,[]).filter(function(item){return item.objectName==="widthUnderline";}); }
  function popup() { return widget.resources.filter(function(item){return "contentWidth" in item && "anchorItem" in item && "open" in item;})[0]; }
  function options() { return descendants(popup().contentItem[0],[]).filter(function(item){return item.objectName==="menuOption";}); }
  function optionHit(option) { return option.children.filter(function(item){return "borderSpec" in item && item.height===Style.space(32);})[0]; }
  function preview(name, after) {
    if(!capturePopup) { if(after) after(); return; }
    test.stop();
    canvas.grabToImage(function(result){
      check(result.saveToFile(Qt.resolvedUrl(name).toString().replace("file://","")),name+" saved");
      if(after) after();
      test.start();
    });
  }
  function finish() {
    Style.cornerRadius=priorRounding;
    console.log("STRIP_INPUT_RESULTS",JSON.stringify({checks:checks,failures:failures}));
    test.stop();
    Qt.quit();
  }

  QtObject {
    id: fakeShell
    property var appLibrary: null
    function updateEntryInline(name,entry) { harness.writes.push({name:name,entry:entry}); }
  }
  QtObject {
    id: fakeBar
    property string position: "bottom"
    property bool vertical: false
    property int barSize: 26
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property var shell: fakeShell
    property var moduleSlots: [leftSlot, centerSlot, hostSlot]
    property string centerAnchor: "clock"
    function layoutEntries(region) {
      return region === "left" ? [{id:"left"},{id:"user1.layout-strip"}] : region === "center" ? [{id:"clock"}] : [];
    }
    function entryId(entry) { return typeof entry === "string" ? entry : entry.id; }
    function dropBarModule(slot, region, before) { harness.movedWidget={region:region,before:before,slot:slot}; }
    property var activePopout: null
    property var clickTargets: []
    function registerClickTarget(item) { if(clickTargets.indexOf(item)<0) clickTargets=clickTargets.concat([item]); }
    function unregisterClickTarget(item) { clickTargets=clickTargets.filter(function(target){return target!==item;}); }
    function targetBelongsToWindow(item, window) { return true; }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function requestPopout(item) {
      if(activePopout===item) return;
      if(activePopout) {
        if("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch();
        else if("close" in activePopout) activePopout.close();
      }
      activePopout=item;
    }
    function releasePopout(item) { activePopout=null; }
  }
  PanelWindow {
    id: panel
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "layout-strip-input-tests"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { bottom: true; left: true }
    implicitWidth: 496
    implicitHeight: 60
    color: Color.bar.background
    Item {
      id: canvas
      anchors.fill: parent
      Rectangle { anchors.fill:parent; color:Color.bar.background; z:-100 }
      Item { id:leftSlot; x:8; width:10; height:26; property string moduleName:"left"; property string region:"left"; property var activeItem:leftSlot }
      Item { id:centerSlot; x:panel.width/2-10; width:20; height:26; property string moduleName:"clock"; property string region:"center"; property var activeItem:centerSlot }
      Item {
        id: hostSlot
        x:18; y:15
        property string moduleName: "user1.layout-strip"
        property string region: "left"
        property var activeItem: loader.item
        width:widget ? widget.implicitWidth : 0
        height:26
        Loader {
          id: loader
          anchors.fill: parent
          sourceComponent: LayoutStrip.BarWidget { backendEnabled:false }
          onLoaded: { item.bar=fakeBar; item.measureGap(); item.applySnapshot(harness.snapshot(12,0,1)); }
        }
        // Match the packaged bar's later-declared drag/click MouseArea.
        MouseArea { anchors.fill:parent; onPressed:harness.hostPresses++ }
      }
      TestEvent { id: events }
    }
  }

  Timer {
    id: test
    interval: 220
    running: true
    repeat: true
    onTriggered: {
      try {
        switch(harness.stage++) {
        case 0:
          widget.measureGap();
          priorRounding=Style.cornerRadius;
          harness.rightArrow=harness.named("rightArrow");
          harness.leftArrow=harness.named("leftArrow");
          check(!!rightArrow && !!leftArrow,"Arrow objects found");
          check(widget.backendEnabled===false,"Real navigation disabled");
          var inputRegion=widget.protectedRegion();
          var stripPoint=named("layoutStrip").mapToItem(panel.contentItem,0,0);
          check(inputRegion.length===4 && inputRegion.every(function(value){return isFinite(value);}) &&
            closeEnough(inputRegion[0],widget.Screen.virtualX+stripPoint.x) &&
            closeEnough(inputRegion[1],widget.Screen.virtualY+panel.screen.height-panel.height+stripPoint.y),
            "Protected input region uses exact global coordinates for the bottom bar");
          check(closeEnough(inputRegion[2],widget.stripWidth) && closeEnough(inputRegion[3],widget.barSize),
            "Native protection is scoped to the strip rectangle");
          check(closeEnough(widget.geometryGap,panel.width/2-centerSlot.width/2-leftSlot.width-Style.space(8)),"Measured left-to-clock gap");
          check(closeEnough(widget.capacity,widget.geometryGap*0.85),"Capacity is 85% of available gap");
          check(widget.overflow && closeEnough(widget.stripWidth,widget.capacity),"Overflow fills permitted width");
          check(closeEnough(rightArrow.parent.x,(widget.width-widget.stripWidth)/2),"Strip is centered inside the available gap");
          check(closeEnough(widget.viewportWidth,widget.capacity-widget.endSpace*2),"Arrow space reserved outside viewport");
          var tiles=descendants(widget,[]).filter(function(item){return item.objectName==="layoutTile";});
          check(tiles.length===12 && tiles.every(function(tile){
            var icons=tile.children.filter(function(child){return "sourceSize" in child;});
            return icons.length===1 && icons[0].width===widget.iconSize && icons[0].height===widget.iconSize;
          }),"Every app icon has an identical square canvas");
          check(tiles.every(function(tile){
            var lines=tile.children.filter(function(child){return closeEnough(child.height,Style.space(2)) && child.opacity===0.9;});
            var factor=tile.modelData.size==="large"?2:tile.modelData.size==="medium"?1.5:1;
            return lines.length===1 && closeEnough(lines[0].width,widget.iconSize*factor) && closeEnough(lines[0].x,(tile.width-lines[0].width)/2);
          }),"Underlines are centered at exact 1:1.5:2 widths");
          check(fakeBar.clickTargets.indexOf(rightArrow)>=0 && fakeBar.clickTargets.indexOf(leftArrow)>=0,"Arrows register after delayed bar injection");
          check(loader.z>0,"Widget rises above bar host pointer area");
          check(closeEnough(widget.scrollOffset,0),"First focused column initially visible");
          widget.setOffset(-500,false);
          check(closeEnough(widget.scrollOffset,0),"Negative scrolling clamps to start");
          widget.setOffset(99999,false);
          check(closeEnough(widget.scrollOffset,widget.maximumOffset),"Scrolling clamps to end");
          widget.setOffset(0,false);
          check(widget.arrowMode==="hover","Hover is default scroll mode");
          away();
          move(rightArrow,rightArrow.width/2,rightArrow.height/2);
          break;
        case 1:
          check(widget.scrollDirection===1 && widget.scrollOffset>10,"Real pointer hover starts smooth right scroll");
          heldOffset=widget.scrollOffset;
          away();
          break;
        case 2:
          check(widget.scrollDirection===0 && closeEnough(widget.scrollOffset,heldOffset),"Hover exit stops scrolling");
          widget.chooseMode("click");
          check(widget.arrowMode==="click" && writes.length===1,"Click mode is exclusive and persisted through host API");
          check(writes[0].name==="user1.layout-strip" && writes[0].entry.arrowMode==="click","Click persistence passes correct id and mode");
          move(rightArrow,rightArrow.width/2,rightArrow.height/2);
          heldOffset=widget.scrollOffset;
          break;
        case 3:
          check(closeEnough(widget.scrollOffset,heldOffset),"Click mode does not scroll on hover");
          check(events.mousePress(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.LeftButton,Qt.NoModifier,1),"QTest click hold press delivered");
          break;
        case 4:
          check(widget.scrollDirection===1 && widget.scrollOffset>heldOffset+1,"Holding click scrolls continuously after the tap threshold");
          check(events.mouseRelease(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.LeftButton,Qt.NoModifier,1),"QTest click hold release delivered");
          heldOffset=widget.scrollOffset;
          break;
        case 5:
          check(widget.scrollDirection===0 && closeEnough(widget.scrollOffset,heldOffset),"Releasing click immediately stops scroll");
          check(hostPresses===0,"Host drag MouseArea did not steal pointer input");
          widget.setOffset(100,false);
          check(events.mouseWheel(widget,widget.width/2,widget.height/2,Qt.NoButton,Qt.NoModifier,0,120,1),"QTest vertical wheel event delivered");
          break;
        case 6:
          check(closeEnough(widget.scrollOffset,100-widget.iconSize*3),"Wheel up scrolls left through real MouseArea event");
          check(events.mouseWheel(widget,widget.width/2,widget.height/2,Qt.NoButton,Qt.NoModifier,0,-120,1),"QTest wheel down delivered");
          break;
        case 7:
          check(closeEnough(widget.scrollOffset,100),"Wheel down scrolls right");
          check(events.mouseWheel(widget,widget.width/2,widget.height/2,Qt.NoButton,Qt.NoModifier,-120,0,1),"QTest horizontal wheel event delivered");
          break;
        case 8:
          check(closeEnough(widget.scrollOffset,100+widget.iconSize*3),"Horizontal scrolling preserved");
          check(events.mousePress(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.RightButton,Qt.NoModifier,1),"QTest right press delivered");
          check(widget.menuOpen && widget.scrollDirection===0,"Right-click opens arrow mode popup and pauses scrolling");
          check(fakeBar.activePopout!==widget && fakeBar.activePopout===harness.popup().coordinatorKey,"Context menu coordinates without selecting the widget's panel underline");
          // Close before mapping the focus-taking popup: validate its event
          // path without changing the user's active window or desktop focus.
          widget.chooseMode("hover");
          events.mouseRelease(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.RightButton,Qt.NoModifier,1);
          check(widget.arrowMode==="hover" && !widget.menuOpen && writes.length===2,"Popup selection restores exclusive hover mode");
          check(writes[1].name==="user1.layout-strip" && writes[1].entry.arrowMode==="hover","Hover persistence passes correct id and mode");
          away();
          move(rightArrow,rightArrow.width/2,rightArrow.height/2);
          check(widget.hoverArmed && widget.scrollDirection===1,"Fresh hover re-arms scrolling after menu closes");
          away();
          widget.applySnapshot(harness.snapshot(12,11,1));
          break;
        case 9:
          check(closeEnough(widget.scrollOffset,widget.maximumOffset),"New focus reveals last column");
          var registeredTiles=fakeBar.clickTargets.filter(function(target){return target.objectName==="layoutTileTarget";});
          check(registeredTiles.length>0 && registeredTiles.every(function(tile){return tile.interactive;}),"Only visible tiles are registered for popup forwarding");
          check(registeredTiles.every(function(tile){return tile.x>=-0.5 && tile.x+tile.width<=widget.viewportWidth+0.5;}),"Forwarded tile hitboxes stay inside viewport");
          var partial=allTiles().filter(function(tile){return tile.x<widget.scrollOffset && tile.x+tile.width>widget.scrollOffset;})[0];
          check(!!partial && registeredTiles.some(function(target){return target.tileItem===partial;}),"Partially visible tile has clipped forwarding target");
          if(partial) {
            var visibleStart=widget.scrollOffset-partial.x;
            check(events.mouseClick(partial,visibleStart+(partial.width-visibleStart)/2,partial.height/2,Qt.RightButton,Qt.NoModifier,1),"QTest partial tile right-click delivered");
            check(widget.menuOpen && widget.menuAnchor===partial,"Visible part of clipped tile still opens menu on real click");
            widget.close();
          }
          widget.applySnapshot(harness.snapshot(12,-1,2));
          break;
        case 10:
          check(closeEnough(widget.scrollOffset,0),"Changing workspace resets offset");
          widget.applySnapshot(harness.snapshot(2,1,2));
          break;
        case 11:
          check(!widget.overflow && closeEnough(widget.scrollOffset,0),"Removing windows clears overflow and clamps scrolling");
          check(fakeBar.clickTargets.indexOf(rightArrow)<0 && fakeBar.clickTargets.indexOf(leftArrow)<0,"Hidden arrows unregister from popup forwarding");
          check(closeEnough(widget.stripWidth,widget.capacity),"Short content retains stable full interaction area");
          check(widget.contentInset>0,"Short content is centered within interaction area");
          if(capturePopup) {
            widget.applySnapshot(harness.snapshot(12,0,3));
            widget.openMenu(rightArrow);
            break;
          }
          harness.stage=13;
          break;
        case 12:
          var popups=widget.resources.filter(function(item){return "contentWidth" in item && "anchorItem" in item && "open" in item;});
          check(popups.length===1 && popups[0].open,"Mode popup actually mapped");
          var popup=popups[0];
          var keys=popup.contentItem[0];
          var card=keys.parent.parent;
          var choices=harness.options();
          check(choices.length===6,"Mapped popup has scrolling, appearance and widget options");
          check(choices.every(function(option){return option.y+option.height<=keys.height;}),"Mode choices fit within popup content bounds");
          check(widget.menuItemChecked(0) && !widget.menuItemChecked(1) && widget.menuItemChecked(2) && !widget.menuItemChecked(3),"Scroll and appearance groups each have exactly one selected choice");
          test.stop();
          card.grabToImage(function(result){
            check(result.saveToFile(Qt.resolvedUrl("mode-popup.png").toString().replace("file://","")),"Mapped mode popup image saved");
            var clickOption=harness.optionHit(choices.filter(function(option){return option.modelData.label==="Scroll on click";})[0]);
            check(events.mouseClick(clickOption,clickOption.width/2,clickOption.height/2,Qt.LeftButton,Qt.NoModifier,1),"QTest mapped popup choice click delivered");
            check(widget.arrowMode==="click" && !widget.menuOpen,"Clicking actual popup option switches and dismisses");
            test.start();
          });
          break;
        case 13:
          panel.implicitWidth=600;
          widget.measureGap();
          widget.applySnapshot(harness.snapshot(3,1,4));
          widget.chooseIndication("tiles");
          Style.cornerRadius=12;
          break;
        case 14:
          check(widget.indicationMode==="tiles" && !widget.overflow,"Three tiled width sizes fit without overflow");
          var paint=harness.surfaces();
          check(paint.length===3 && Math.abs(paint[1].width/paint[0].width-1.5)<0.001 && Math.abs(paint[2].width/paint[0].width-2)<0.001,"Painted tile widths have exact 1:1.5:2 ratios");
          check(paint.every(function(surface){return closeEnough(surface.radius,Math.min(Style.cornerRadius,Style.space(4))) && surface.radius<surface.height/2;}),"Rounded theme produces modest rounded-square tile corners");
          check(harness.underlines().every(function(line){return !line.visible;}),"Tile mode paints no underlines");
          check(Math.abs(paint[0].color.a-paint[1].color.a*0.25)<0.006 && Math.abs(paint[2].color.a-paint[0].color.a)<0.006,"Inactive tiles use one quarter of focused fill alpha");
          check(paint[1].color.a>=0.298 && paint[0].color.a>=0.073,"Active and inactive tiles retain visible translucent fills");
          check(allTiles().every(function(tile){var icon=tile.children.filter(function(child){return "sourceSize" in child;})[0];return icon.width===widget.iconSize && icon.height===widget.iconSize && closeEnough(icon.x,(tile.width-icon.width)/2) && closeEnough(icon.y,(tile.height-icon.height)/2);}),"Tile icons remain normalized and centered in both axes");
          var saved=writes[writes.length-1];
          check(saved.name==="user1.layout-strip" && saved.entry.indicationMode==="tiles" && saved.entry.arrowMode===widget.arrowMode,"Tiles selection persists while preserving arrow mode");
          preview("tiles-rounded.png",function(){Style.cornerRadius=0;});
          break;
        case 15:
          check(harness.surfaces().every(function(surface){return surface.radius===0;}),"Zero-radius theme gives tiles square corners");
          preview("tiles-square.png",function(){widget.chooseIndication("underlines");});
          break;
        case 16:
          check(widget.indicationMode==="underlines","Underlines appearance can be restored");
          check(harness.underlines().every(function(line){return line.visible && line.radius===0;}),"Underlines honor zero-radius theme");
          check(harness.surfaces().every(function(surface){return surface.radius===0;}),"Focused underline-mode tile also honors square corners");
          check(harness.surfaces().filter(function(surface){return !surface.parent.focused;}).every(function(surface){return surface.color.a===0;}),"Inactive underline-mode icons have no tile fill");
          var saved=writes[writes.length-1];
          check(saved.entry.indicationMode==="underlines" && saved.entry.arrowMode===widget.arrowMode,"Restoring underlines persists without changing arrow mode");
          preview("underlines-square.png",function(){Style.cornerRadius=12;});
          break;
        case 17:
          check(harness.underlines().every(function(line){return closeEnough(line.radius,line.height/2);}),"Rounded theme restores rounded underlines");
          check(harness.surfaces().every(function(surface){return closeEnough(surface.radius,Math.min(Style.cornerRadius,Style.space(4))) && surface.radius<surface.height/2;}),"Focused underline-mode tile uses modest rounded-square corners");
          preview("underlines-rounded.png");
          break;
        case 18:
          var first=allTiles()[0];
          check(!widget.overflow,"App menu access tested without overflow");
          check(events.mouseClick(first,first.width/2,first.height/2,Qt.RightButton,Qt.NoModifier,1),"QTest right-click on app icon delivered");
          check(widget.menuOpen && widget.menuKind==="app" && widget.menuItems.length===1 && widget.menuItems[0].label==="Close","App context menu contains only Close");
          check(fakeBar.activePopout!==widget,"App context menu also omits widget panel underline");
          widget.chooseMenuItem(0);
          check(widget.lastCommand[1]==="close" && widget.lastCommand[2]==="0x1" && widget.lastCommand.indexOf("focus")<0,"Close targets clicked inactive address without focus");
          check(!widget.menuOpen,"Close dismisses popup");
          var strip=named("layoutStrip");
          check(events.mouseClick(strip,widget.endSpace+2,strip.height/2,Qt.RightButton,Qt.NoModifier,1),"Right-click blank padding delivered");
          check(widget.menuOpen && widget.menuKind==="general" && widget.menuItems.length===6,"Blank padding opens general settings");
          widget.close();
          var firstTarget=fakeBar.clickTargets.filter(function(target){return target.objectName==="layoutTileTarget" && target.tileItem===first;})[0];
          check(fakeBar.clickTargets.indexOf(firstTarget)>fakeBar.clickTargets.indexOf(strip),"App forwarding target outranks broad padding target");
          firstTarget.triggerPress(Qt.RightButton);
          check(widget.menuKind==="app" && widget.menuAddress==="0x1","Popup forwarding right-click reaches exact app context");
          widget.close();
          widget.openAppMenu(allTiles()[2],allTiles()[2].modelData);
          widget.close();
          requestedCommands=[];
          events.mousePress(first,first.width/2,first.height/2,Qt.MiddleButton,Qt.NoModifier,1);
          check(requestedCommands.length===0,"Middle press waits for click release before closing");
          events.mouseRelease(first,first.width/2,first.height/2,Qt.MiddleButton,Qt.NoModifier,1);
          check(requestedCommands.length===1 && requestedCommands[0][1]==="close" && requestedCommands[0][2]==="0x1" &&
            requestedCommands[0][4]==="4" && requestedCommands[0][6]===widget.monitorName,
            "Middle click closes exactly the inactive clicked window in its current workspace, not the stale menu target");
          check(!widget.menuOpen && widget.snapshot.activeAddress==="0x2","Middle close neither focuses the window nor opens a menu");
          requestedCommands=[];
          firstTarget.triggerPress(Qt.MiddleButton);
          check(requestedCommands.length===1 && requestedCommands[0][1]==="close" && requestedCommands[0][2]==="0x1",
            "Popup forwarding middle-click closes the addressed tile once");
          widget.actionBusy=true;
          requestedCommands=[];
          firstTarget.triggerPress(Qt.MiddleButton);
          check(requestedCommands.length===0 && !widget.pendingFocus,"Busy middle close is not queued or converted to focus");
          widget.actionBusy=false;
          widget.resizing=true;
          firstTarget.triggerPress(Qt.MiddleButton);
          check(requestedCommands.length===0,"Forwarded middle close is suppressed during resize");
          widget.resizing=false;
          widget.lastCommand=[];
          away();
          break;
        case 19:
          check(!rightArrow.visible && !leftArrow.visible,"Non-overflow arrows hidden off hover");
          var strip=named("layoutStrip");
          move(strip,strip.width/2,strip.height/2);
          break;
        case 20:
          check(rightArrow.visible && leftArrow.visible && !rightArrow.available && !leftArrow.available,"Hover reveals dim settings arrows with no scrolling available");
          check(closeEnough(widget.stripWidth,widget.capacity),"Hover arrows never change strip width");
          check(events.mouseClick(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.RightButton,Qt.NoModifier,1),"Right click dim arrow delivered");
          check(widget.menuKind==="general" && widget.menuOpen,"Dim arrow still opens general settings");
          widget.chooseMenuItem(5);
          check(widget.menuKind==="regions","Move widget shows section choices");
          widget.chooseMenuItem(3);
          check(widget.menuKind==="positions","Right section shows insertion choices");
          widget.chooseMenuItem(widget.menuItems.length-1);
          check(movedWidget && movedWidget.region==="right" && movedWidget.before==="" && movedWidget.slot===hostSlot,"Move widget uses host persistent API and exact slot");
          priorWidth=widget.stripWidth;
          priorCenter=named("layoutStrip").x+widget.stripWidth/2;
          var edge=named("rightResizeEdge");
          check(edge.cursorShape===Qt.SizeHorCursor && edge.children.length===0,"Resize edges are cursor-only with no painted handles");
          check(events.mousePress(edge,edge.width/2,edge.height/2,Qt.LeftButton,Qt.NoModifier,1),"Resize edge press delivered");
          check(widget.resizing,"Edge press begins resize");
          events.mouseMove(widget,priorCenter+(priorWidth-40)/2,widget.barSize/2,1,Qt.LeftButton,Qt.NoModifier);
          break;
        case 21:
          check(widget.resizing && Math.abs(widget.stripWidth-(priorWidth-40))<1.1,"Resize changes width live");
          check(closeEnough(named("layoutStrip").x+widget.stripWidth/2,priorCenter),"Right-edge resize preserves exact center");
          check(closeEnough(widget.implicitWidth,widget.geometryGap),"Resize preserves host allocation and neighboring positions");
          events.mouseRelease(widget,priorCenter+(priorWidth-40)/2,widget.barSize/2,Qt.LeftButton,Qt.NoModifier,1);
          check(!widget.resizing,"Resize release stops resize");
          check(Math.abs(writes[writes.length-1].entry.widthRatio-(priorWidth-40)/widget.geometryGap)<0.005,"Resize persists proportional width once on release");
          var edge=named("leftResizeEdge");
          priorWidth=widget.stripWidth;
          events.mousePress(edge,edge.width/2,edge.height/2,Qt.LeftButton,Qt.NoModifier,1);
          events.mouseMove(widget,priorCenter-(priorWidth-20)/2,widget.barSize/2,1,Qt.LeftButton,Qt.NoModifier);
          break;
        case 22:
          check(closeEnough(widget.stripWidth,priorWidth-20) && closeEnough(named("layoutStrip").x+widget.stripWidth/2,priorCenter),"Left edge also resizes symmetrically from center");
          events.mouseRelease(widget,priorCenter-(priorWidth-20)/2,widget.barSize/2,Qt.LeftButton,Qt.NoModifier,1);
          widget.openMenu(named("layoutStrip"));
          widget.chooseMenuItem(4);
          check(closeEnough(widget.stripWidth,widget.capacity),"Reset width restores 85% allocation");
          widget.chooseIndication("tiles");
          widget.applySnapshot(snapshot(3,1,4));
          break;
        case 23:
          var first=allTiles()[0], last=allTiles()[2];
          priorTile=first;
          priorWidth=widget.lastCommand.length;
          events.mousePress(first,first.width/2,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          var point=last.mapToItem(first,last.width-2,last.height/2);
          events.mouseMove(first,point.x,point.y,1,Qt.LeftButton,Qt.NoModifier);
          check(widget.dragging && named("dragGhost").visible && named("dropMarker").visible,"Real icon drag shows ghost and insertion marker");
          check(widget.dropTarget && widget.dropTarget.address==="0x3" && widget.dropTarget.side==="after","Insertion targets stable last app address");
          check(widget.lastCommand.length===priorWidth,"Dragging preview sends no desktop action");
          widget.applySnapshot(snapshot(3,2,4));
          check(widget.columns[1].focused && widget.deferredSnapshot!==null,"Polling cannot replace dragged delegate or jump strip");
          events.mouseRelease(first,point.x,point.y,Qt.LeftButton,Qt.NoModifier,1);
          check(!widget.dragging && widget.lastCommand[1]==="reorder" && widget.lastCommand[2]==="0x1" && widget.lastCommand[4]==="0x3" && widget.lastCommand[6]==="after","Drop emits one addressed reorder without click navigation");
          widget.lastCommand=[];
          events.mousePress(first,first.width/2,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          events.mouseMove(first,first.width/2+10,-30,1,Qt.LeftButton,Qt.NoModifier);
          events.mouseRelease(first,first.width/2+10,-30,Qt.LeftButton,Qt.NoModifier,1);
          check(!widget.dragging && widget.lastCommand.length===0,"Dropping outside cancels without navigation");
          widget.applySnapshot(snapshot(12,0,4));
          break;
        case 24:
          widget.setOffset(0,false);
          var first=allTiles()[0];
          priorTile=first;
          events.mousePress(first,first.width/2,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          var point=named("layoutStrip").mapToItem(first,widget.stripWidth-widget.edgeWidth-2,widget.barSize/2);
          events.mouseMove(first,point.x,point.y,1,Qt.LeftButton,Qt.NoModifier);
          heldOffset=widget.scrollOffset;
          check(widget.dragging,"Drag can reach scroll endcap");
          break;
        case 25:
          check(widget.scrollOffset>heldOffset+10,"Drag near edge autoscrolls strip independently of arrow mode");
          check(widget.lastCommand.length===0,"Edge autoscroll never changes desktop view");
          var point=named("layoutStrip").mapToItem(priorTile,widget.stripWidth/2,-20);
          events.mouseRelease(priorTile,point.x,point.y,Qt.LeftButton,Qt.NoModifier,1);
          check(!widget.dragging && widget.lastCommand.length===0,"Cancel after edge scroll emits no desktop action");
          var unavailable=snapshot(3,0,4);
          unavailable.reorderAvailable=false;
          widget.applySnapshot(unavailable);
          break;
        case 26:
          var first=allTiles()[0];
          widget.lastCommand=[];
          events.mousePress(first,first.width/2,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          events.mouseMove(first,first.width/2+10,first.height/2,1,Qt.LeftButton,Qt.NoModifier);
          events.mouseRelease(first,first.width/2+10,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          check(!widget.dragging && widget.lastCommand.length===0,"Unavailable drag never falls through to focus click");
          widget.applySnapshot(snapshot(3,0,4));
          break;
        case 27:
          var first=allTiles()[0];
          events.mousePress(first,first.width/2,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          events.mouseMove(first,first.width/2+10,first.height/2,1,Qt.LeftButton,Qt.NoModifier);
          check(widget.dragging,"Secondary-button test begins active drag");
          var count=requestedCommands.length;
          events.mousePress(first,first.width/2+10,first.height/2,Qt.MiddleButton,Qt.NoModifier,1);
          first.triggerPress(Qt.MiddleButton);
          check(widget.dragging && requestedCommands.length===count,"Middle input during drag does not close or cancel the dragged window");
          events.mouseRelease(first,first.width/2+10,first.height/2,Qt.MiddleButton,Qt.NoModifier,1);
          events.mouseRelease(first,first.width/2+10,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          check(requestedCommands.length===count && !widget.menuOpen,"Releasing the middle/left sequence never closes or focuses a window");
          // TestEvent reports no held buttons after the middle release. Start
          // a separate drag to exercise the existing right-button cancellation.
          events.mousePress(first,first.width/2,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          events.mouseMove(first,first.width/2+10,first.height/2,1,Qt.LeftButton,Qt.NoModifier);
          events.mousePress(first,first.width/2+10,first.height/2,Qt.RightButton,Qt.NoModifier,1);
          events.mouseRelease(first,first.width/2+10,first.height/2,Qt.RightButton,Qt.NoModifier,1);
          events.mouseRelease(first,first.width/2+10,first.height/2,Qt.LeftButton,Qt.NoModifier,1);
          check(!widget.dragging && widget.lastCommand.length===0 && !widget.menuOpen,"Right-button cancellation cannot strand drag or trigger menu/click");
          events.mouseClick(first,first.width/2,first.height/2,Qt.MiddleButton,Qt.NoModifier,1);
          check(requestedCommands.length===count+1 && widget.lastCommand[1]==="close" && widget.lastCommand[2]==="0x1",
            "A fresh middle click works after the preceding drag was cancelled");
          widget.lastCommand=[];
          panel.implicitWidth=150;
          break;
        case 28:
          widget.measureGap();
          check(widget.compactStrip && !leftArrow.visible && !rightArrow.visible,"Cramped allocation yields arrow space to apps");
          check(widget.viewportWidth>0 && named("layoutStrip").clip,"Cramped placement keeps usable clipped viewport without overlapping neighbors");
          named("leftResizeEdge").pressed;
          widget.openMenu(named("layoutStrip"));
          check(widget.menuKind==="general" && widget.menuOpen,"Cramped strip still provides settings access");
          var otherOwner={close:function(){}};
          fakeBar.requestPopout(otherOwner);
          check(!widget.menuOpen && fakeBar.activePopout===otherOwner,"Opening another popup dismisses context menu with independent owner");
          fakeBar.releasePopout(otherOwner);
          panel.implicitWidth=600;
          widget.persistSetting("widthRatio",0.85);
          widget.chooseIndication("tiles");
          widget.applySnapshot(snapshot(3,0,10));
          break;
        case 29:
          widget.lastCommand=[];
          priorTile=tileFor("0x2");
          pressPosition=priorTile.mapToItem(widget,priorTile.width/2,priorTile.height/2);
          events.mousePress(priorTile,priorTile.width/2,priorTile.height/2,Qt.LeftButton,Qt.NoModifier,1);
          var next=snapshot(3,0,10); next.columns[0].title="Unrelated metadata during press";
          widget.applySnapshot(next);
          check(tileFor("0x2")===priorTile,"Title-only refresh retains the pressed delegate identity");
          break;
        case 30:
          events.mouseRelease(widget,pressPosition.x,pressPosition.y,Qt.LeftButton,Qt.NoModifier,1);
          check(widget.lastCommand[1]==="focus" && widget.lastCommand[2]==="0x2","Release after metadata refresh still focuses the pressed app");
          widget.openAppMenu(priorTile,priorTile.modelData);
          var next=snapshot(3,0,10); next.columns[1].title="Menu target title changed";
          widget.applySnapshot(next);
          break;
        case 31:
          check(widget.menuOpen && widget.menuAnchor===priorTile && tileFor("0x2")===priorTile,"App menu anchor survives metadata refresh across frames");
          check(priorTile.modelData.title==="Menu target title changed","Stable delegate receives updated title data");
          var next=snapshot(3,0,10); next.columns.reverse();
          widget.applySnapshot(next);
          check(tileFor("0x2")===priorTile,"Address-keyed move retains delegates on compositor reorder");
          widget.applySnapshot(snapshot(1,0,10));
          check(!widget.menuOpen,"Closing the menu target dismisses its stale app menu");
          widget.applySnapshot(snapshot(12,0,10));
          break;
        case 32:
          widget.setOffset(0,false);
          widget.setOffset(200,true);
          var next=snapshot(12,0,10); next.columns[1].title="Metadata during wheel glide";
          widget.applySnapshot(next);
          break;
        case 33:
          check(closeEnough(widget.scrollOffset,200),"Metadata-only refresh does not cancel an active glide destination");
          priorTile=tileFor("0x2");
          widget.applySnapshot({ok:false,error:"Synthetic query failure",columns:[]});
          check(widget.columns.length===12 && tileFor("0x2")===priorTile,"Failed query retains last good data and delegates");
          check(widget.backendStale && widget.queryError==="Synthetic query failure" && named("layoutStatus").visible,"Failed query exposes a visible stale status");
          check(!widget.canReorder,"Stale data disables reorder until recovery");
          widget.applySnapshot(snapshot(12,0,10));
          check(!widget.backendStale && !widget.queryError,"A successful snapshot clears stale status");
          widget.applySnapshot(snapshot(12,6,10));
          break;
        case 34:
          var focus=tileFor("0x7");
          check(focus.x>=widget.scrollOffset-0.6 && focus.x+focus.width<=widget.scrollOffset+widget.viewportWidth+0.6,"Resize begins with focused tile visible");
          widget.beginResize();
          widget.updateResize(Qt.point(widget.resizeCenter+widget.geometryGap*0.30/2,0));
          break;
        case 35:
          var focus=tileFor("0x7");
          check(focus.x>=widget.scrollOffset-0.6 && focus.x+focus.width<=widget.scrollOffset+widget.viewportWidth+0.6,"Shrinking the viewport preserves an already-visible focused tile");
          widget.finishResize(true);
          widget.persistSetting("widthRatio",0.85);
          break;
        case 36:
          widget.setOffset(0,false);
          check(tileFor("0x7").x>widget.viewportWidth,"Manual scrolling may deliberately hide the focused tile");
          widget.beginResize();
          widget.updateResize(Qt.point(widget.resizeCenter+widget.geometryGap*0.30/2,0));
          break;
        case 37:
          check(closeEnough(widget.scrollOffset,0),"Resizing preserves manual scrolling when focus was already hidden");
          widget.finishResize(true);
          widget.lastCommand=[];
          widget.actionBusy=true;
          widget.focusColumn(widget.columns[1]);
          widget.focusColumn(widget.columns[2]);
          var count=requestedCommands.length;
          widget.runAction([widget.helper,"close","0x1","--workspace","10","--monitor",widget.monitorName]);
          check(widget.pendingFocus && widget.pendingFocus[2]==="0x3" && requestedCommands.length===count,"Busy input keeps only the latest focus and never queues close");
          check(named("layoutStatus").visible && widget.statusMessage.indexOf("progress")>=0,"Busy actions expose status feedback");
          widget.onBackendActionFinished({ok:true});
          check(widget.lastCommand[1]==="focus" && widget.lastCommand[2]==="0x3" && !widget.pendingFocus,"Completion dispatches the latest focus once");
          widget.actionBusy=true;
          widget.focusColumn(widget.columns[1]);
          widget.applySnapshot(snapshot(3,0,11));
          count=requestedCommands.length;
          widget.onBackendActionFinished({ok:true});
          check(!widget.pendingFocus && requestedCommands.length===count,"Workspace change discards a stale queued focus");
          widget.persistSetting("widthRatio",0.85);
          widget.applySnapshot(snapshot(12,0,11));
          widget.chooseMode("click");
          break;
        case 38:
          widget.setOffset(0,false);
          events.mouseClick(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.LeftButton,Qt.NoModifier,1);
          break;
        case 39:
          check(closeEnough(widget.scrollOffset,widget.iconSize*3),"A short arrow click advances exactly one step without a hold increment");
          finish();
          break;
        }
      } catch(error) {
        console.error("HARNESS_ERROR",error.stack||error);
        test.stop();
        Qt.quit();
      }
    }
  }
  Timer { interval:25000; running:true; onTriggered:{console.error("HARNESS_TIMEOUT");Qt.quit();} }
}
