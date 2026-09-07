import QtQuick
import Quickshell
import "IconModel.js" as IconModel

// One instance belongs to the shared service, never to individual delegates.
// Cache icon names, not resolved paths: AppLibrary.iconSource must remain in
// each live image binding so its icon-index/theme updates can invalidate it.
QtObject {
  id: root
  property var entries: DesktopEntries.applications.values
  readonly property var index: IconModel.buildIndex(entries)
  property var resolvedNames: Object.create(null)
  onIndexChanged: resolvedNames = Object.create(null)

  function iconFor(className, library) {
    var key = String(className || "");
    var cache = resolvedNames;
    var name = cache[key];
    if (name === undefined) {
      name = IconModel.iconName(index, key);
      if (!name) {
        var entry = DesktopEntries.heuristicLookup(key);
        name = entry && entry.icon ? entry.icon : key;
      }
      cache[key] = name;
    }
    if (library && typeof library.iconSource === "function") return library.iconSource(name);
    return Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true);
  }

  function sourceFor(className, library) { return iconFor(className, library); }
}
