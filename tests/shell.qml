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
    return {workspaceId:workspace||1,activeAddress:focus>=0?columns[focus].address:"",columns:columns};
  }
  function move(item,x,y) { check(events.mouseMove(item,x,y,1,Qt.NoButton,Qt.NoModifier),"QTest mouse move delivered"); }
  function away() { move(canvas,2,2); }
  function allTiles() { return descendants(widget,[]).filter(function(item){return item.objectName==="layoutTile";}); }
  function surfaces() { return descendants(widget,[]).filter(function(item){return item.objectName==="tileSurface";}); }
  function underlines() { return descendants(widget,[]).filter(function(item){return item.objectName==="widthUnderline";}); }
  function popup() { return widget.resources.filter(function(item){return "contentWidth" in item && "anchorItem" in item && "open" in item;})[0]; }
  function options() { return descendants(popup().contentItem[0],[]).filter(function(item){return "modelData" in item && typeof item.modelData==="string";}); }
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
    property var moduleSlots: [leftSlot, centerSlot]
    property var activePopout: null
    property var clickTargets: []
    function registerClickTarget(item) { if(clickTargets.indexOf(item)<0) clickTargets=clickTargets.concat([item]); }
    function unregisterClickTarget(item) { clickTargets=clickTargets.filter(function(target){return target!==item;}); }
    function targetBelongsToWindow(item, window) { return true; }
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function requestPopout(item) { activePopout=item; }
    function releasePopout(item) { activePopout=null; }
  }
  PanelWindow {
    id: panel
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "layout-strip-input-tests"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { bottom: true; left: true }
    implicitWidth: 260
    implicitHeight: 60
    color: Color.bar.background
    Item {
      id: canvas
      anchors.fill: parent
      Rectangle { anchors.fill:parent; color:Color.bar.background; z:-100 }
      Item { id:leftSlot; x:0; width:10; height:26; property string moduleName:"left"; property string region:"left"; property var activeItem:leftSlot }
      Item { id:centerSlot; x:230; width:10; height:26; property string moduleName:"clock"; property string region:"center"; property var activeItem:centerSlot }
      Item {
        id: hostSlot
        x:10; y:15
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
          priorRounding=Style.cornerRadius;
          harness.rightArrow=harness.named("rightArrow");
          harness.leftArrow=harness.named("leftArrow");
          check(!!rightArrow && !!leftArrow,"Arrow objects found");
          check(widget.backendEnabled===false,"Real navigation disabled");
          check(closeEnough(widget.geometryGap,220),"Measured left-to-clock gap");
          check(closeEnough(widget.capacity,220*0.85),"Capacity is 85% of available gap");
          check(widget.overflow && closeEnough(widget.stripWidth,widget.capacity),"Overflow fills permitted width");
          check(closeEnough(rightArrow.parent.x,(widget.width-widget.stripWidth)/2),"Strip is centered inside the available gap");
          check(closeEnough(widget.viewportWidth,widget.capacity-widget.arrowSize*2),"Arrow space reserved outside viewport");
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
          check(writes[0].name==="io.github.mapleroyal.layout-strip" && writes[0].entry.arrowMode==="click","Click persistence passes correct id and mode");
          move(rightArrow,rightArrow.width/2,rightArrow.height/2);
          heldOffset=widget.scrollOffset;
          break;
        case 3:
          check(closeEnough(widget.scrollOffset,heldOffset),"Click mode does not scroll on hover");
          check(events.mousePress(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.LeftButton,Qt.NoModifier,1),"QTest click hold press delivered");
          break;
        case 4:
          check(widget.scrollDirection===1 && widget.scrollOffset>heldOffset+10,"Holding click scrolls continuously");
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
          // Close before mapping the focus-taking popup: validate its event
          // path without changing the user's active window or desktop focus.
          widget.chooseMode("hover");
          events.mouseRelease(rightArrow,rightArrow.width/2,rightArrow.height/2,Qt.RightButton,Qt.NoModifier,1);
          check(widget.arrowMode==="hover" && !widget.menuOpen && writes.length===2,"Popup selection restores exclusive hover mode");
          check(writes[1].name==="io.github.mapleroyal.layout-strip" && writes[1].entry.arrowMode==="hover","Hover persistence passes correct id and mode");
          away();
          move(rightArrow,rightArrow.width/2,rightArrow.height/2);
          check(widget.hoverArmed && widget.scrollDirection===1,"Fresh hover re-arms scrolling after menu closes");
          away();
          widget.applySnapshot(harness.snapshot(12,11,1));
          break;
        case 9:
          check(closeEnough(widget.scrollOffset,widget.maximumOffset),"New focus reveals last column");
          var registeredTiles=fakeBar.clickTargets.filter(function(target){return target.objectName==="layoutTile";});
          check(registeredTiles.length>0 && registeredTiles.every(function(tile){return tile.interactive;}),"Only visible tiles are registered for popup forwarding");
          check(registeredTiles.every(function(tile){return tile.x>=widget.scrollOffset-0.5 && tile.x+tile.width<=widget.scrollOffset+widget.viewportWidth+0.5;}),"Forwarded tile hitboxes stay inside viewport");
          var partial=allTiles().filter(function(tile){return tile.x<widget.scrollOffset && tile.x+tile.width>widget.scrollOffset;})[0];
          check(!!partial && fakeBar.clickTargets.indexOf(partial)<0,"Partially visible tile is excluded from forwarded hitboxes");
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
          check(closeEnough(widget.stripWidth,widget.naturalWidth),"Short strip keeps natural width");
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
          check(choices.length===4,"Mapped popup has four options in two groups");
          check(choices.every(function(option){return option.y+option.height<=keys.height;}),"Mode choices fit within popup content bounds");
          check(widget.menuItemChecked(0) && !widget.menuItemChecked(1) && widget.menuItemChecked(2) && !widget.menuItemChecked(3),"Scroll and appearance groups each have exactly one selected choice");
          test.stop();
          card.grabToImage(function(result){
            check(result.saveToFile(Qt.resolvedUrl("mode-popup.png").toString().replace("file://","")),"Mapped mode popup image saved");
            var clickOption=harness.optionHit(choices.filter(function(option){return option.modelData==="Scroll on click";})[0]);
            check(events.mouseClick(clickOption,clickOption.width/2,clickOption.height/2,Qt.LeftButton,Qt.NoModifier,1),"QTest mapped popup choice click delivered");
            check(widget.arrowMode==="click" && !widget.menuOpen,"Clicking actual popup option switches and dismisses");
            test.start();
          });
          break;
        case 13:
          widget.applySnapshot(harness.snapshot(3,1,4));
          widget.chooseIndication("tiles");
          Style.cornerRadius=12;
          break;
        case 14:
          check(widget.indicationMode==="tiles" && !widget.overflow,"Three tiled width sizes fit without arrows");
          var paint=harness.surfaces();
          check(paint.length===3 && Math.abs(paint[1].width/paint[0].width-1.5)<0.001 && Math.abs(paint[2].width/paint[0].width-2)<0.001,"Painted tile widths have exact 1:1.5:2 ratios");
          check(paint.every(function(surface){return closeEnough(surface.radius,Math.min(Style.cornerRadius,Style.space(4))) && surface.radius<surface.height/2;}),"Rounded theme produces modest rounded-square tile corners");
          check(harness.underlines().every(function(line){return !line.visible;}),"Tile mode paints no underlines");
          check(Math.abs(paint[0].color.a-paint[1].color.a*0.25)<0.006 && Math.abs(paint[2].color.a-paint[0].color.a)<0.006,"Inactive tiles use one quarter of focused fill alpha");
          check(paint[1].color.a>=0.298 && paint[0].color.a>=0.073,"Active and inactive tiles retain visible translucent fills");
          check(allTiles().every(function(tile){var icon=tile.children.filter(function(child){return "sourceSize" in child;})[0];return icon.width===widget.iconSize && icon.height===widget.iconSize && closeEnough(icon.x,(tile.width-icon.width)/2) && closeEnough(icon.y,(tile.height-icon.height)/2);}),"Tile icons remain normalized and centered in both axes");
          var saved=writes[writes.length-1];
          check(saved.name==="io.github.mapleroyal.layout-strip" && saved.entry.indicationMode==="tiles" && saved.entry.arrowMode===widget.arrowMode,"Tiles selection persists while preserving arrow mode");
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
          check(!widget.overflow,"Appearance menu access tested without overflow arrows");
          check(events.mouseClick(first,first.width/2,first.height/2,Qt.RightButton,Qt.NoModifier,1),"QTest right-click on app icon delivered");
          check(widget.menuOpen && widget.menuAnchor===first,"Right-click app icon opens shared menu without arrows");
          if(!capturePopup) {widget.chooseIndication("tiles");finish();}
          break;
        case 19:
          var tileChoice=optionHit(options().filter(function(option){return option.modelData==="Tiles";})[0]);
          check(events.mouseClick(tileChoice,tileChoice.width/2,tileChoice.height/2,Qt.LeftButton,Qt.NoModifier,1),"QTest actual Tiles choice click delivered");
          check(widget.indicationMode==="tiles" && !widget.menuOpen,"Actual appearance popup choice changes mode and dismisses");
          check(!widget.menuItemChecked(2) && widget.menuItemChecked(3),"Appearance radio choices remain exclusive after selection");
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
  Timer { interval:10000; running:true; onTriggered:{console.error("HARNESS_TIMEOUT");Qt.quit();} }
}
