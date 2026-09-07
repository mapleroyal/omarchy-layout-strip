"""Health checks use only fixture files and fake command responses."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('strip_doctor', str(ROOT/'bin/hypr-tape-doctor'))
spec = importlib.util.spec_from_loader(loader.name, loader)
doctor = importlib.util.module_from_spec(spec)
loader.exec_module(doctor)


class Doctor(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='strip-doctor-')
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.config, self.data = base/'config', base/'data'
        for path in [self.config/'omarchy/plugins/user1.layout-strip/manifest.json',
                     self.config/'hypr/tape-bootstrap.lua', self.config/'hypr/tape.lua',
                     self.config/'hypr/tape-bar.lua', self.config/'hypr/tape-native.lua',
                     self.data/'hypr-tape/active.lua']:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}')
        self.settings = self.config/'omarchy/shell.json'
        self.settings.write_text(json.dumps({'bar': {'layout': {'left': [{'id': doctor.PLUGIN_ID}]}}}))
        self.calls = []
        self.debug = {'protocolVersion': 2, 'backendError': '', 'regionError': '',
                      'instances': [{'monitorName': 'HEADLESS-1', 'workspaceId': 1,
                                     'queryError': '', 'stale': False,
                                     'capabilities': {'layout': True, 'error': ''}}]}

    def run_command(self, command, **kwargs):
        self.calls.append(command)
        self.assertTrue(kwargs['check'])
        if command[0] == 'hyprctl':
            value = {'version': 'test'}
        elif command[0] == 'omarchy':
            value = self.debug
        else:
            value = {'ok': True, 'protocolVersion': 2, 'nativeProtocolVersion': 2}
        return subprocess.CompletedProcess(command, 0, json.dumps(value), '')

    def health(self):
        return doctor.health(self.config, self.data, self.run_command)

    def test_active_shell_and_adjacent_helper(self):
        with patch.object(doctor, '__file__', str(Path(self.temporary.name)/'custom-bin/hypr-tape-doctor')):
            result = self.health()
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['shell']['status'], 'active')
        self.assertEqual(self.calls[1][0], str(Path(self.temporary.name)/'custom-bin/hypr-tape-bar'))
        self.assertEqual(self.calls[2], ['omarchy', 'shell', doctor.PLUGIN_ID, 'debug'])

    def test_disabled_shell_is_explicit_and_skips_ipc(self):
        for settings in ({}, {'bar': {'layout': {'left': [doctor.PLUGIN_ID]}},
                             'disabledPlugins': [doctor.PLUGIN_ID]}):
            self.calls.clear()
            self.settings.write_text(json.dumps(settings))
            result = self.health()
            self.assertTrue(result['ok'], result)
            self.assertEqual(result['shell'], {'enabled': False, 'status': 'disabled'})
            self.assertFalse(any(call[0] == 'omarchy' for call in self.calls))

    def test_enabled_missing_service_fails_health(self):
        def unavailable(command, **kwargs):
            if command[0] == 'omarchy':
                raise subprocess.CalledProcessError(1, command, stderr='No such target')
            return self.run_command(command, **kwargs)
        result = doctor.health(self.config, self.data, unavailable)
        self.assertFalse(result['ok'])
        self.assertEqual(result['shell']['status'], 'unavailable')

    def test_invalid_protocol_empty_instances_and_stale_fail(self):
        for debug in ({'protocolVersion': 1, 'instances': []},
                      {'protocolVersion': 2, 'instances': []},
                      {'protocolVersion': 2, 'instances': [{'stale': True, 'capabilities': {'layout': True}}]},
                      {'protocolVersion': 2, 'instances': [{'capabilities': {'layout': False}}]},
                      {'protocolVersion': 2, 'regionError': 'Lease failed', 'instances': self.debug['instances']}):
            with self.subTest(debug=debug):
                self.debug = debug
                result = self.health()
                self.assertFalse(result['ok'])
                self.assertEqual(result['shell']['status'], 'unhealthy')

    def test_invalid_config_and_debug_are_reported(self):
        self.settings.write_text('[]')
        result = self.health()
        self.assertFalse(result['ok'])
        self.assertEqual(result['shell']['status'], 'configuration-error')
        self.settings.write_text(json.dumps({'bar': {'layout': {'left': [doctor.PLUGIN_ID]}}}))
        self.debug = []
        result = self.health()
        self.assertFalse(result['ok'])
        self.assertEqual(result['shell']['status'], 'unavailable')


if __name__ == '__main__':
    unittest.main()
