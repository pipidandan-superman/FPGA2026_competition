import ast
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

import board_pl_reload_controller as board
import pl_reloader_gui as gui
import ssh_askpass


class PayloadTests(unittest.TestCase):
    def test_local_release_manifest_and_hashes(self):
        manifest = gui.validate_local_payload()
        self.assertEqual(manifest["marker"], "ACTION_V1_RELEASE_PASS")
        self.assertEqual(len(manifest["files"]), 13)
        self.assertEqual(
            manifest["files"]["display_test_axi_action_uart.bit"]["sha256"],
            "bffaa83565d60ea28e04a31497b4c3dff828b0359012dafe1d5d1ea5a390e16d",
        )

    def test_board_controller_validates_same_payload(self):
        manifest = board.validate_payload(gui.payload_dir())
        self.assertEqual(manifest["marker"], "ACTION_V1_RELEASE_PASS")

    def test_payload_tamper_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "payload.bin").write_bytes(b"changed")
            manifest = {
                "marker": "ACTION_V1_RELEASE_PASS",
                "files": {"payload.bin": {"sha256": "0" * 64}},
            }
            (root / "release_manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaises(board.ControllerError):
                board.validate_payload(root)


class SafetyTests(unittest.TestCase):
    def test_v14_default_password_is_xilinx(self):
        self.assertEqual(gui.APP_VERSION, "1.4")
        self.assertEqual(gui.DEFAULT_SSH_PASSWORD, "xilinx")

    def test_camera_uses_extended_diagnostic_waits(self):
        source = (gui.payload_dir() / "camera.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        constants = {
            node.targets[0].id: ast.literal_eval(node.value)
            for node in tree.body
            if isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id in {
                "SENSOR_SETTLE_SECONDS", "FIRST_FRAME_TIMEOUT_SECONDS"
            }
        }
        self.assertEqual(constants["SENSOR_SETTLE_SECONDS"], 10.0)
        self.assertEqual(constants["FIRST_FRAME_TIMEOUT_SECONDS"], 30.0)
        self.assertEqual(board.ACTION_READY_TIMEOUT_SECONDS, 75)

    def test_run_can_stream_output_without_losing_full_text(self):
        streamed = []
        code, output = gui.BoardClient._run(
            [sys.executable, "-u", "-c", "print('line-one'); print('line-two')"],
            timeout=10,
            line_callback=streamed.append,
        )
        self.assertEqual(code, 0)
        self.assertEqual(streamed, ["line-one", "line-two"])
        self.assertEqual(output.splitlines(), streamed)

    def test_journal_delta_returns_only_new_lines(self):
        self.assertEqual(board.journal_delta("a\nb\n", "a\nb\nc\n"), ["c"])
        self.assertEqual(board.journal_delta("a\nb\n", "b\nc\n"), ["c"])

    def test_action_process_parser_rejects_pgrep_self_match(self):
        output = "2786 bash -c pgrep -af camera_action_v1.py || true\n"
        self.assertEqual(gui.real_action_processes(output), [])

    def test_action_process_parser_accepts_real_python_process(self):
        output = (
            "301 /usr/local/share/pynq-venv/bin/python3 -u "
            "/home/xilinx/app/camera_action_v1.py --peer 192.168.240.2\n"
        )
        self.assertEqual(gui.real_action_processes(output), [output.strip()])

    def test_action_running_uses_non_self_matching_pattern(self):
        client = object.__new__(gui.BoardClient)
        client.remote = mock.Mock(return_value="")
        client.log = mock.Mock()
        self.assertFalse(client.action_running())
        client.remote.assert_called_once_with("pgrep -af '[c]amera_action_v1.py' || true")

    def test_wait_until_success_and_timeout(self):
        values = iter([False, False, True])
        self.assertTrue(board.wait_until(lambda: next(values), 1, interval=0))
        self.assertFalse(board.wait_until(lambda: False, 0.001, interval=0))

    def test_self_test_marker(self):
        output = io.StringIO()
        with mock.patch("sys.stdout", output):
            code = gui.self_test()
        self.assertEqual(code, 0)
        self.assertIn("PL_RELOADER_SELF_TEST_PASS", output.getvalue())

    def test_tcp_preflight_reports_board_network_problem(self):
        with mock.patch.object(gui.socket, "create_connection", side_effect=OSError("unreachable")):
            with self.assertRaisesRegex(ConnectionError, "192.168.240.2/24"):
                gui.tcp_preflight("192.168.240.10", timeout=0.01)

    def test_tcp_preflight_accepts_reachable_ssh(self):
        connection = mock.MagicMock()
        with mock.patch.object(gui.socket, "create_connection", return_value=connection):
            gui.tcp_preflight("192.168.240.10", timeout=0.01)
        connection.__enter__.assert_called_once()
        connection.__exit__.assert_called_once()

    def test_askpass_reads_only_temporary_environment(self):
        output = io.StringIO()
        with mock.patch.dict("os.environ", {ssh_askpass.PASSWORD_ENV: "test-secret"}, clear=True), \
                mock.patch("sys.stdout", output):
            code = ssh_askpass.main()
        self.assertEqual(code, 0)
        self.assertEqual(output.getvalue(), "test-secret")

    def test_password_is_not_an_ssh_command_argument(self):
        with mock.patch.object(gui, "find_openssh", return_value=Path("C:/OpenSSH/tool.exe")), \
                mock.patch.object(gui, "askpass_helper", return_value=Path("C:/app/askpass.exe")):
            client = gui.BoardClient("192.168.240.10", "xilinx", "test-secret", lambda _: None)
        arguments = [str(client.ssh), "-p", "22", *client._ssh_options(), "xilinx@192.168.240.10"]
        self.assertNotIn("test-secret", arguments)
        self.assertEqual(client._environment()["EES331_SSH_PASSWORD"], "test-secret")

    def test_restore_is_idempotent_when_original_is_running(self):
        props = {"MainPID": "123", "ActiveState": "active", "SubState": "running"}
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(board, "STATE_FILE", Path(directory) / "state.json"), \
                mock.patch.object(board, "processes", return_value=board.ORIGINAL_PROCESS), \
                mock.patch.object(board, "service_properties", return_value=props), \
                mock.patch.object(board, "run") as execute:
            result = board.restore_original(reason="TEST")
        self.assertEqual(result["properties"], props)
        execute.assert_not_called()

    def test_restore_requires_action_dma_release_markers(self):
        inactive = {"MainPID": "0", "ActiveState": "inactive", "SubState": "dead"}
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            state.write_text(json.dumps({"unit": "ees331-action-test.service", "started_epoch": 1}))
            with mock.patch.object(board, "STATE_FILE", state), \
                    mock.patch.object(board, "processes", side_effect=[board.ACTION_PROCESS, ""]), \
                    mock.patch.object(board, "service_properties", return_value=inactive), \
                    mock.patch.object(board, "action_units", return_value=["ees331-action-test.service"]), \
                    mock.patch.object(board, "journal", return_value="BUFFER_ALLOCATED\nVDMA_STREAM_STARTED"), \
                    mock.patch.object(board, "run", return_value=mock.Mock(returncode=0, stdout="")) as execute:
                with self.assertRaises(board.ControllerError):
                    board.restore_original(reason="TEST")
        commands = [call.args[0] for call in execute.call_args_list]
        self.assertNotIn(["systemctl", "start", board.ORIGINAL_SERVICE], commands)

    def test_restore_starts_original_after_proven_release(self):
        inactive = {"MainPID": "0", "ActiveState": "inactive", "SubState": "dead"}
        active = {"MainPID": "456", "ActiveState": "active", "SubState": "running"}
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state.json"
            state.write_text(json.dumps({"unit": "ees331-action-test.service", "started_epoch": 1}))
            with mock.patch.object(board, "STATE_FILE", state), \
                    mock.patch.object(board, "processes", side_effect=[board.ACTION_PROCESS, ""]), \
                    mock.patch.object(board, "service_properties", side_effect=[inactive, active]), \
                    mock.patch.object(board, "action_units", return_value=["ees331-action-test.service"]), \
                    mock.patch.object(board, "journal", return_value="BUFFER_ALLOCATED\nVDMA_HALTED\nBUFFER_FREED"), \
                    mock.patch.object(board, "wait_until", return_value=True), \
                    mock.patch.object(board, "run", return_value=mock.Mock(returncode=0, stdout="")) as execute:
                result = board.restore_original(reason="TEST")
        self.assertEqual(result["properties"], active)
        commands = [call.args[0] for call in execute.call_args_list]
        self.assertIn(["systemctl", "stop", "ees331-action-test.service"], commands)
        self.assertIn(["systemctl", "start", board.ORIGINAL_SERVICE], commands)


if __name__ == "__main__":
    unittest.main(verbosity=2)
