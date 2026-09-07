#!/usr/bin/env python3
"""Install the shared backend, rebuild its matching native bridge, then swap the widget.

Without --apply, only print the installation plan. Existing settings and unrelated
bindings are preserved. Backups are created before any managed file is replaced.
"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
BOOTSTRAP = '''
-- Layout Strip shared backend (managed bootstrap; installs no keybindings).
require("hypr.tape-native").load()
local layout_strip_tape = require("hypr.tape").new(hl)
local layout_strip_integration = require("hypr.tape-bootstrap").new(hl, layout_strip_tape, require("hypr.tape-bar"))
omarchy_tape_bar = layout_strip_integration.bar
'''


def migrate_bindings(text):
    changes = json.loads((ROOT / 'docs/bindings-migration.json').read_text())
    if all(change['before'] in text for change in changes):
        for change in changes:
            if text.count(change['before']) != 1:
                raise RuntimeError('Ambiguous old tape integration in bindings.lua')
            text = text.replace(change['before'], change['after'], 1)
        return text
    if 'require("hypr.tape-bootstrap").new(' in text:
        if any(change['before'] in text for change in changes):
            raise RuntimeError('Partially migrated tape integration; inspect bindings.lua')
        return text
    if 'omarchy_tape_bar' in text or 'pointer_refocus_deferred' in text:
        raise RuntimeError('Unrecognized existing tape integration; merge the documented bootstrap explicitly')
    return text.rstrip() + '\n' + BOOTSTRAP


def atomic_copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, path = tempfile.mkstemp(prefix='.layout-strip-', dir=destination.parent)
    os.close(descriptor)
    temporary = Path(path)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def refuse_linked_path(destination, root):
    """Do not follow/replace links below an explicitly selected install root."""
    root = Path(root).absolute()
    destination = Path(destination).absolute()
    relative = destination.relative_to(root)
    current = root
    for component in relative.parts:
        current = current / component
        # is_symlink also detects dangling links, unlike exists(). The root
        # itself is user-selected; only descendants are managed by this install.
        if current.is_symlink():
            raise RuntimeError('Refusing managed symlink or linked parent: ' + str(current))


def preflight_paths(destinations, roots):
    for destination in destinations:
        for root in roots:
            if Path(destination).absolute().is_relative_to(Path(root).absolute()):
                refuse_linked_path(destination, root)
                break


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--config-home', type=Path, default=Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')))
    parser.add_argument('--data-home', type=Path, default=Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')))
    parser.add_argument('--bin-dir', type=Path, default=Path.home() / '.local/bin')
    parser.add_argument('--backup', type=Path)
    parser.add_argument('--skip-native-build', action='store_true', help='For isolated staging only; leaves the bridge unavailable until rebuilt')
    args = parser.parse_args()
    bindings = args.config_home / 'hypr/bindings.lua'
    refuse_linked_path(bindings, args.config_home)
    original = bindings.read_text() if bindings.exists() else ''
    patched = migrate_bindings(original)
    widget = args.config_home / 'omarchy/plugins/user1.layout-strip'
    native = args.data_home / 'hypr-tape'
    backup = args.backup or native / 'backups' / ('install-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    sources = []
    for name in ('tape.lua','tape-bar.lua','tape-native.lua','tape-bootstrap.lua'):
        sources.append((ROOT / 'backend' / name, args.config_home / 'hypr' / name))
    mode = args.config_home / 'hypr/tape-mode.lua'
    if not mode.exists(): sources.append((ROOT/'backend/tape-mode.lua', mode))
    for source in sorted((ROOT/'native').iterdir()):
        if source.is_file() and source.suffix in ('.cpp','.hpp','.sh','.md'):
            sources.append((source,native/source.name))
    for source in sorted((ROOT/'bin').iterdir()):
        if source.is_file(): sources.append((source,args.bin_dir/source.name))
    # Validate all managed paths before backups, staging or live writes. A
    # copied managed symlink would otherwise let copytree write outside staging.
    managed = [p for _, p in sources] + [bindings, native/'active.lua', widget, backup]
    managed.extend(widget / source.relative_to(ROOT/'plugin') for source in (ROOT/'plugin').rglob('*'))
    preflight_paths(managed, [args.config_home, args.data_home, args.bin_dir])
    plan = {'widget':str(widget),'backendFiles':[str(p) for _,p in sources],
            'bindingsChanged':patched!=original,'nativeBuild':not args.skip_native_build,'backup':str(backup)}
    if not args.apply:
        print(json.dumps(plan,indent=2)); return
    backup.mkdir(parents=True,exist_ok=False)
    records = []
    for index, destination in enumerate([p for _,p in sources] + [bindings, native/'active.lua']):
        saved = backup / f'file-{index}'
        existed = destination.exists()
        if existed: shutil.copy2(destination,saved)
        records.append({'path':str(destination),'backup':str(saved) if existed else None})
    if widget.exists(): shutil.copytree(widget,backup/'widget',symlinks=True)
    (backup/'files.json').write_text(json.dumps(records,indent=2)+'\n')
    # Prepare outside plugins/ so watchers see a complete code tree at once.
    widget.parent.mkdir(parents=True,exist_ok=True)
    staging=Path(tempfile.mkdtemp(prefix='.layout-strip-stage-',dir=widget.parent.parent))
    held=staging.with_name(staging.name+'-previous')
    committed=False
    try:
        if widget.exists(): shutil.copytree(widget,staging,dirs_exist_ok=True,symlinks=True)
        shutil.copytree(ROOT/'plugin',staging,dirs_exist_ok=True)
        for source,destination in sources: atomic_copy(source,destination)
        if patched != original:
            with tempfile.TemporaryDirectory(prefix='layout-strip-binding-') as temp:
                source=Path(temp)/'bindings.lua';source.write_text(patched);source.chmod(0o644)
                atomic_copy(source,bindings)
        if not args.skip_native_build:
            subprocess.run([str(args.bin_dir/'hypr-tape-rebuild'),'--data-dir',str(native)],check=True,timeout=240)
            subprocess.run(['hyprctl','reload'],check=True,timeout=10,capture_output=True)
            errors=subprocess.run(['hyprctl','configerrors'],check=True,timeout=10,capture_output=True,text=True).stdout.strip()
            if errors: raise RuntimeError('Hyprland configuration errors: '+errors)
        if widget.exists(): widget.rename(held)
        staging.rename(widget)
        committed=True
    except BaseException:
        if held.exists():
            if widget.exists(): shutil.rmtree(widget)
            held.rename(widget)
        for record in reversed(records):
            destination=Path(record['path'])
            if record['backup']: atomic_copy(Path(record['backup']),destination)
            else: destination.unlink(missing_ok=True)
        if not args.skip_native_build:
            subprocess.run(['hyprctl','reload'],timeout=10,capture_output=True,check=False)
        raise
    finally:
        if staging.exists(): shutil.rmtree(staging)
        # Never discard the recovery tree if publication or restoration failed.
        if committed and held.exists(): shutil.rmtree(held)
    print('Installed Layout Strip 1.2.0. Backup: '+str(backup))
    if not args.skip_native_build:
        print('Run omarchy restart shell to load new QML components, then hypr-tape-doctor to verify the active plugin.')


if __name__=='__main__': main()
