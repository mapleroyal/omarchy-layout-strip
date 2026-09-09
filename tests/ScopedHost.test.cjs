'use strict';
const assert = require('node:assert/strict');
const Host = require('../plugin/HostAdapter.js');
const Geometry = require('../plugin/Geometry.js');
const entries = {left: [{id:'workspaces'}, {id:'strip'}], center:[{id:'clock'}], right:[]};
const surface = {width:1440,contentItem:{children:[]}};
const widget = {moduleName:'strip',visible:true,surface};
const ownSlot = {entry:entries.left[1],moduleName:'strip',region:'left',activeItem:widget};
Object.defineProperty(ownSlot,'width',{get(){ throw Error('must not read own width'); }});
Object.defineProperty(ownSlot,'children',{get(){ throw Error('must not traverse widget contents'); }});
const workspaceSlot = {entry:entries.left[0],moduleName:'workspaces',region:'left',width:130,
  activeItem:{visible:true,surface}};
const clockSlot = {entry:entries.center[0],moduleName:'clock',region:'center',width:220,
  activeItem:{visible:true,surface}};
surface.contentItem.children = [{children:[workspaceSlot,ownSlot]}, {children:[clockSlot]}];
const commands = [];
const bar = {layoutConfig:entries,shell:{barConfig:{centerAnchor:'clock'},bar:{barHidden:false},
  updateEntryInline:()=>true}, targetBelongsToWindow:(item,window)=>item.surface===window,
  run:command=>commands.push(command)};
assert.equal(Host.capabilities(bar,widget,surface).layout,true);
assert.equal(Host.capabilities(bar,widget,surface).move,true);
assert.equal(Host.findSlot(widget,bar,surface),ownSlot);
const measure = ()=>Geometry.measure(Host.geometryInput(widget,bar,surface,8));
assert.deepEqual(measure(),{allocation:472,x:138,centerX:374,region:'left',index:1,anchored:true});
workspaceSlot.width=160;
assert.equal(measure().allocation,442,'dynamic sibling width changes allocation');
clockSlot.activeItem=null;
assert.equal(measure().allocation,1264,'loading slot remains discoverable but has zero extent');
clockSlot.activeItem={visible:true,surface};
assert.equal(measure().allocation,442,'loader completion restores the clock boundary');
clockSlot.activeItem.visible=false;
assert.equal(measure().allocation,1264);
clockSlot.activeItem.visible=true;
const foreign={width:2000,contentItem:{children:[]}};
assert.equal(Host.findSlot(widget,bar,foreign),null);
assert.equal(Geometry.measure(Host.geometryInput(widget,bar,foreign,8)).allocation,0);
assert.equal(Host.hidden(bar),false);
bar.shell.bar.barHidden=true;
assert.equal(Host.hidden(bar),true);
assert.deepEqual(Host.moveWidget(widget,bar,surface,'center','clock'),{ok:true,changed:false,pending:true});
assert.equal(commands[0],"omarchy bar move 'strip' --section 'center' --before 'clock'");
assert.equal(Host.moveWidget(widget,bar,surface,'left','').ok,true);
assert.equal(commands[1],"omarchy bar move 'strip' --section 'left' --index 1");
assert.equal(Host.moveWidget(widget,bar,surface,'right; malicious','').ok,false);
assert.equal(Host.moveWidget(widget,bar,surface,'right','missing').ok,false);
widget.moduleName="strip'$(false)";
assert.equal(Host.moveWidget(widget,bar,surface,'right','').ok,true);
assert.equal(commands[2],"omarchy bar move 'strip'\\''$(false)' --section 'right' --index 0");
console.log('Scoped host: scene geometry, delayed loading, monitor isolation, hidden state and quoted placement passed');
