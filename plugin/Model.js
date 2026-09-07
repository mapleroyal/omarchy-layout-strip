function sizeFactor(size) {
  return size === "large" ? 2 : size === "medium" ? 1.5 : 1;
}

function validAddress(address) { return /^0x[0-9a-f]+$/i.test(String(address || "")); }

function widthRatio(value) {
  var ratio = Number(value);
  return isFinite(ratio) && ratio > 0 ? Math.min(0.85, ratio) : 0.85;
}

// Resolve an insertion boundary against stable identities. Keeping the source
// in the preview row avoids changing the pointer's coordinates mid-drag.
function dropTarget(columns, widths, gap, source, point) {
  if (columns.length < 2 || !isFinite(point)) return null;
  var position = 0, boundary = columns.length, sourceIndex = -1;
  for (var i = 0; i < columns.length; i++) {
    if (columns[i].address === source) sourceIndex = i;
    if (boundary === columns.length && point < position + widths[i] / 2) boundary = i;
    position += widths[i] + gap;
  }
  if (sourceIndex < 0) return null;
  var targetIndex = boundary < columns.length ? boundary : columns.length - 1;
  var side = boundary < columns.length ? "before" : "after";
  var changed = boundary !== sourceIndex && boundary !== sourceIndex + 1;
  var marker = 0;
  for (var j = 0; j < boundary; j++) marker += widths[j] + gap;
  marker = boundary === 0 ? 0 : marker - gap / 2;
  return {address: columns[targetIndex].address, side: side, changed: changed, position: marker, boundary: boundary};
}

function clampOffset(offset, contentWidth, viewportWidth) {
  return Math.max(0, Math.min(offset, Math.max(0, contentWidth - viewportWidth)));
}

function revealOffset(offset, viewportWidth, start, width, contentWidth) {
  // In a narrow strip a large column cannot fit in full. Center its icon
  // instead of exposing only the padding at the right edge of its tile.
  if (width > viewportWidth) return clampOffset(start + (width - viewportWidth) / 2, contentWidth, viewportWidth);
  var next = offset;
  if (start < offset) next = start;
  else if (start + width > offset + viewportWidth) next = start + width - viewportWidth;
  return clampOffset(next, contentWidth, viewportWidth);
}

// Keep horizontal touchpad events in their native direction; a vertical wheel
// moves the strip left on up and right on down. Pixel deltas remain continuous.
function wheelStep(pixelX, pixelY, angleX, angleY, inverted, mouse, step) {
  var horizontal = Math.abs(pixelX) > Math.abs(pixelY) ||
    (!pixelX && !pixelY && Math.abs(angleX) > Math.abs(angleY));
  if (horizontal) return pixelX ? -pixelX : -angleX / 120 * step;
  var delta = pixelY ? -pixelY : -angleY / 120 * step;
  return mouse && inverted ? -delta : delta;
}
