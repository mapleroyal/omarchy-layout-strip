"""Validate optional strip-region transport without invoking Hyprland."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest import mock

loader = importlib.machinery.SourceFileLoader('region_cli', str(Path(__file__).resolve().parents[2] / 'bin' / 'hypr-tape-bar'))
spec = importlib.util.spec_from_loader(loader.name, loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)


class RegionCliTests(unittest.TestCase):
    def command(self, arguments):
        completed = subprocess.CompletedProcess([], 0, json.dumps({'ok': True}), '')
        with mock.patch.object(cli.subprocess, 'run', return_value=completed) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(cli.main(arguments), 0)
        self.assertEqual(run.call_args.args[0][:2], ['hyprctl', 'repl'])
        return run.call_args.args[0][2]

    def test_optional_region_omitted_keeps_old_snapshot_shape(self):
        self.assertIn('omarchy_tape_bar.snapshot(nil)', self.command(['snapshot']))
        self.assertIn(f'omarchy_tape_bar.snapshot({cli.lua_string("eDP-1")})',
                      self.command(['snapshot', '--monitor', 'eDP-1']))

    def test_global_fractional_negative_coordinates_are_forwarded(self):
        self.assertIn(f'omarchy_tape_bar.snapshot({cli.lua_string("eDP-1")}, -122.5, -146.0, 415.5, 26.0)',
                      self.command(['snapshot', '--monitor', 'eDP-1', '--protect-region',
                                    '-122.5', '-146', '415.5', '26']))

    def test_bad_regions_never_invoke_compositor(self):
        cases = [
            ['--protect-region', '0', '0', '100', '26'],
            ['--monitor', '', '--protect-region', '0', '0', '100', '26'],
            ['--monitor', 'eDP-1', '--protect-region', 'nan', '0', '100', '26'],
            ['--monitor', 'eDP-1', '--protect-region', '0', 'inf', '100', '26'],
            ['--monitor', 'eDP-1', '--protect-region', '0', '0', '1e999', '26'],
            ['--monitor', 'eDP-1', '--protect-region', '0', '0', '0', '26'],
            ['--monitor', 'eDP-1', '--protect-region', '0', '0', '100', '-1'],
            ['--monitor', 'eDP-1', '--protect-region', '0', '0', '100'],
        ]
        for arguments in cases:
            with self.subTest(arguments=arguments), mock.patch.object(cli.subprocess, 'run') as run:
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    cli.main(['snapshot'] + arguments)
                self.assertEqual(error.exception.code, 2)
                run.assert_not_called()

    def test_zero_dimensions_clear_a_hidden_strip_immediately(self):
        self.assertIn(f'omarchy_tape_bar.snapshot({cli.lua_string("eDP-1")}, 0.0, 0.0, 0.0, 0.0)',
                      self.command(['snapshot', '--monitor', 'eDP-1', '--protect-region', '0', '0', '0', '0']))

    def test_existing_addressed_actions_remain_compatible(self):
        self.assertIn('omarchy_tape_bar.close(', self.command(['close', '0x1', '--workspace', '1', '--monitor', 'eDP-1']))
        self.assertIn('omarchy_tape_bar.reorder(', self.command(['reorder', '0x1', '--target', '0x2',
            '--side', 'before', '--workspace', '1', '--monitor', 'eDP-1']))


if __name__ == '__main__':
    unittest.main()
