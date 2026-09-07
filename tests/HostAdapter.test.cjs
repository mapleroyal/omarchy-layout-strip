'use strict';
const assert = require('node:assert/strict');
const Host = require('../plugin/HostAdapter.js');
const Geometry = require('../plugin/Geometry.js');
const surface = {width:1000};
const foreign = {width:2500};
const widget = {moduleName:'strip',visible:true,surface};
const entries = {left:[{id:'omarchy.spacer',size:10},{id:'strip'},{id:'omarchy.spacer',size:100}],
  center:[{id:'clock'}],right:[]};
function slot(entry, region, width, screen = surface, item = null) {
  return {entry, region, moduleName:entry.id, width, visible:true,
    activeItem:item || {surface:screen,visible:true}};
}
const first = slot(entries.left[0],'left',10);
const last = slot(entries.left[2],'left',100);
const self = slot(entries.left[1],'left',0,surface,widget);
const bar = {centerAnchor:'clock', layoutEntries:r=>entries[r],
  targetBelongsToWindow:(item,s)=>item.surface===s,
  moduleSlots:[slot(entries.left[0],'left',900,foreign),last,self,first,slot(entries.center[0],'center',100)]};
let input = Host.geometryInput(widget,bar,surface,8);
assert.deepEqual(input.sections.left.map(e=>e.width),[10,0,100], 'real entry identity survives reversed registration order and other monitors');
assert.equal(Geometry.measure(input).allocation,332);
assert.equal(Host.findSlot(widget,bar,surface),self);
assert.equal(Host.findSlot(widget,bar,foreign),null);

// Equal settings do not outrank actual per-entry identity (width may be dynamic).
const originalSize = entries.left[2].size;
entries.left[2].size = entries.left[0].size;
assert.deepEqual(Host.geometryInput(widget,bar,surface,8).sections.left.map(e=>e.width),[10,0,100]);
entries.left[2].size = originalSize;

// QML wrappers with equal config values still pair the right instances.
first.entry = structuredClone(entries.left[0]);
last.entry = structuredClone(entries.left[2]);
assert.deepEqual(Host.geometryInput(widget,bar,surface,8).sections.left.map(e=>e.width),[10,0,100]);
first.visible=false;
assert.deepEqual(Host.geometryInput(widget,bar,surface,8).sections.left.map(e=>e.width),[0,0,100]);
first.visible=true;
last.activeItem.opacity=0;
assert.equal(Geometry.measure(Host.geometryInput(widget,bar,surface,8)).allocation,332);

// Legacy/fake hosts without slot.entry retain occurrence order, never reuse a slot.
delete first.entry; delete last.entry;
bar.moduleSlots=[first,self,last,bar.moduleSlots.at(-1)];
assert.deepEqual(Host.geometryInput(widget,bar,surface,8).sections.left.map(e=>e.width),[10,0,100]);
assert.equal(Host.capabilities(bar).layout,true);
assert.equal(Host.capabilities(null).layout,false);
assert.match(Host.capabilities({}).error,/layout API/);
assert.equal(Host.persistSetting(bar,'strip',{}).ok,false);
assert.equal(Host.moveWidget(widget,bar,surface,'right','').ok,false);
assert.equal(Host.registerClickTarget(null,widget),false);
assert.equal(Host.unregisterClickTarget(null,widget),false);
assert.equal(Host.service(bar,'strip'),null);
assert.equal(Host.appLibrary(bar),null);

const events=[];
const library={iconSource:name=>name};
const backend={connected:true};
bar.shell={updateEntryInline:(id,entry)=>{events.push(['save',id,entry]); return true;},
  appLibrary:library,serviceFor:id=>id==='strip'?backend:null};
bar.dropBarModule=(source,region,before)=>{events.push(['move',source,region,before]);return true;};
bar.registerClickTarget=target=>events.push(['register',target]);
bar.unregisterClickTarget=target=>events.push(['unregister',target]);
assert.deepEqual(Host.capabilities(bar),{layout:true,settings:true,move:true,forwarding:true,icons:true,services:true,error:'',warnings:[]});
assert.equal(Host.appLibrary(bar),library);
assert.equal(Host.service(bar,'strip'),backend);
assert.equal(Host.persistSetting(bar,'strip',{widthRatio:.7}).ok,true);
assert.equal(Host.moveWidget(widget,bar,surface,'right','clock').changed,true);
assert.equal(Host.registerClickTarget(bar,widget),true);
assert.equal(Host.unregisterClickTarget(bar,widget),true);
assert.equal(events.length,4);
assert.equal(events[1][1],self);
assert.equal(Host.moveChoices(bar,'strip','left').filter(c=>c.value==='omarchy.spacer').length,1);
bar.shell.updateEntryInline=()=>{throw new Error('write denied');};
assert.match(Host.persistSetting(bar,'strip',{}).error,/write denied/);
bar.dropBarModule=()=>{throw new Error('removed');};
assert.match(Host.moveWidget(widget,bar,surface,'left','clock').error,/removed/);
console.log('HostAdapter: repeated instances, monitor isolation and capability/action checks passed');
