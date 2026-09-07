const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const P = require('../plugin/Protocol.js');

const strings = ['', 'eDP-1', 'a"; os.execute("touch should-not-exist"); --', '\0\n\r\t\\123',
  'snow 雪 café', '🎞️ Video', '$(false)`false`', '\u007f\u0080\u07ff\u0800\uffff'];
for (const value of strings) {
  const result = spawnSync('lua', ['-e', 'io.write(' + P.luaString(value) + ')']);
  assert.equal(result.status, 0, String(result.stderr));
  assert.deepEqual(result.stdout, Buffer.from(value, 'utf8'));
}
for (const value of ['\ud800', '\udc00', '\ud800x']) assert.throws(() => P.luaString(value));
for (const monitor of ['', '\0', 42]) assert.throws(() => P.snapshots([monitor]));
assert.throws(() => P.snapshots([]));
const focus = P.parseAction(['ignored', 'focus', '0xABCD', '--workspace', '-99', '--monitor', 'eDP-1']);
assert.equal(focus.kind, 'focus');
assert.equal(focus.workspaceId, -99);
assert.deepEqual(focus.command.slice(0, 2), ['hyprctl', 'repl']);
assert.ok(focus.command[2].includes(P.luaString('0xabcd')));
for (const args of [
 ['ignored', 'focus', '0x1'],
 ['ignored', 'focus', '0x1', '--workspace', '', '--monitor', 'eDP-1'],
 ['ignored', 'focus', '0x1', '--workspace', '1.5', '--monitor', 'eDP-1'],
 ['ignored', 'focus', '0x1', '--workspace', '1', '--monitor', 'eDP-1', '--monitor', 'DP-2'],
 ['ignored', 'focus', '0x1', '--workspace', '1', '--monitor', 'eDP-1', '--target', '0x2'],
 ['ignored', 'close', '0x1;bad()', '--workspace', '1', '--monitor', 'eDP-1'],
 ['ignored', 'reorder', '0x1', '--workspace', '1', '--monitor', 'eDP-1', '--target', '0x2', '--side', 'inside'],
 ['ignored', 'exec', '0x1', '--workspace', '1', '--monitor', 'eDP-1']
]) assert.throws(() => P.parseAction(args), JSON.stringify(args));
const reorder = P.parseAction(['ignored','reorder','0xA','--target','0xB','--side','after','--workspace','1','--monitor','DP-2']);
assert.equal(reorder.kind,'reorder');
for (const [width,height] of [[1,0],[-1,-1],[NaN,1],[Infinity,1]])
 assert.throws(() => P.regions([{monitor:'eDP-1',x:0,y:0,width,height}],'test'));
P.regions([{monitor:'eDP-1',x:-100,y:0,width:0,height:0}],'test');
P.regions([{monitor:'eDP-1',x:-100,y:0,width:100,height:26}],'test');
assert.throws(() => P.reply('not-json'));
assert.throws(() => P.reply('{"ok":true}'));
assert.throws(() => P.reply('{"ok":true,"protocolVersion":1}'));
assert.equal(P.reply('{"ok":false,"error":"Unavailable","protocolVersion":2}').error,'Unavailable');
// Guard mismatched installations before executing even a correctly typed action.
const guarded = spawnSync('lua',['-e',`omarchy_tape_bar={protocol_version=1,focus=function() error('MUST NOT RUN') end}; io.write((function() ${focus.command[2]} end)())`],{encoding:'utf8'});
assert.equal(guarded.status,0,guarded.stderr);
assert.equal(JSON.parse(guarded.stdout).ok,false);
console.log('Protocol encoding, injection boundaries, validation and version guard passed');
