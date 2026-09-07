#!/usr/bin/env python3
"""Installer isolation, migration, preservation and repeat-install contracts."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('strip_install',ROOT/'install.py')
installer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class Installation(unittest.TestCase):
    def test_new_install_defaults_to_public_nested_layout(self):
        with tempfile.TemporaryDirectory(prefix='strip-public-install-') as path:
            base=Path(path); config=base/'config'; widget=config/'omarchy/plugins'/installer.PUBLIC_PLUGIN_ID
            command=[sys.executable,str(ROOT/'install.py'),'--apply','--skip-native-build',
                     '--config-home',str(config),'--data-home',str(base/'data'),'--bin-dir',str(base/'bin')]
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            manifest=json.loads((widget/'manifest.json').read_text())
            self.assertEqual(manifest['id'],installer.PUBLIC_PLUGIN_ID)
            self.assertEqual(manifest['entryPoints']['service'],'plugin/Service.qml')
            for entry in manifest['entryPoints'].values(): self.assertTrue((widget/entry).is_file())
            self.assertFalse((widget.parent/installer.LOCAL_PLUGIN_ID).exists())

    def test_explicit_local_alias_creates_flat_layout(self):
        with tempfile.TemporaryDirectory(prefix='strip-local-install-') as path:
            base=Path(path); config=base/'config'; widget=config/'omarchy/plugins'/installer.LOCAL_PLUGIN_ID
            command=[sys.executable,str(ROOT/'install.py'),'--apply','--skip-native-build',
                     '--config-home',str(config),'--data-home',str(base/'data'),'--bin-dir',str(base/'bin'),
                     '--plugin-id',installer.LOCAL_PLUGIN_ID]
            result=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            manifest=json.loads((widget/'manifest.json').read_text())
            self.assertEqual(manifest['id'],installer.LOCAL_PLUGIN_ID)
            self.assertEqual(manifest['entryPoints']['service'],'Service.qml')
            self.assertTrue((widget/'Service.qml').is_file())
            self.assertFalse((widget/'plugin').exists())

    def test_public_git_source_stays_clean_and_preserves_local_alias(self):
        with tempfile.TemporaryDirectory(prefix='strip-public-git-') as path:
            base=Path(path); config=base/'config'; widget=config/'omarchy/plugins'/installer.PUBLIC_PLUGIN_ID
            shutil.copytree(ROOT,widget,ignore=shutil.ignore_patterns('.git','__pycache__','*.pyc'))
            local=widget.parent/installer.LOCAL_PLUGIN_ID
            local.mkdir(); (local/'custom.txt').write_text('keep local installation')
            settings=config/'omarchy/shell.json'
            settings.write_text(json.dumps({'bar':{'layout':{'left':[
                {'id':installer.PUBLIC_PLUGIN_ID,'widthRatio':0.63,'arrowMode':'click'}]}}}))
            original_settings=settings.read_text()
            # Only this temporary fixture repository is initialized or changed.
            subprocess.run(['git','init','-q',str(widget)],check=True)
            subprocess.run(['git','-C',str(widget),'add','.'],check=True)
            subprocess.run(['git','-C',str(widget),'-c','user.name=Fixture',
                            '-c','user.email=fixture@example.invalid','commit','-qm','Fixture'],check=True)
            command=[sys.executable,str(widget/'install.py'),'--apply','--skip-native-build',
                     '--config-home',str(config),'--data-home',str(base/'data'),'--bin-dir',str(base/'bin'),
                     '--plugin-id',installer.PUBLIC_PLUGIN_ID]
            result=subprocess.run(command,capture_output=True,text=True,cwd=base)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            status=subprocess.run(['git','-C',str(widget),'status','--porcelain'],check=True,capture_output=True,text=True)
            self.assertEqual(status.stdout,'',status.stdout)
            self.assertEqual((local/'custom.txt').read_text(),'keep local installation')
            self.assertEqual(settings.read_text(),original_settings)

    def test_managed_plugin_symlink_refused_before_changes(self):
        with tempfile.TemporaryDirectory(prefix='strip-install-link-') as path:
            base=Path(path); config=base/'config'; data=base/'data'; binary=base/'bin'
            bindings=config/'hypr/bindings.lua'; bindings.parent.mkdir(parents=True)
            bindings.write_text('-- original keys\n')
            widget=config/'omarchy/plugins/user1.layout-strip'; widget.mkdir(parents=True)
            external=base/'external.qml'; external.write_text('external original\n')
            (widget/'BarWidget.qml').symlink_to(external)
            backup=base/'backup'
            args=['install.py','--apply','--skip-native-build','--config-home',str(config),
                  '--data-home',str(data),'--bin-dir',str(binary),'--backup',str(backup)]
            with patch.object(sys,'argv',args):
                with self.assertRaisesRegex(RuntimeError,'managed symlink'): installer.main()
            self.assertEqual(external.read_text(),'external original\n')
            self.assertEqual(bindings.read_text(),'-- original keys\n')
            self.assertTrue((widget/'BarWidget.qml').is_symlink())
            self.assertFalse(backup.exists())
            self.assertFalse((config/'hypr/tape.lua').exists())
            self.assertFalse(binary.exists())

    def test_linked_parent_and_dangling_managed_paths_refused(self):
        with tempfile.TemporaryDirectory(prefix='strip-install-parents-') as path:
            base=Path(path); root=base/'config'; root.mkdir()
            external=base/'outside'; external.mkdir()
            (root/'hypr').symlink_to(external,target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError,'linked parent'):
                installer.refuse_linked_path(root/'hypr/tape.lua',root)
            (root/'missing').symlink_to(base/'does-not-exist')
            with self.assertRaisesRegex(RuntimeError,'managed symlink'):
                installer.refuse_linked_path(root/'missing',root)

    def test_widget_publish_failure_restores_backend_and_widget(self):
        with tempfile.TemporaryDirectory(prefix='strip-install-rollback-') as path:
            base=Path(path); config=base/'config'; data=base/'data'; binary=base/'bin'
            bindings=config/'hypr/bindings.lua'; bindings.parent.mkdir(parents=True)
            bindings.write_text('-- my keys\n')
            backend=config/'hypr/tape.lua'; backend.write_text('-- original backend\n')
            widget=config/'omarchy/plugins/user1.layout-strip'; widget.mkdir(parents=True)
            (widget/'original.txt').write_text('old widget')
            active=data/'hypr-tape/active.lua'; active.parent.mkdir(parents=True)
            active.write_text('-- original active manifest\n')
            rename=Path.rename
            def fail_publication(source,target):
                if source.name.startswith('.layout-strip-stage-') and not source.name.endswith('-previous'):
                    raise OSError('simulated widget publication failure')
                return rename(source,target)
            args=['install.py','--apply','--skip-native-build','--config-home',str(config),
                  '--data-home',str(data),'--bin-dir',str(binary),'--backup',str(base/'backup')]
            with patch.object(sys,'argv',args),patch.object(Path,'rename',fail_publication):
                with self.assertRaisesRegex(OSError,'publication failure'):installer.main()
            self.assertEqual(bindings.read_text(),'-- my keys\n')
            self.assertEqual(backend.read_text(),'-- original backend\n')
            self.assertEqual(active.read_text(),'-- original active manifest\n')
            self.assertEqual((widget/'original.txt').read_text(),'old widget')
            self.assertFalse((widget/'manifest.json').exists())
            self.assertFalse((config/'hypr/tape-bootstrap.lua').exists())

    def test_migration_preserves_surrounding_bindings(self):
        changes=json.loads((ROOT/'docs/bindings-migration.json').read_text())
        old='-- user prefix\n'+('\n-- user separator\n'.join(c['before'] for c in changes))+'-- user suffix\n'
        patched=installer.migrate_bindings(old)
        self.assertTrue(patched.startswith('-- user prefix\n'))
        self.assertTrue(patched.endswith('-- user suffix\n'))
        self.assertEqual(patched.count('-- user separator'),2)
        self.assertEqual(installer.migrate_bindings(patched),patched)
        for change in changes:
            self.assertNotIn(change['before'],patched)
            if change['after']:self.assertIn(change['after'],patched)

    def test_ambiguous_migration_refused(self):
        with self.assertRaises(RuntimeError):installer.migrate_bindings('omarchy_tape_bar = custom_backend\n')
        self.assertEqual(installer.migrate_bindings(installer.BOOTSTRAP),installer.BOOTSTRAP)

    def test_isolated_install_preserves_settings_and_mode(self):
        with tempfile.TemporaryDirectory(prefix='strip-install-test-') as path:
            base=Path(path); config=base/'config'; data=base/'data'; binary=base/'bin'
            (config/'hypr').mkdir(parents=True)
            (config/'hypr/bindings.lua').write_text('-- my untouched keybindings\n')
            (config/'hypr/tape-mode.lua').write_text('return "smooth"\n')
            widget=config/'omarchy/plugins/user1.layout-strip'
            widget.mkdir(parents=True)
            (widget/'custom.txt').write_text('keep me')
            custom_target=base/'custom-target'; custom_target.write_text('external custom')
            (widget/'custom-link').symlink_to(custom_target)
            (config/'omarchy/shell.json').write_text('{"keep":"my settings"}')
            command=[sys.executable,str(ROOT/'install.py'),'--apply','--skip-native-build',
                     '--config-home',str(config),'--data-home',str(data),'--bin-dir',str(binary)]
            for i in range(2):
                result=subprocess.run(command+['--backup',str(base/f'backup-{i}')],capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            bindings=(config/'hypr/bindings.lua').read_text()
            self.assertTrue(bindings.startswith('-- my untouched keybindings\n'))
            self.assertEqual(bindings.count('omarchy_tape_bar ='),1)
            self.assertEqual((config/'hypr/tape-mode.lua').read_text(),'return "smooth"\n')
            self.assertEqual((widget/'custom.txt').read_text(),'keep me')
            self.assertTrue((widget/'custom-link').is_symlink())
            self.assertEqual((widget/'custom-link').readlink(),custom_target)
            self.assertEqual(custom_target.read_text(),'external custom')
            self.assertEqual((config/'omarchy/shell.json').read_text(),'{"keep":"my settings"}')
            self.assertEqual(json.loads((widget/'manifest.json').read_text())['version'],'1.0.0')
            self.assertEqual(json.loads((widget/'manifest.json').read_text())['id'],installer.LOCAL_PLUGIN_ID)
            self.assertTrue((binary/'hypr-tape-doctor').stat().st_mode & 0o111)
            self.assertTrue((data/'hypr-tape/BarRegionRegistry.hpp').is_file())
            records=json.loads((base/'backup-0/files.json').read_text())
            self.assertTrue(any(r['path']==str(data/'hypr-tape/active.lua') for r in records))

if __name__=='__main__':unittest.main()
