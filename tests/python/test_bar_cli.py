"""Contract tests for CLI argument validation and the one-request transport."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest import mock

path = Path(__file__).resolve().parents[2] / 'bin' / 'hypr-tape-bar'
loader = importlib.machinery.SourceFileLoader('bar_cli', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)


class CliTests(unittest.TestCase):
    def invoke(self, arguments, reply=None, error=None):
        output = io.StringIO()
        completed = subprocess.CompletedProcess([], 0, json.dumps(reply or {'ok': True}), '')
        with mock.patch.object(cli.subprocess, 'run', return_value=completed, side_effect=error) as run:
            with contextlib.redirect_stdout(output):
                code = cli.main(arguments)
        return code, json.loads(output.getvalue()), run

    def test_reorder_context_and_strings_reach_only_hyprctl_repl(self):
        monitor = 'DP-1"; os.execute("false"); -- 雪'
        code, reply, run = self.invoke(['reorder', '0xAb', '--target', '0x12', '--side', 'after',
                                       '--workspace', '-99', '--monitor', monitor])
        self.assertEqual(code, 0)
        invocation = run.call_args.args[0]
        self.assertEqual(invocation[:2], ['hyprctl', 'repl'])
        self.assertIn(f'omarchy_tape_bar.reorder({cli.lua_string("0xab")}, '
                      f'{cli.lua_string("0x12")}, {cli.lua_string("after")}, -99, '
                      f'{cli.lua_string(monitor)})', invocation[2])
        self.assertNotIn('os.execute', invocation[2])
        self.assertNotIn('shell', run.call_args.kwargs)

    def test_close_is_addressed_and_never_requests_focus(self):
        _, _, run = self.invoke(['close', '0x12', '--workspace', '1', '--monitor', 'eDP-1'])
        code = run.call_args.args[0][2]
        self.assertIn('omarchy_tape_bar.close(', code)
        self.assertNotIn('.focus(', code)

    def test_snapshot_and_focus_remain_compatible(self):
        _, _, run = self.invoke(['snapshot'])
        self.assertIn('omarchy_tape_bar.snapshot(nil)', run.call_args.args[0][2])
        _, _, run = self.invoke(['focus', '0x12', '--workspace', '1'])
        self.assertIn('omarchy_tape_bar.focus(', run.call_args.args[0][2])

    def test_focus_normalizes_accepted_hexadecimal_addresses(self):
        _, _, run = self.invoke(['focus', '0xABcd', '--workspace', '1', '--monitor', 'one'])
        invocation = run.call_args.args[0][2]
        self.assertIn('omarchy_tape_bar.focus(' + cli.lua_string('0xabcd') + ',', invocation)
        self.assertIn('omarchy_tape_bar.protocol_version ~= 2', invocation)

    def test_rejected_arguments_never_invoke_compositor(self):
        cases = [
            ['close', '0x12;bad()', '--workspace', '1', '--monitor', 'eDP-1'],
            ['close', '0x12', '--workspace', '1'],
            ['close', '0x12', '--workspace', '1', '--monitor', ''],
            ['reorder', '0x12', '--target', 'bogus', '--side', 'after', '--workspace', '1', '--monitor', 'eDP-1'],
            ['reorder', '0x12', '--target', '0x13', '--side', 'outside', '--workspace', '1', '--monitor', 'eDP-1'],
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments), mock.patch.object(cli.subprocess, 'run') as run:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    cli.main(arguments)
                self.assertEqual(error.exception.code, 2)
                run.assert_not_called()

    def test_compositor_rejection_is_preserved_and_exits_nonzero(self):
        result = {'ok': False, 'error': 'The workspace changed'}
        code, reply, _ = self.invoke(['snapshot'], result)
        self.assertEqual((code, reply), (1, result))

    def test_transport_timeout_is_json_error_without_retry(self):
        code, reply, run = self.invoke(['snapshot'], error=subprocess.TimeoutExpired('hyprctl', 3))
        self.assertEqual(code, 1)
        self.assertFalse(reply['ok'])
        self.assertIn('timed out', reply['error'])
        run.assert_called_once()

    def test_malformed_success_flag_is_rejected(self):
        code, reply, _ = self.invoke(['snapshot'], {'ok': 'false'})
        self.assertEqual(code, 1)
        self.assertEqual(reply['error'], 'unexpected reply from Hyprland')


if __name__ == '__main__':
    unittest.main()
