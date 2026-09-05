function sizeFactor(size) {
  return size === "large" ? 2 : size === "medium" ? 1.5 : 1;
}

function clampOffset(offset, contentWidth, viewportWidth) {
  return Math.max(0, Math.min(offset, Math.max(0, contentWidth - viewportWidth)));
}

function revealOffset(offset, viewportWidth, start, width, contentWidth) {
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
