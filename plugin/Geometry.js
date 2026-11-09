// Pure geometry for Omarchy's horizontal bar. Rows have zero spacing; the
// outer sections sit at `margin` and the middle uses a centered anchor or row.
// Only other widgets' widths participate in the allocation, so repeatedly
// measuring after this widget has been laid out cannot feed back on itself.

function positive(value) {
  var number = Number(value);
  return isFinite(number) && number > 0 ? number : 0;
}

function entryId(entry) {
  return typeof entry === "string" ? entry : String(entry && entry.id || "");
}

function sectionEntries(input, region) {
  var values = input.sections && input.sections[region];
  return Array.isArray(values) ? values : [];
}

function indexOfId(entries, id) {
  for (var i = 0; i < entries.length; i++)
    if (entryId(entries[i]) === id) return i;
  return -1;
}

function sum(entries, from, until, excludedId) {
  var total = 0;
  for (var i = from; i < until; i++) {
    var entry = entries[i];
    if (entryId(entry) !== excludedId) total += positive(entry && entry.width);
  }
  return total;
}

// Input: {width, margin, selfId, centerAnchor,
//         sections: {left: [{id,width}], center: [...], right: [...]}}.
// Preserve the configuration's entry order, including zero-width hidden
// widgets. `width` is the full slot extent, not painted icon width or opacity.
// Output: allocation is the stable host slot width. Place the interaction
// area at its center and apply the user's 0..0.85 fraction to allocation.
function measure(input) {
  input = input || {};
  if (input.splitCenter) return measureSplitCenter(input);
  var width = positive(input.width);
  var margin = Math.min(positive(input.margin), width / 2);
  var self = String(input.selfId || "");
  var left = sectionEntries(input, "left");
  var center = sectionEntries(input, "center");
  var right = sectionEntries(input, "right");
  var region = "";
  var selfIndex = -1;
  var sections = {left: left, center: center, right: right};
  var names = ["left", "center", "right"];
  for (var n = 0; n < names.length; n++) {
    var found = indexOfId(sections[names[n]], self);
    if (found >= 0) { region = names[n]; selfIndex = found; break; }
  }
  if (!self || !region || !width)
    return {allocation: 0, x: 0, centerX: 0, region: region, index: selfIndex, anchored: false};

  var leftWidth = sum(left, 0, left.length, self);
  var centerWidth = sum(center, 0, center.length, self);
  var rightWidth = sum(right, 0, right.length, self);
  var leftEnd = margin + leftWidth;
  var rightStart = width - margin - rightWidth;
  var anchorIndex = indexOfId(center, String(input.centerAnchor || ""));
  var anchored = anchorIndex >= 0;
  var anchorWidth = anchored && entryId(center[anchorIndex]) !== self
    ? positive(center[anchorIndex].width) : 0;
  var beforeWidth = anchored ? sum(center, 0, anchorIndex, self) : 0;
  var afterWidth = anchored ? sum(center, anchorIndex + 1, center.length, self) : 0;
  var centerStart = anchored ? width / 2 - anchorWidth / 2 - beforeWidth : (width - centerWidth) / 2;
  var centerEnd = anchored ? width / 2 + anchorWidth / 2 + afterWidth : (width + centerWidth) / 2;
  var hasCenterExtent = centerWidth > 0 || region === "center";
  var allocation = 0;
  var x = 0;

  if (region === "left") {
    var leftBoundary = hasCenterExtent ? Math.min(centerStart, rightStart) : rightStart;
    allocation = Math.max(0, leftBoundary - margin - leftWidth);
    x = margin + sum(left, 0, selfIndex, self);
  } else if (region === "right") {
    var rightBoundary = hasCenterExtent ? Math.max(centerEnd, leftEnd) : leftEnd;
    allocation = Math.max(0, width - margin - rightWidth - rightBoundary);
    x = width - margin - rightWidth - allocation + sum(right, 0, selfIndex, self);
  } else if (!anchored) {
    allocation = Math.max(0, 2 * Math.min(width / 2 - leftEnd, rightStart - width / 2) - centerWidth);
    x = (width - centerWidth - allocation) / 2 + sum(center, 0, selfIndex, self);
  } else if (selfIndex < anchorIndex) {
    allocation = Math.max(0, centerStart - leftEnd);
    x = centerStart - allocation + sum(center, 0, selfIndex, self);
  } else if (selfIndex > anchorIndex) {
    allocation = Math.max(0, rightStart - centerEnd);
    x = width / 2 + anchorWidth / 2 + sum(center, anchorIndex + 1, selfIndex, self);
  } else {
    allocation = Math.max(0, 2 * Math.min(width / 2 - leftEnd - beforeWidth,
      rightStart - width / 2 - afterWidth));
    x = (width - allocation) / 2;
  }

  return {allocation: allocation, x: x, centerX: x + allocation / 2,
    region: region, index: selfIndex, anchored: anchored};
}

// Current Omarchy centers the middle row as a group. Its two adjacent rows
// grow outwards, independently of that group. Ignore centerAnchor from older
// shell.json files: it no longer participates in the host's placement.
function measureSplitCenter(input) {
  var width = positive(input.width);
  var margin = Math.min(positive(input.margin), width / 2);
  var self = String(input.selfId || "");
  var names = ["left", "centerBegin", "center", "centerEnd", "right"];
  var sections = {}, widths = {}, region = "", index = -1;
  for (var n = 0; n < names.length; n++) {
    var name = names[n];
    sections[name] = sectionEntries(input, name);
    widths[name] = sum(sections[name], 0, sections[name].length, self);
    var found = indexOfId(sections[name], self);
    if (found >= 0) { region = name; index = found; }
  }
  if (!self || !region || !width)
    return {allocation: 0, x: 0, centerX: 0, region: region, index: index, anchored: false};

  var leftEnd = margin + widths.left;
  var rightStart = width - margin - widths.right;
  var centerStart = Math.round((width - widths.center) / 2);
  var centerEnd = centerStart + widths.center;
  var beginStart = centerStart - widths.centerBegin;
  var endEnd = centerEnd + widths.centerEnd;
  var hasCenter = widths.centerBegin + widths.center + widths.centerEnd > 0 ||
    ["centerBegin", "center", "centerEnd"].indexOf(region) >= 0;
  var before = sum(sections[region], 0, index, self);
  var allocation = 0, x = 0;
  if (region === "left") {
    allocation = Math.max(0, Math.min(hasCenter ? beginStart : rightStart, rightStart) - leftEnd);
    x = margin + before;
  } else if (region === "right") {
    allocation = Math.max(0, rightStart - Math.max(hasCenter ? endEnd : leftEnd, leftEnd));
    x = rightStart - allocation + before;
  } else if (region === "centerBegin") {
    allocation = beginStart + before > rightStart ? 0 : Math.max(0, beginStart - leftEnd);
    x = beginStart - allocation + before;
  } else if (region === "centerEnd") {
    allocation = centerEnd + before < leftEnd ? 0 : Math.max(0, rightStart - endEnd);
    x = centerEnd + before;
  } else {
    allocation = Math.max(0, 2 * Math.min(width / 2 - leftEnd - widths.centerBegin,
      rightStart - width / 2 - widths.centerEnd) - widths.center);
    // The host rounds the centered row's origin to a whole logical pixel.
    // Leave enough room when a sibling has a fractional implicit width.
    var start = Math.round((width - widths.center - allocation) / 2);
    var excess = Math.max(leftEnd + widths.centerBegin - start,
      start + widths.center + allocation + widths.centerEnd - rightStart, 0);
    if (excess > 0) allocation = Math.max(0, allocation - 2 * Math.ceil(excess));
    x = Math.round((width - widths.center - allocation) / 2) + before;
  }
  return {allocation: allocation, x: x, centerX: x + allocation / 2,
    region: region, index: index, anchored: false};
}

// Host introspection lives in HostAdapter.js; the layout policy is pure.
if (typeof module !== "undefined") module.exports = {measure: measure};
