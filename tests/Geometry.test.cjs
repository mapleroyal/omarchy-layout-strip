'use strict';

const assert = require('node:assert/strict');
const Geometry = require('../plugin/Geometry.js');
const Host = require('../plugin/HostAdapter.js');
let assertions = 0;
function check(value, message) { assert(value, message); assertions++; }
function equal(actual, expected) { assert.deepEqual(actual, expected); assertions++; }

const fixture = {
  width: 1440, margin: 8, selfId: 'strip', centerAnchor: 'clock',
  sections: {
    left: [{id: 'menu', width: 40}, {id: 'workspaces', width: 93}, {id: 'strip', width: 99999}],
    center: [{id: 'clock', width: 158}],
    right: [{id: 'status', width: 380}]
  }
};
equal(Geometry.measure(fixture), {allocation: 500, x: 141, centerX: 391, region: 'left', index: 2, anchored: true});
const noCenter = structuredClone(fixture);
noCenter.sections.center = [];
equal(Geometry.measure(noCenter).allocation, 911);
const crowded = structuredClone(fixture);
crowded.sections.left[0].width = 1000;
equal(Geometry.measure(crowded).allocation, 0);
equal(Geometry.measure({width: 1000, selfId: 'missing', sections: fixture.sections}).allocation, 0);
const concealedAnchor = structuredClone(fixture);
concealedAnchor.sections.center = [{id: 'before', width: 50}, {id: 'clock', width: 0}, {id: 'after', width: 100}];
equal(Geometry.measure(concealedAnchor).allocation, 529);

// Reproduce Omarchy's rows independently of the geometry implementation.
function placeRows(data, selfWidth) {
  const groups = {};
  for (const region of ['left', 'center', 'right']) {
    const entries = data.sections[region];
    const widths = entries.map(e => e.id === 'strip' ? selfWidth : e.width);
    const total = widths.reduce((a, b) => a + b, 0);
    let start = region === 'left' ? data.margin : region === 'right'
      ? data.width - data.margin - total : (data.width - total) / 2;
    if (region === 'center') {
      const anchor = entries.findIndex(e => e.id === data.centerAnchor);
      if (anchor >= 0)
        start = data.width / 2 - widths[anchor] / 2 - widths.slice(0, anchor).reduce((a, b) => a + b, 0);
    }
    const positions = widths.map((width, index) => ({id: entries[index].id,
      x: start + widths.slice(0, index).reduce((a, b) => a + b, 0), width}));
    groups[region] = {start, end: start + total, total, positions};
  }
  return groups;
}

// Fixed seed, bounded runtime. Exercise every possible slot in each generated
// layout, including center anchors before/after the strip and the strip itself.
let seed = 8125;
function random(maximum) { seed = (seed * 1664525 + 1013904223) >>> 0; return seed % maximum; }
for (let caseNumber = 0; caseNumber < 250; caseNumber++) {
  const data = {width: 700 + random(1800), margin: 8, selfId: 'strip', centerAnchor: 'clock', sections: {
    left: Array.from({length: random(5)}, (_, i) => ({id: 'l' + i, width: random(80)})),
    center: [{id: 'pre', width: random(50)}, {id: 'clock', width: 60 + random(110)}, {id: 'post', width: random(50)}],
    right: Array.from({length: random(10)}, (_, i) => ({id: 'r' + i, width: random(40)}))
  }};
  if (caseNumber % 3 === 1) data.centerAnchor = 'absent';
  if (caseNumber % 9 === 0) data.sections.center = [];
  for (const region of ['left', 'center', 'right']) {
    for (let index = 0; index <= data.sections[region].length; index++) {
      const candidate = structuredClone(data);
      candidate.sections[region].splice(index, 0, {id: 'strip', width: 10000});
      if (caseNumber % 7 === 0 && region === 'center') candidate.centerAnchor = 'strip';
      const result = Geometry.measure(candidate);
      const groups = placeRows(candidate, result.allocation);
      const actual = groups[region].positions.find(e => e.id === 'strip');
      check(Math.abs(actual.x - result.x) < .0001, 'Predicted position matches host row');
      const repeated = structuredClone(candidate);
      repeated.sections[region][index].width = result.allocation;
      equal(Geometry.measure(repeated), result);
      if (!result.allocation) continue;
      check(groups[region].start >= candidate.margin - .0001, 'Fits left screen margin');
      check(groups[region].end <= candidate.width - candidate.margin + .0001, 'Fits right screen margin');
      if (region === 'left' && groups.center.total)
        check(groups.left.end <= groups.center.start + .0001, 'Left allocation respects center');
      if (region === 'right' && groups.center.total)
        check(groups.center.end <= groups.right.start + .0001, 'Right allocation respects center');
      if (region === 'center') {
        check(groups.left.end <= groups.center.start + .0001, 'Center allocation respects left');
        check(groups.center.end <= groups.right.start + .0001, 'Center allocation respects right');
      }
      check(groups.left.end <= groups.right.start + .0001, 'Outer sections never overlap');
    }
  }
}

// Host adapter regression: identical module IDs on another monitor must not
// influence measurement; opacity-hidden widgets still reserve their full slot.
const screenA = {width: 1440};
const screenB = {width: 2560};
const widget = {moduleName: 'strip', visible: true, surface: screenA};
const otherWidget = {moduleName: 'strip', visible: true, surface: screenB};
function slot(id, region, width, surface, options = {}) {
  return {moduleName: id, region, width, visible: true,
    activeItem: {visible: true, surface, opacity: 1}, ...options};
}
const selfSlot = slot('strip', 'left', 99999, screenA, {activeItem: widget});
const foreignSlot = slot('strip', 'left', 1300, screenB, {activeItem: otherWidget});
const bar = {
  centerAnchor: 'clock',
  moduleSlots: [foreignSlot, slot('clock', 'center', 400, screenB),
    slot('menu', 'left', 40, screenA), slot('workspaces', 'left', 93, screenA),
    selfSlot, slot('clock', 'center', 158, screenA), slot('status', 'right', 380, screenA)],
  layoutEntries: region => fixture.sections[region],
  entryId: entry => entry.id,
  targetBelongsToWindow: (item, surface) => item.surface === surface,
  barWidgetRegistry: {metadataFor: id => ({clock: {displayName: 'Clock'}, status: {displayName: 'System status'}})[id]}
};
equal(Host.findSlot(widget, bar, screenA), selfSlot);
equal(Host.findSlot(widget, bar, screenB), null);
equal(Host.findSlot(otherWidget, bar, screenB), foreignSlot);
equal(Geometry.measure(Host.geometryInput(widget, bar, screenA, 8)), Geometry.measure(fixture));
const localClock = bar.moduleSlots.find(s => s.moduleName === 'clock' && s.activeItem.surface === screenA);
localClock.activeItem.opacity = 0;
equal(Geometry.measure(Host.geometryInput(widget, bar, screenA, 8)).allocation, 500);
localClock.activeItem.visible = false;
equal(Geometry.measure(Host.geometryInput(widget, bar, screenA, 8)).allocation, 911);
equal(Host.moveChoices(bar, 'strip', 'center'), [
  {label: '‹ Back', action: 'regions'},
  {label: 'Before Clock', action: 'place', value: 'clock'},
  {label: 'At end', action: 'place', value: ''}
]);
equal(Host.moveChoices(bar, 'strip', 'left'), [
  {label: '‹ Back', action: 'regions'},
  {label: 'Before menu', action: 'place', value: 'menu'},
  {label: 'Before workspaces', action: 'place', value: 'workspaces'},
  {label: 'At end', action: 'place', value: ''}
]);
equal(Host.moveChoices(null, 'strip', 'right'), [
  {label: '‹ Back', action: 'regions'}, {label: 'At end', action: 'place', value: ''}
]);
console.log(`Geometry: ${assertions} assertions passed`);
