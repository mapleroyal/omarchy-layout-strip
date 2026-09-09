// The only adapter to Omarchy's bar internals. Geometry and icon matching stay
// host-independent; missing optional capabilities must never throw from input.
function callable(object, name) {
  return !!object && typeof object[name] === "function";
}

function entryId(entry) {
  return typeof entry === "string" ? entry : String(entry && entry.id || "");
}

function hostEntryId(bar, entry) {
  return callable(bar, "entryId") ? bar.entryId(entry) : entryId(entry);
}

function configuredEntries(bar, region) {
  if (!bar) return [];
  var entries = callable(bar, "layoutEntries") ? bar.layoutEntries(region)
    : bar.layoutConfig && bar.layoutConfig[region];
  return Array.isArray(entries) ? entries : [];
}

// Omarchy 4.0.3 injects a scoped PluginBarApi rather than the host Bar. Read
// slot geometry from this surface's visual tree; keep all operations on the
// scoped API. Never recover the host or another plugin's service through it.
function surfaceSlots(surface) {
  var slots = [];
  function visit(item) {
    if (!item) return;
    if ("activeItem" in item && "moduleName" in item && "region" in item && "entry" in item) {
      slots.push(item);
      return; // Do not inspect widget internals or depend on our own width.
    }
    var children = item.children || [];
    for (var i = 0; i < children.length; i++) visit(children[i]);
  }
  visit(surface && surface.contentItem);
  return slots;
}

function moduleSlots(bar, surface) {
  return bar && Array.isArray(bar.moduleSlots) ? bar.moduleSlots : surfaceSlots(surface);
}

function centerAnchor(bar) {
  if (!bar) return "";
  if (typeof bar.centerAnchor === "string") return bar.centerAnchor;
  var config = bar.shell && bar.shell.barConfig;
  return String(config && config.centerAnchor || "");
}

function hidden(bar) {
  return !!bar && (bar.barHidden === true ||
    !!(bar.shell && bar.shell.bar && bar.shell.bar.barHidden === true));
}

function capabilities(bar, root, surface) {
  var slots = !!bar && (Array.isArray(bar.moduleSlots) || !!findSlot(root, bar, surface));
  var entries = !!bar && (callable(bar, "layoutEntries") || !!bar.layoutConfig);
  var windows = callable(bar, "targetBelongsToWindow") || callable(bar, "slotWindow");
  var shell = bar && bar.shell;
  var layout = slots && entries && windows;
  var settings = callable(shell, "updateEntryInline");
  var move = layout && (callable(bar, "dropBarModule") || callable(bar, "run"));
  var forwarding = callable(bar, "registerClickTarget") && callable(bar, "unregisterClickTarget");
  var warnings = [];
  if (!settings) warnings.push("This bar cannot save strip settings");
  if (!move) warnings.push("This bar cannot move the strip");
  if (!forwarding) warnings.push("This bar cannot forward clicks while another popup is open");
  return {layout: layout, settings: settings, move: move, forwarding: forwarding,
    icons: callable(appLibrary(bar), "iconSource"), services: callable(shell, "serviceFor"),
    error: layout ? "" : "Layout Strip requires the Omarchy bar layout API",
    warnings: warnings};
}

function belongsToSurface(bar, slot, surface) {
  if (!bar || !slot || !slot.activeItem || !surface) return false;
  if (callable(bar, "targetBelongsToWindow"))
    return bar.targetBelongsToWindow(slot.activeItem, surface);
  if (callable(bar, "slotWindow")) {
    var window = bar.slotWindow(slot);
    return callable(bar, "sameWindow") ? bar.sameWindow(window, surface) : window === surface;
  }
  return false;
}

function findSlot(root, bar, surface) {
  if (!root || !bar || !surface) return null;
  var slots = moduleSlots(bar, surface);
  for (var i = 0; i < slots.length; i++) {
    var slot = slots[i];
    if (slot && slot.activeItem === root && belongsToSurface(bar, slot, surface)) return slot;
  }
  return null;
}

function entryMatchScore(left, right) {
  if (left === undefined || right === undefined) return 0;
  if (left === right) return 2;
  // QML may wrap a JS entry when assigning it to a var property. Its immutable
  // config value is a second identity hint, before the occurrence-order fallback.
  try { return JSON.stringify(left) === JSON.stringify(right) ? 1 : 0; }
  catch (error) { return 0; }
}

function geometryInput(root, bar, surface, margin) {
  var input = {width: surface ? surface.width : 0, margin: margin,
    selfId: root ? root.moduleName : "", centerAnchor: centerAnchor(bar),
    sections: {left: [], center: [], right: []}};
  var slots = moduleSlots(bar, surface);
  // A missing/starting host must not allocate the entire bar as empty space.
  if (!bar || !slots.length) { input.width = 0; return input; }
  var used = [];
  var names = ["left", "center", "right"];
  for (var r = 0; r < names.length; r++) {
    var region = names[r];
    var entries = configuredEntries(bar, region);
    for (var e = 0; e < entries.length; e++) {
      var id = hostEntryId(bar, entries[e]);
      var found = -1;
      var bestScore = -1;
      if (id !== input.selfId) {
        for (var s = 0; s < slots.length; s++) {
          var slot = slots[s];
          if (used.indexOf(s) >= 0 || !slot || slot.region !== region ||
              slot.moduleName !== id || !belongsToSurface(bar, slot, surface)) continue;
          var score = entryMatchScore(slot.entry, entries[e]);
          if (score > bestScore) { found = s; bestScore = score; }
          if (score === 2) break;
        }
      }
      var width = 0;
      if (found >= 0) {
        used.push(found);
        var match = slots[found];
        if (match.visible !== false && match.activeItem.visible !== false) {
          var value = Number(match.width);
          width = isFinite(value) && value > 0 ? value : 0;
        }
      }
      input.sections[region].push({id: id, width: width});
    }
  }
  return input;
}

function moveChoices(bar, selfId, region) {
  var choices = [{label: "‹ Back", action: "regions"}];
  var entries = configuredEntries(bar, region);
  var registry = bar && bar.barWidgetRegistry;
  var seen = [];
  for (var i = 0; i < entries.length; i++) {
    var id = hostEntryId(bar, entries[i]);
    // Omarchy's move API addresses the first occurrence of a widget ID. Avoid
    // offering indistinguishable destinations that all select that occurrence.
    if (!id || id === selfId || seen.indexOf(id) >= 0) continue;
    seen.push(id);
    var metadata = callable(registry, "metadataFor") ? registry.metadataFor(id) : null;
    var label = metadata && (metadata.displayName || metadata.name) || id;
    choices.push({label: "Before " + label, action: "place", value: id});
  }
  choices.push({label: "At end", action: "place", value: ""});
  return choices;
}

function persistSetting(bar, moduleName, entry) {
  if (!callable(bar && bar.shell, "updateEntryInline"))
    return {ok: false, error: "This bar cannot save strip settings"};
  try { return {ok: true, changed: bar.shell.updateEntryInline(moduleName, entry) !== false}; }
  catch (error) { return {ok: false, error: "Could not save strip settings: " + String(error)}; }
}

function moveWidget(root, bar, surface, region, beforeId) {
  var slot = findSlot(root, bar, surface);
  if (!slot || ["left", "center", "right"].indexOf(region) < 0)
    return {ok: false, error: "This bar cannot move the strip"};
  try {
    if (callable(bar, "dropBarModule"))
      return {ok: true, changed: bar.dropBarModule(slot, region, beforeId) === true};
    if (callable(bar, "run")) {
      var entries = configuredEntries(bar, region);
      if (beforeId && !entries.some(function(entry) { return entryId(entry) === beforeId; }))
        return {ok: false, error: "The destination widget is no longer in this section"};
      var command = "omarchy bar move " + shellQuote(root.moduleName) + " --section " + shellQuote(region);
      command += beforeId ? " --before " + shellQuote(beforeId)
        : " --index " + entries.filter(function(entry) { return entryId(entry) !== root.moduleName; }).length;
      bar.run(command);
      // The CLI saves asynchronously; shell.json's watcher applies the move.
      return {ok: true, changed: false, pending: true};
    }
    return {ok: false, error: "This bar cannot move the strip"};
  }
  catch (error) { return {ok: false, error: "Could not move the strip: " + String(error)}; }
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function registerClickTarget(bar, target) {
  if (!target || !callable(bar, "registerClickTarget") || !callable(bar, "unregisterClickTarget")) return false;
  bar.registerClickTarget(target);
  return true;
}

function unregisterClickTarget(bar, target) {
  if (!target || !callable(bar, "unregisterClickTarget")) return false;
  bar.unregisterClickTarget(target);
  return true;
}

function service(bar, id) {
  var shell = bar && bar.shell;
  return callable(shell, "serviceFor") ? shell.serviceFor(id) : null;
}

function appLibrary(bar) {
  return bar && bar.shell ? bar.shell.appLibrary || null : null;
}

if (typeof module !== "undefined") module.exports = {
  capabilities: capabilities, configuredEntries: configuredEntries, findSlot: findSlot,
  geometryInput: geometryInput, moveChoices: moveChoices, persistSetting: persistSetting,
  moveWidget: moveWidget, registerClickTarget: registerClickTarget,
  unregisterClickTarget: unregisterClickTarget, service: service, appLibrary: appLibrary,
  hidden: hidden
};
