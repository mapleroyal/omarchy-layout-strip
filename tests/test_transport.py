import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

source = Path(__file__).resolve().parents[1] / 'backend' / 'transport.py'
spec = importlib.util.spec_from_file_location('transport', source)
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


class TransportTests(unittest.TestCase):
    def test_lua_strings_round_trip_untrusted_text(self):
        text = 'monitor"; error("bad") -- \\ café\n$(touch /tmp/never)'
        result = subprocess.run(['lua', '-e', 'io.write(' + transport.lua_string(text) + ')'],
                                check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout, text)

    def test_backend_load_is_portable_and_literal(self):
        code = transport.request_code('snapshot', 'monitor"; error("bad")')
        self.assertIn(transport.lua_string(str(source.parent / 'tape.lua')), code)
        self.assertIn('omarchy_tape_bar or dofile(', code)
        self.assertNotIn('.local/bin', code)
        self.assertNotIn('error("bad")', code)

    def test_invalid_address_never_reaches_compositor(self):
        with patch('sys.argv', [str(source), 'focus', '0x12;bad', '--workspace', '1']), \
             patch.object(transport.subprocess, 'run') as run, \
             self.assertRaises(SystemExit) as raised:
            transport.main()
        self.assertEqual(raised.exception.code, 2)
        run.assert_not_called()

    def test_interrupted_compositor_returns_machine_readable_error(self):
        with patch('sys.argv', [str(source), 'snapshot']), \
             patch.object(transport.subprocess, 'run', side_effect=subprocess.TimeoutExpired('hyprctl', 3)), \
             patch('builtins.print') as output:
            self.assertEqual(transport.main(), 1)
        result = json.loads(output.call_args.args[0])
        self.assertFalse(result['ok'])
        self.assertEqual(result['columns'], [])

    def test_compositor_command_uses_argv_without_shell(self):
        reply = subprocess.CompletedProcess([], 0, '{"ok":true,"columns":[]}', '')
        with patch('sys.argv', [str(source), 'snapshot', '--monitor', 'eDP-1']), \
             patch.object(transport.subprocess, 'run', return_value=reply) as run, \
             patch('builtins.print'):
            self.assertEqual(transport.main(), 0)
        self.assertEqual(run.call_args.args[0][:2], ['hyprctl', 'repl'])
        self.assertFalse(run.call_args.kwargs.get('shell', False))


if __name__ == '__main__':
    unittest.main()
