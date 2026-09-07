const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../plugin/Model.js'), 'utf8'), model);

// Every insertion gap maps to an addressed move. Removing and reinserting the
// source must preserve all other windows' relative order, including uneven
// column sizes and the two boundaries immediately surrounding the source.
const columns = ['0x1', '0x2', '0x3', '0x4'].map(address => ({address}));
const widths = [30, 44, 58, 30];
const gap = 4;
const points = [-20, 32, 80, 142, 190];
let cases = 0;
for (let sourceIndex = 0; sourceIndex < columns.length; sourceIndex++) {
  const source = columns[sourceIndex].address;
  for (let boundary = 0; boundary <= columns.length; boundary++) {
    const drop = model.dropTarget(columns, widths, gap, source, points[boundary]);
    assert.equal(drop.boundary, boundary);
    assert.equal(drop.changed, boundary !== sourceIndex && boundary !== sourceIndex + 1);
    assert.equal(drop.address, columns[Math.min(boundary, columns.length - 1)].address);
    assert.equal(drop.side, boundary < columns.length ? 'before' : 'after');
    if (drop.changed) {
      const other = columns.map(c => c.address).filter(address => address !== source);
      const targetIndex = other.indexOf(drop.address);
      assert.notEqual(targetIndex, -1, 'changed move must target a different column');
      const actual = [...other];
      actual.splice(targetIndex + (drop.side === 'after' ? 1 : 0), 0, source);
      const expected = columns.map(c => c.address);
      expected.splice(sourceIndex, 1);
      expected.splice(boundary - (sourceIndex < boundary ? 1 : 0), 0, source);
      assert.deepEqual(actual, expected);
      assert.deepEqual(actual.filter(address => address !== source), other);
    }
    cases++;
  }
}
assert.equal(model.dropTarget([], [], gap, '0x1', 0), null);
assert.equal(model.dropTarget(columns.slice(0, 1), [30], gap, '0x1', 10), null);
assert.equal(model.dropTarget(columns, widths, gap, '0xdead', 10), null);
assert.equal(model.dropTarget(columns, widths, gap, '0x1', NaN), null);

// Saved proportional widths tolerate malformed/old preferences and obey the
// agreed 85% maximum without introducing a hardcoded pixel limit.
for (const invalid of [undefined, null, '', 'bad', -1, 0, Infinity, NaN])
  assert.equal(model.widthRatio(invalid), 0.85);
assert.equal(model.widthRatio('0.62'), 0.62);
assert.equal(model.widthRatio(0.01), 0.01);
assert.equal(model.widthRatio(1), 0.85);
assert.equal(model.widthRatio(5), 0.85);

// Strip scrolling stays within its own viewport, and focus reveal makes only
// the smallest necessary adjustment. None of these helpers moves the desktop.
assert.equal(model.clampOffset(-20, 400, 200), 0);
assert.equal(model.clampOffset(240, 400, 200), 200);
assert.equal(model.clampOffset(20, 100, 200), 0);
assert.equal(model.revealOffset(80, 100, 90, 30, 400), 80);
assert.equal(model.revealOffset(80, 100, 40, 30, 400), 40);
assert.equal(model.revealOffset(80, 100, 160, 40, 400), 100);
assert.equal(model.revealOffset(0, 30, 60, 60, 400), 75);
assert.equal(model.revealOffset(150, 30, 60, 60, 400), 75);
assert.equal(model.wheelStep(20, 0, 0, 0, false, false, 48), -20);
assert.equal(model.wheelStep(0, 0, 0, 120, false, true, 48), -48);
assert.equal(model.wheelStep(0, 0, 0, -120, false, true, 48), 48);
assert.equal(model.wheelStep(0, 0, 0, 120, true, true, 48), 48);
console.log(`Layout model contracts passed (${cases} insertion cases plus widths/scrolling)`);
