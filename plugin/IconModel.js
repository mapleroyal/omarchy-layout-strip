// Desktop launch metadata -> icon names. This never executes desktop commands.
function tokens(command) {
  var result = [], value = "", quote = "", escaped = false, started = false;
  for (var i = 0; i < command.length; i++) {
    var character = command.charAt(i);
    if (escaped) { value += character; escaped = false; started = true; }
    else if (character === "\\") { escaped = true; started = true; }
    else if (quote) {
      if (character === quote) quote = "";
      else value += character;
    } else if (character === '"' || character === "'") { quote = character; started = true; }
    else if (/\s/.test(character)) {
      if (started) { result.push(value); value = ""; started = false; }
    } else { value += character; started = true; }
  }
  if (escaped) value += "\\";
  if (started) result.push(value);
  return result;
}

function webappKey(url) {
  // Chromium URL app classes use host + '_' + path, with path separators
  // replaced by underscores. Query/fragment do not identify a desktop app.
  var match = /^https?:\/\/([^/?#]+)([^?#]*)/i.exec(String(url || ""));
  if (!match || match[1].indexOf("@") >= 0) return "";
  var host = match[1].toLowerCase().replace(/:\d+$/, "");
  var path = match[2] || "/";
  return host + "_" + path.replace(/\//g, "_");
}

function launchUrl(entry) {
  var args = entry.command && entry.command.length ? Array.from(entry.command)
    : tokens(String(entry.execString || ""));
  for (var i = 0; i < args.length; i++) {
    var arg = String(args[i]);
    var basename = arg.slice(arg.lastIndexOf("/") + 1);
    if (basename === "omarchy-launch-webapp") return String(args[i + 1] || "");
    if (arg.indexOf("--app=") === 0) return arg.slice(6);
    if (arg === "--app") return String(args[i + 1] || "");
  }
  return "";
}

function buildIndex(entries) {
  var exact = Object.create(null), webapps = Object.create(null);
  var sorted = Array.from(entries || []).slice().sort(function(a, b) {
    return String(a.id || "").localeCompare(String(b.id || ""));
  });
  for (var i = 0; i < sorted.length; i++) {
    var entry = sorted[i];
    var icon = String(entry.icon || "");
    if (!icon) continue;
    var id = String(entry.id || "").replace(/\.desktop$/, "");
    if (id && exact[id.toLowerCase()] === undefined) exact[id.toLowerCase()] = icon;
    var startupClass = String(entry.startupClass || "");
    if (startupClass) exact[startupClass.toLowerCase()] = icon;
    var key = webappKey(launchUrl(entry));
    if (key && webapps[key] === undefined) webapps[key] = icon;
  }
  // Longest matches first: /foo and /foo-bar must not confuse a suffix with
  // a profile name. Exact URL path wins before a shorter candidate is tried.
  var keys = Object.keys(webapps).sort(function(a, b) { return b.length - a.length || a.localeCompare(b); });
  return {exact: exact, webapps: webapps, keys: keys};
}

function iconName(index, className) {
  var value = String(className || "");
  var exact = index.exact[value.toLowerCase()];
  if (exact) return exact;
  // Omarchy supports Chromium-family browsers. They retain Chromium's chrome-
  // prefix for URL app classes regardless of the selected browser executable.
  if (value.indexOf("chrome-") === 0) {
    var candidate = value.slice(7);
    for (var i = 0; i < index.keys.length; i++) {
      var key = index.keys[i];
      if (candidate === key || candidate.indexOf(key + "-") === 0) return index.webapps[key];
    }
  }
  return "";
}

if (typeof module !== "undefined") module.exports = {
  tokens: tokens, webappKey: webappKey, launchUrl: launchUrl,
  buildIndex: buildIndex, iconName: iconName
};
