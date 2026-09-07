"""Behavioral integration against two outputs in an owned, private compositor.

Never connects to the login compositor. Backend startup failure is a test failure,
not permission to fall back to a visible nested window.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

PARSER = argparse.ArgumentParser(description=__doc__)
PARSER.add_argument('--plugin', required=True, type=Path)
PARSER.add_argument('--output', required=True, type=Path)
PARSER.add_argument('--parent-display', type=Path, help='Explicit private headless compositor socket; never the login socket')
ARGS = PARSER.parse_args()
REPO = Path(__file__).resolve().parents[2]
OUT = ARGS.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
runtime = Path(tempfile.mkdtemp(prefix='ls-native-'))
runtime.chmod(0o700)
env = os.environ.copy()
for name in ['WAYLAND_DISPLAY','WAYLAND_SOCKET','HYPRLAND_INSTANCE_SIGNATURE','DISPLAY','I3SOCK','SWAYSOCK']:
    env.pop(name, None)
if ARGS.parent_display:
    parent=ARGS.parent_display.resolve()
    assert parent.is_socket() and parent.is_absolute()
    login_runtime=Path(os.environ.get('XDG_RUNTIME_DIR','/run/user/'+str(os.getuid())))
    assert not parent.is_relative_to(login_runtime), 'Refusing login runtime socket'
    env['WAYLAND_DISPLAY']=str(parent)
env.update(XDG_RUNTIME_DIR=str(runtime), HYPRLAND_NO_CRASHREPORTER='1',
           AQ_DRM_DEVICES='/dev/dri/renderD128', AQ_NO_KMS_REQUIRE='1')
config = OUT / 'hyprland.lua'
config.write_text('''
hl.monitor({output="HEADLESS-1", mode="1440x900@60", position="0x0", scale=1})
hl.monitor({output="HEADLESS-2", mode="1440x900@60", position="1440x0", scale=1})
hl.monitor({output="",disabled=true})
hl.config({general={layout="scrolling",gaps_in=3,gaps_out=6,border_size=2},
 scrolling={column_width=0.5,fullscreen_on_one_column=false,follow_focus=true,focus_fit_method=1},
 input={follow_mouse=0},animations={enabled=false},
 misc={disable_hyprland_logo=true,disable_splash_rendering=true}})
hl.plugin.load('''+json.dumps(str(ARGS.plugin.resolve()))+''')
local Tape = dofile('''+json.dumps(str(REPO/'backend/tape.lua'))+''')
local Bar = dofile('''+json.dumps(str(REPO/'backend/tape-bar.lua'))+''')
local Bootstrap = dofile('''+json.dumps(str(REPO/'backend/tape-bootstrap.lua'))+''')
_testTape = Tape.new(hl)
_testIntegration = Bootstrap.new(hl,_testTape,Bar)
omarchy_tape_bar = _testIntegration.bar
_focusEvents=0
_focusListener=hl.on("window.active",function() _focusEvents=_focusEvents+1 end)
''')
compositor = None
clients = []
cases = []

def ctl(*args):
    assert env.get('HYPRLAND_INSTANCE_SIGNATURE')
    assert env['HYPRLAND_INSTANCE_SIGNATURE'] != os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    assert Path(env['XDG_RUNTIME_DIR']) == runtime
    completed = subprocess.run(['hyprctl',*args],env=env,capture_output=True,text=True,timeout=10)
    if completed.returncode: raise RuntimeError(completed.stdout+completed.stderr)
    return completed.stdout.strip()

def evaluate(code): return ctl('repl',code)
def reply(expr): return json.loads(evaluate('return '+expr))
def windows(): return {w['title']:w for w in json.loads(ctl('-j','clients'))}
def addr(title): return windows()[title]['address']
def active(): return json.loads(ctl('-j','activewindow')).get('address')
def focus(title): evaluate('return hl.dispatch(hl.dsp.focus({window="address:'+addr(title)+'"}))')
def camera(workspace=1,monitor='HEADLESS-1'):
    return json.loads(evaluate('local r=hl.plugin.tape.snapshot('+str(workspace)+','+json.dumps(monitor)+''');return string.format('{"ok":%s,"offset":%f,"width":%f}',tostring(r.ok),r.offset or 0,r.width or 0)'''))
def pan_to(offset,workspace=1,monitor='HEADLESS-1'):
    before=camera(workspace,monitor); assert before['ok'],before
    result=evaluate('return hl.plugin.tape.pan('+str(before['offset']-offset)+',true,'+str(workspace)+','+json.dumps(monitor)+').ok')
    assert result=='true',result
    assert abs(camera(workspace,monitor)['offset']-offset)<.1

def wait_for(predicate):
    for _ in range(100):
        if predicate(): return
        time.sleep(.05)
    raise AssertionError('private compositor condition timed out')

def launch(title):
    with (OUT/f'client-{title}.log').open('w') as log:
        clients.append(subprocess.Popen(['foot','--config=/dev/null',f'--app-id=layout-strip-test-{title}',f'--title={title}','/usr/bin/sleep','300'],env=env,stdout=log,stderr=subprocess.STDOUT))
    wait_for(lambda:title in windows())

def close_preserving(target,anchor,workspace=1,monitor='HEADLESS-1'):
    before_windows=windows()
    before=before_windows[anchor]['at'][0]
    before_camera=camera(workspace,monitor)
    focused=active()
    result=reply('omarchy_tape_bar.close('+json.dumps(addr(target))+','+str(workspace)+','+json.dumps(monitor)+')')
    assert result['ok'],result
    wait_for(lambda:target not in windows())
    time.sleep(.08)
    after=windows()[anchor]['at'][0]
    if abs(before-after)>2:
        (OUT/'close-diagnostic.json').write_text(json.dumps({'target':target,'anchor':anchor,'before':before_windows,'after':windows(),'cameraBefore':before_camera,'cameraAfter':camera(workspace,monitor)},indent=2))
    assert abs(before-after)<=2,(target,anchor,before,after)
    assert active()==focused,(focused,active())
    cases.append({'case':'close_preserves_anchor','target':target,'anchor':anchor,'before':before,'after':after})

try:
    with (OUT/'compositor.log').open('w') as log:
        compositor=subprocess.Popen(['Hyprland','--config',str(config)],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    for _ in range(100):
        if compositor.poll() is not None: raise RuntimeError('private compositor failed; see '+str(OUT/'compositor.log'))
        sockets=list((runtime/'hypr').glob('*/.socket.sock'))
        if sockets:
            env['HYPRLAND_INSTANCE_SIGNATURE']=sockets[0].parent.name
            displays=[p.name for p in runtime.glob('wayland-*') if not p.name.endswith('.lock')]
            if displays: env['WAYLAND_DISPLAY']=displays[0];break
        time.sleep(.1)
    else: raise RuntimeError('private compositor startup timeout')
    for monitor in ['HEADLESS-1','HEADLESS-2']: ctl('output','create','headless',monitor)
    assert not ctl('configerrors'),ctl('configerrors')
    monitors=json.loads(ctl('-j','monitors','all'))
    assert all(m['name'].startswith(('HEADLESS-','WAYLAND-')) for m in monitors),monitors
    active_monitors=json.loads(ctl('-j','monitors'))
    assert len(active_monitors)==2 and all(m['name'].startswith('HEADLESS-') for m in active_monitors),active_monitors
    (OUT/'monitors.json').write_text(json.dumps(monitors,indent=2))
    evaluate('return hl.dispatch(hl.dsp.focus({monitor="HEADLESS-1"}))')
    evaluate('return hl.dispatch(hl.dsp.focus({workspace="1"}))')
    for title in 'ABCDEFG': launch(title)
    evaluate('return hl.dispatch(hl.dsp.focus({monitor="HEADLESS-2"}))')
    evaluate('return hl.dispatch(hl.dsp.focus({workspace="2"}))')
    for title in 'XYZ': launch(title)
    state=reply('omarchy_tape_bar.snapshot_all({"HEADLESS-1","HEADLESS-2"})')
    assert state['protocolVersion']==2 and len(state['snapshots'])==2,state
    assert all(s['nativeProtocolVersion']==2 and s['capabilities']['addressedCamera'] for s in state['snapshots'])
    cases.append({'case':'protocol_v2_bulk_snapshot','monitors':2})
    focused=active(); events=evaluate('return _focusEvents')
    width=camera()['width'];pan_to(width/2)
    assert active()==focused and evaluate('return _focusEvents')==events
    cases.append({'case':'addressed_pan_nonfocused_monitor','offset':camera()['offset']})
    # Use an interior visible anchor: becoming the first/last native column
    # changes Hyprland's boundary gap by 3px even with an identical camera.
    close_preserving('A','C')
    close_preserving('G','C')
    focus('F')
    evaluate('return hl.dispatch(hl.dsp.window.float({action="set"}))')
    width=camera()['width'];pan_to(width/2)
    assert active()==addr('F')
    cases.append({'case':'addressed_camera_floating_focus','offset':camera()['offset']})
    close_preserving('B','D')
    # Addressed reorder and token invalidation use the loaded native bridge.
    focused=active();anchor_x=windows()['C']['at'][0]
    evaluate('for _,w in ipairs(hl.get_windows()) do if w.address=='+json.dumps(addr('C'))+' then _pending=_testTape.prepare_close(w) end end; return _pending ~= nil')
    source,target=addr('D'),addr('E')
    result=reply('omarchy_tape_bar.reorder('+json.dumps(source)+','+json.dumps(target)+',"after",1,"HEADLESS-1")')
    assert result['ok'] and result['changed'],result
    time.sleep(.04)
    order=[c['address'] for c in reply('omarchy_tape_bar.snapshot("HEADLESS-1")')['columns']]
    assert order.index(source)==order.index(target)+1 and active()==focused
    assert abs(windows()['C']['at'][0]-anchor_x)<=2
    cases.append({'case':'addressed_reorder_floating_focus'})
    old_camera=camera()
    assert evaluate('return _testTape.finish_close(_pending).changed')=='false'
    assert camera()==old_camera
    cases.append({'case':'reorder_invalidates_pending_close'})
    # Stale context must not mutate any live camera or focus.
    before=camera();focused=active()
    rejected=evaluate('return hl.plugin.tape.pan(100,false,1,"HEADLESS-2").ok')
    assert rejected=='false' and camera()==before and active()==focused
    cases.append({'case':'reject_stale_camera_context'})
    # Old lifecycle owners cannot clear their successor's region.
    region='{{monitor="HEADLESS-1",x=0,y=0,width=100,height=26}}'
    assert reply('omarchy_tape_bar.protect_regions('+region+',"old")')['ok']
    assert reply('omarchy_tape_bar.protect_regions('+region+',"new")')['ok']
    assert float(evaluate('return hl.plugin.tape.info().protectedRegionCount'))==2
    assert reply('omarchy_tape_bar.protect_regions({{monitor="HEADLESS-1",x=0,y=0,width=0,height=0}},"old")')['ok']
    assert float(evaluate('return hl.plugin.tape.info().protectedRegionCount'))==1
    cases.append({'case':'retiring_owner_cannot_clear_successor'})
    assert not ctl('configerrors'),ctl('configerrors')
    (OUT/'results.json').write_text(json.dumps(cases,indent=2)+'\n')
    print(f'{len(cases)} private two-output compositor cases passed')
finally:
    for client in clients:
        if client.poll() is None:client.terminate()
        try:client.wait(timeout=2)
        except subprocess.TimeoutExpired:client.kill();client.wait()
    if compositor is not None and compositor.poll() is None:
        compositor.terminate()
        try:compositor.wait(timeout=5)
        except subprocess.TimeoutExpired:compositor.kill();compositor.wait()
    for log in (runtime/'hypr').glob('*/hyprland.log'):
        shutil.copy2(log,OUT/'hyprland.log')
    shutil.rmtree(runtime)
