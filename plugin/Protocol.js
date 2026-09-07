// Typed Lua RPC encoding. Arguments are never interpreted by a shell.
var VERSION = 2;

function luaString(value) {
  if (typeof value !== "string") throw new Error("Expected a string");
  var bytes = [];
  for (var i = 0; i < value.length; i++) {
    var c = value.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      var next = value.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) throw new Error("Invalid Unicode string");
      c = 0x10000 + ((c - 0xd800) << 10) + next - 0xdc00;
    } else if (c >= 0xdc00 && c <= 0xdfff) throw new Error("Invalid Unicode string");
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) bytes.push(0xc0 | c >> 6, 0x80 | c & 63);
    else if (c < 0x10000) bytes.push(0xe0 | c >> 12, 0x80 | c >> 6 & 63, 0x80 | c & 63);
    else bytes.push(0xf0 | c >> 18, 0x80 | c >> 12 & 63, 0x80 | c >> 6 & 63, 0x80 | c & 63);
  }
  return '"' + bytes.map(function(b) { return "\\" + ("00" + b).slice(-3); }).join("") + '"';
}

function monitor(value) {
  if (typeof value !== "string" || !value.length || value.length > 512 || value.indexOf("\0") >= 0)
    throw new Error("A valid monitor name is required");
  return luaString(value);
}
function address(value) {
  if (typeof value !== "string" || !/^0x[0-9a-f]+$/i.test(value)) throw new Error("Invalid window address");
  return luaString(value.toLowerCase());
}
function number(value) {
  if (typeof value !== "number" || !isFinite(value)) throw new Error("A finite number is required");
  return String(value);
}
function workspace(value) {
  if (!Number.isSafeInteger(value)) throw new Error("A workspace ID is required");
  return String(value);
}
function command(invocation) {
  var failure = JSON.stringify({ok:false,protocolVersion:VERSION,error:"Layout strip backend needs installation or upgrade (protocol 2)"});
  return ["hyprctl", "repl", "local api = omarchy_tape_bar; if not api or api.protocol_version ~= " + VERSION
    + " then return " + luaString(failure) + " end; return api." + invocation];
}
function snapshots(monitors) {
  if (!Array.isArray(monitors) || !monitors.length) throw new Error("No displayed monitors");
  return command("snapshot_all({" + monitors.map(monitor).join(",") + "})");
}
function regions(values, owner) {
  if (!Array.isArray(values)) throw new Error("Invalid protection regions");
  var entries = values.map(function(r) {
    var rect = [r.x, r.y, r.width, r.height];
    rect.forEach(number);
    if (!((r.width > 0 && r.height > 0) || (r.width === 0 && r.height === 0))) throw new Error("Invalid region dimensions");
    return "{monitor=" + monitor(r.monitor) + ",x=" + number(r.x) + ",y=" + number(r.y)
      + ",width=" + number(r.width) + ",height=" + number(r.height) + "}";
  });
  return command("protect_regions({" + entries.join(",") + "}," + luaString(owner) + ")");
}
function parseAction(args) {
  if (!Array.isArray(args) || args.length < 3) throw new Error("Invalid action");
  var action = args[1];
  if (["focus", "close", "reorder"].indexOf(action) < 0) throw new Error("Unknown action");
  var fields = {};
  for (var i = 3; i < args.length; i += 2) {
    var key = args[i];
    if (["--workspace", "--monitor", "--target", "--side"].indexOf(key) < 0 || fields[key] !== undefined || i + 1 >= args.length)
      throw new Error("Invalid action argument");
    fields[key] = args[i + 1];
  }
  var id = Number(fields["--workspace"]);
  workspace(id);
  monitor(fields["--monitor"]);
  address(args[2]);
  if (fields["--workspace"] === undefined || String(fields["--workspace"]).trim() === "") throw new Error("Missing workspace");
  var call = action + "(" + address(args[2]);
  if (action === "reorder") {
    if (["before", "after"].indexOf(fields["--side"]) < 0) throw new Error("Invalid reorder side");
    call += "," + address(fields["--target"]) + "," + luaString(fields["--side"]);
  } else if (fields["--target"] !== undefined || fields["--side"] !== undefined) throw new Error("Unexpected reorder arguments");
  call += "," + workspace(id) + "," + monitor(fields["--monitor"]) + ")";
  return {kind:action,workspaceId:id,monitorName:fields["--monitor"],command:command(call)};
}
function reply(text) {
  var data;
  try { data = JSON.parse(text); } catch (e) { throw new Error("Layout backend returned an invalid response"); }
  if (!data || typeof data.ok !== "boolean") throw new Error("Layout backend returned an invalid response");
  if (data.protocolVersion !== VERSION) throw new Error("Layout backend protocol mismatch; reinstall matching components");
  return data;
}
if (typeof module !== "undefined") module.exports = {VERSION:VERSION,luaString:luaString,command:command,
  snapshots:snapshots,regions:regions,parseAction:parseAction,reply:reply};
