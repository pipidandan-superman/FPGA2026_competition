#!/usr/bin/env python3
"""Windows GUI for safely loading the EES-331 action overlay over SSH."""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import queue
import shutil
import socket
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk


APP_NAME = "EES331_PL_Reloader"
APP_VERSION = "1.4"
DEFAULT_SSH_PASSWORD = "xilinx"
REMOTE_DIR = "/home/xilinx/pl_reloader/action_v1_20260913"
BOARD_PYTHON = "/usr/local/share/pynq-venv/bin/python3"
CONTROLLER = "board_pl_reload_controller.py"


def executable_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def payload_dir() -> Path:
    packaged = executable_root() / "payload" / "action_v1_20260913"
    if packaged.is_dir():
        return packaged
    workspace = Path("E:/competition/9_pynq/overlays/action_v1_20260913")
    if workspace.is_dir():
        return workspace
    raise FileNotFoundError("找不到动作版PL载荷目录")


def controller_source() -> Path:
    packaged = payload_dir() / CONTROLLER
    if packaged.is_file():
        return packaged
    source = Path(__file__).resolve().with_name(CONTROLLER)
    if source.is_file():
        return source
    raise FileNotFoundError("找不到板端重加载控制器")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_local_payload() -> dict:
    root = payload_dir()
    manifest = json.loads((root / "release_manifest.json").read_text(encoding="utf-8"))
    if manifest.get("marker") != "ACTION_V1_RELEASE_PASS":
        raise RuntimeError("本地载荷发布标记无效")
    failures = []
    for name, metadata in manifest.get("files", {}).items():
        path = root / name
        actual = sha256(path) if path.is_file() else None
        if actual != metadata.get("sha256"):
            failures.append({"file": name, "expected": metadata.get("sha256"), "actual": actual})
    if failures:
        raise RuntimeError("本地载荷哈希失败: " + json.dumps(failures, ensure_ascii=False))
    return manifest


def find_openssh(name: str) -> Path:
    found = shutil.which(name)
    if found:
        return Path(found)
    candidate = Path("C:/Windows/System32/OpenSSH") / name
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(f"未找到 Windows OpenSSH {name}")


def askpass_helper() -> Path:
    packaged = executable_root() / "askpass" / "EES331_SSH_AskPass.exe"
    if packaged.is_file():
        return packaged
    if getattr(sys, "frozen", False):
        raise FileNotFoundError("安装目录缺少 askpass/EES331_SSH_AskPass.exe")
    source = Path(__file__).resolve().with_name("ssh_askpass.py")
    if source.is_file():
        return source
    raise FileNotFoundError("找不到SSH密码辅助程序")


def tcp_preflight(host: str, port: int = 22, timeout: float = 3.0) -> None:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return
    except OSError as exc:
        raise ConnectionError(
            f"无法连接开发板 {host}:{port}。请确认板卡已上电、网线已连接，"
            "并确认PC有线网卡仍为192.168.240.2/24。"
        ) from exc


def local_log_root() -> Path:
    project = Path("E:/competition/4_metrics/logs")
    if project.is_dir():
        return project
    return Path.home() / "Documents" / "EES331_PL_Reloader" / "logs"


class CommandFailure(RuntimeError):
    def __init__(self, label: str, code: int, output: str):
        super().__init__(f"{label}失败，退出码{code}\n{output[-3000:]}")
        self.code = code
        self.output = output


class OperationSkipped(RuntimeError):
    """A safe no-op that must not be reported as a successful operation."""


def real_action_processes(output: str) -> list[str]:
    """Return only real PID/cmdline rows for camera_action_v1.py."""
    matches = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        parts = line.split(maxsplit=1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        command = parts[1]
        if "camera_action_v1.py" not in command:
            continue
        if "pgrep -af" in command or "bash -c pgrep" in command:
            continue
        matches.append(line)
    return matches


class BoardClient:
    def __init__(self, host: str, user: str, password: str, log):
        self.host = str(ipaddress.ip_address(host.strip()))
        self.user = user.strip()
        if not self.user or any(char.isspace() for char in self.user):
            raise ValueError("SSH用户名无效")
        if not password:
            raise ValueError("请输入开发板SSH密码")
        self.password = password
        self.log = log
        self.ssh = find_openssh("ssh.exe")
        self.scp = find_openssh("scp.exe")
        self.askpass = askpass_helper()
        if self.askpass.suffix.lower() != ".exe":
            raise RuntimeError("源码模式不能执行SSH密码辅助程序；请使用已打包的正式版")

    def _environment(self) -> dict[str, str]:
        environment = os.environ.copy()
        environment.update({
            "SSH_ASKPASS": str(self.askpass),
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": "EES331_PL_RELOADER",
            "EES331_SSH_PASSWORD": self.password,
        })
        return environment

    def _ssh_options(self) -> list[str]:
        return [
            "-o", "BatchMode=no",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-o", "ConnectionAttempts=1",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
        ]

    @staticmethod
    def _run(
        args: list[str], *, input_text: str = "", timeout: float = 90,
        environment: dict[str, str] | None = None, cwd: Path | None = None,
        line_callback=None,
    ) -> tuple[int, str]:
        startup = None
        creation_flags = 0
        if sys.platform == "win32":
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creation_flags = subprocess.CREATE_NO_WINDOW
        process = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=environment,
            cwd=str(cwd) if cwd else None,
            startupinfo=startup,
            creationflags=creation_flags,
        )
        if line_callback is None:
            try:
                output, _ = process.communicate(input=input_text, timeout=timeout)
            except subprocess.TimeoutExpired:
                process.kill()
                output, _ = process.communicate()
                raise CommandFailure("远程命令超时", -1, output)
            return process.returncode, output

        output_parts = []

        def read_output() -> None:
            assert process.stdout is not None
            for raw_line in process.stdout:
                output_parts.append(raw_line)
                line_callback(raw_line.rstrip("\r\n"))

        reader = threading.Thread(target=read_output, daemon=True)
        reader.start()
        try:
            if process.stdin is not None:
                if input_text:
                    process.stdin.write(input_text)
                    process.stdin.flush()
                process.stdin.close()
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            reader.join(timeout=5)
            if process.stdout is not None:
                process.stdout.close()
            raise CommandFailure("远程命令超时", -1, "".join(output_parts))
        reader.join(timeout=5)
        if process.stdout is not None:
            process.stdout.close()
        return process.returncode, "".join(output_parts)

    def trust_and_connect(self) -> None:
        self.log(f"检查开发板网络端口 {self.host}:22……")
        tcp_preflight(self.host)
        self.log("网络端口可达；使用Windows OpenSSH登录并检查主机密钥……")
        args = [
            str(self.ssh), "-p", "22", *self._ssh_options(),
            f"{self.user}@{self.host}", "printf PL_RELOADER_CONNECTED",
        ]
        code, output = self._run(args, timeout=20, environment=self._environment())
        lowered = output.lower()
        if "host key verification failed" in lowered or "remote host identification has changed" in lowered:
            raise CommandFailure("SSH主机密钥冲突", code, output)
        if "permission denied" in lowered:
            raise CommandFailure("SSH认证（请核对用户名和密码）", code, output)
        if code or "PL_RELOADER_CONNECTED" not in output:
            raise CommandFailure("SSH连接", code, output)
        self.log("SSH连接成功。")

    def remote(self, command: str, *, sudo: bool = False, timeout: float = 90) -> str:
        remote_command = command
        input_text = ""
        if sudo:
            remote_command = "sudo -S -p '' " + command
            input_text = self.password + "\n"
        args = [
            str(self.ssh), "-p", "22", *self._ssh_options(),
            f"{self.user}@{self.host}", remote_command,
        ]
        code, output = self._run(
            args, input_text=input_text, timeout=timeout, environment=self._environment(),
            line_callback=self.log,
        )
        if code:
            raise CommandFailure("板端命令", code, output)
        return output

    def upload_items(self, sources: list[Path], remote_parent: str) -> None:
        if not sources:
            return
        parent = sources[0].parent
        if any(source.parent != parent for source in sources):
            raise ValueError("一次SCP上传的文件必须位于同一目录")
        args = [
            str(self.scp), "-q", "-P", "22", *self._ssh_options(), "-r",
        ]
        args.extend([source.name for source in sources])
        args.append(f"{self.user}@{self.host}:{remote_parent}/")
        code, output = self._run(
            args, timeout=240, environment=self._environment(), cwd=parent
        )
        if code:
            raise CommandFailure("上传必要文件", code, output)

    def plain_status(self) -> str:
        return self.remote(
            "systemctl show ees331-camera -p MainPID -p ActiveState -p SubState; "
            "pgrep -af 'camera.py|camera_action_v1.py' || true"
        )

    def action_running(self) -> bool:
        # Match the real script name without matching the remote shell's own
        # command line, which contains the bracketed pattern literally.
        output = self.remote("pgrep -af '[c]amera_action_v1.py' || true")
        processes = real_action_processes(output)
        if processes:
            self.log("检测到真实动作进程：" + " | ".join(processes))
        return bool(processes)

    def sync_payload(self) -> None:
        validate_local_payload()
        self.log("本地BIT/HWH及13项发布清单验证通过。")
        self.remote(f"mkdir -p {REMOTE_DIR}")
        root = payload_dir()
        items = sorted(root.iterdir(), key=lambda item: item.name.lower())
        total = len(items) + (0 if (root / CONTROLLER).is_file() else 1)
        self.log(f"一次同步必要文件：载荷目录{len(items)}项，共{total}项")
        self.upload_items(items, REMOTE_DIR)
        if not (root / CONTROLLER).is_file():
            self.upload_items([controller_source()], REMOTE_DIR)
        self.log("文件同步完成，接下来由板端控制器再次逐项验签。")

    def ensure_controller(self) -> None:
        output = self.remote(f"test -f {REMOTE_DIR}/{CONTROLLER} && echo FOUND || true")
        if "FOUND" in output:
            return
        self.remote(f"mkdir -p {REMOTE_DIR}")
        self.upload_items([controller_source()], REMOTE_DIR)

    def controller(self, action: str, *, timeout: float) -> str:
        self.ensure_controller()
        command = (
            f"{BOARD_PYTHON} -u {REMOTE_DIR}/{CONTROLLER} {action} "
            f"--app-dir {REMOTE_DIR}"
        )
        return self.remote(command, sudo=True, timeout=timeout)


class ReloaderApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title(f"EES-331 PL 在线重加载 v{APP_VERSION}")
        self.root.geometry("820x610")
        self.root.minsize(720, 520)
        self.messages: queue.Queue[str] = queue.Queue()
        self.busy = False
        self.run_dir = self._new_run_dir()
        self.log_file = self.run_dir / "application.log"
        self.result_file = self.run_dir / "result.json"

        self.host = tk.StringVar(value="192.168.240.10")
        self.user = tk.StringVar(value="xilinx")
        self.password = tk.StringVar(value=DEFAULT_SSH_PASSWORD)
        self.baseline_ok = tk.BooleanVar(value=False)
        self.open_viewer = tk.BooleanVar(value=True)
        self.status_text = tk.StringVar(value="等待操作；当前不会自动修改开发板。")
        self._build_ui()
        self.root.after(100, self._drain_messages)
        self.log(f"本地证据目录：{self.run_dir}")

    @staticmethod
    def _new_run_dir() -> Path:
        root = local_log_root()
        root.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y-%m-%d_%H%M%S") + f"_{int(time.time_ns() % 1_000_000):06d}"
        path = root / f"{stamp}_pl_reloader_gui_run01"
        path.mkdir(exist_ok=False)
        return path

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=14)
        outer.pack(fill="both", expand=True)

        connection = ttk.LabelFrame(outer, text="开发板连接", padding=10)
        connection.pack(fill="x")
        ttk.Label(connection, text="IP").grid(row=0, column=0, sticky="w")
        ttk.Entry(connection, textvariable=self.host, width=20).grid(row=0, column=1, padx=(6, 16))
        ttk.Label(connection, text="用户名").grid(row=0, column=2, sticky="w")
        ttk.Entry(connection, textvariable=self.user, width=14).grid(row=0, column=3, padx=(6, 16))
        ttk.Label(connection, text="SSH密码").grid(row=0, column=4, sticky="w")
        ttk.Entry(connection, textvariable=self.password, show="●", width=18).grid(row=0, column=5, padx=(6, 0))

        checks = ttk.Frame(outer, padding=(0, 10))
        checks.pack(fill="x")
        ttk.Checkbutton(
            checks,
            text="我已确认当前原HDMI/UDP画面动态、流畅",
            variable=self.baseline_ok,
        ).pack(side="left")
        ttk.Checkbutton(
            checks,
            text="加载成功后打开动作识别",
            variable=self.open_viewer,
        ).pack(side="right")

        buttons = ttk.Frame(outer)
        buttons.pack(fill="x", pady=(0, 10))
        self.status_button = ttk.Button(buttons, text="检查状态", command=self.check_status)
        self.load_button = ttk.Button(buttons, text="一键加载动作版PL", command=self.load_overlay)
        self.restore_button = ttk.Button(buttons, text="恢复原视频", command=self.restore_original)
        self.viewer_button = ttk.Button(buttons, text="打开动作识别", command=self.launch_viewer)
        for button in (self.status_button, self.load_button, self.restore_button, self.viewer_button):
            button.pack(side="left", padx=(0, 8))

        ttk.Label(outer, textvariable=self.status_text, foreground="#0b5cab").pack(fill="x", pady=(0, 8))
        log_frame = ttk.LabelFrame(outer, text="完整过程日志", padding=6)
        log_frame.pack(fill="both", expand=True)
        self.log_widget = tk.Text(log_frame, wrap="word", state="disabled", font=("Consolas", 10))
        scrollbar = ttk.Scrollbar(log_frame, command=self.log_widget.yview)
        self.log_widget.configure(yscrollcommand=scrollbar.set)
        self.log_widget.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        ttk.Label(
            outer,
            text="动作版不会设为开机自启；检测到动作版已运行时不会重复重加载。物理HDMI/LED仍需人工确认。",
        ).pack(fill="x", pady=(8, 0))

    def log(self, message: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        line = f"[{stamp}] {message}"
        self.messages.put(line)
        with self.log_file.open("a", encoding="utf-8") as stream:
            stream.write(line + "\n")

    def _drain_messages(self) -> None:
        while True:
            try:
                line = self.messages.get_nowait()
            except queue.Empty:
                break
            self.log_widget.configure(state="normal")
            self.log_widget.insert("end", line + "\n")
            self.log_widget.see("end")
            self.log_widget.configure(state="disabled")
        self.root.after(100, self._drain_messages)

    def _set_busy(self, busy: bool, status: str) -> None:
        self.busy = busy
        self.status_text.set(status)
        state = "disabled" if busy else "normal"
        for button in (self.status_button, self.load_button, self.restore_button, self.viewer_button):
            button.configure(state=state)

    def _connection_values(self) -> tuple[str, str, str]:
        return self.host.get(), self.user.get(), self.password.get()

    def _background(self, name: str, operation) -> None:
        if self.busy:
            return
        self._set_busy(True, name + "执行中……")

        def worker():
            result = {"operation": name, "state": "FAIL"}
            try:
                value = operation()
                result.update(state="PASS", value=value)
                self.log(name + "完成。")
                self.root.after(0, lambda: self.status_text.set(name + "完成"))
            except OperationSkipped as exc:
                result.update(state="SKIPPED", value=str(exc))
                self.log("未执行：" + str(exc))
                skipped_text = str(exc)
                self.root.after(0, lambda text=skipped_text: messagebox.showwarning(name + "未执行", text))
                self.root.after(0, lambda: self.status_text.set(name + "未执行"))
            except BaseException as exc:
                result["error"] = repr(exc)
                self.log("错误：" + str(exc))
                error_text = str(exc)
                self.root.after(0, lambda text=error_text: messagebox.showerror(name + "失败", text))
                self.root.after(0, lambda: self.status_text.set(name + "失败，已保留日志"))
            finally:
                result["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
                self.result_file.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
                self.root.after(0, lambda: self.password.set(DEFAULT_SSH_PASSWORD))
                self.root.after(0, lambda: self._set_busy(False, self.status_text.get()))

        threading.Thread(target=worker, daemon=True).start()

    def check_status(self) -> None:
        connection = self._connection_values()

        def operation():
            client = BoardClient(*connection, self.log)
            client.trust_and_connect()
            return client.plain_status()
        self._background("状态检查", operation)

    def load_overlay(self) -> None:
        if not self.baseline_ok.get():
            messagebox.showwarning("尚未确认基线", "请先确认原HDMI/UDP画面动态流畅并勾选确认框。")
            return
        if not messagebox.askokcancel(
            "开始在线重加载",
            "即将短暂中断原HDMI/UDP，上传并验签文件，然后单次加载动作版PL。继续吗？",
        ):
            return
        connection = self._connection_values()
        open_after = self.open_viewer.get()

        def operation():
            client = BoardClient(*connection, self.log)
            client.trust_and_connect()
            if client.action_running():
                raise OperationSkipped(
                    "检测到真实动作进程，出于安全原因未执行C→C重载。"
                    "这不代表本次加载成功；请先检查状态，或恢复原视频后再加载。"
                )
            client.sync_payload()
            output = client.controller("load", timeout=180)
            if '"event": "ACTION_OVERLAY_READY"' not in output:
                raise RuntimeError("板端未返回ACTION_OVERLAY_READY")
            self.log("动作版PL、视频和AXI服务已READY；请观察HDMI并核对LED。")
            if open_after:
                self.root.after(0, self.launch_viewer)
            return "ACTION_OVERLAY_READY"

        self._background("动作版PL加载", operation)

    def restore_original(self) -> None:
        if not messagebox.askokcancel("恢复原视频", "将停止动作版进程并重新加载原视频Overlay。继续吗？"):
            return
        connection = self._connection_values()

        def operation():
            client = BoardClient(*connection, self.log)
            client.trust_and_connect()
            output = client.controller("restore", timeout=120)
            if '"event": "ORIGINAL_RESTORE_READY"' not in output:
                raise RuntimeError("板端未返回ORIGINAL_RESTORE_READY")
            self.log("原视频服务已重新产帧；仍请人工确认HDMI/UDP动态画面。")
            return "ORIGINAL_RESTORE_READY"

        self._background("原视频恢复", operation)

    def launch_viewer(self) -> None:
        candidates = [
            executable_root().parent / "EES331_Action_Viewer_v1.0" / "Start_Action_Verification.ps1",
            Path("E:/competition/8_tools/EES331_Action_Viewer_v1.0/Start_Action_Verification.ps1"),
        ]
        script = next((path for path in candidates if path.is_file()), None)
        if script is None:
            messagebox.showerror("未找到动作识别", "请保留EES331_Action_Viewer_v1.0工具目录。")
            return
        subprocess.Popen([
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(script), "-BoardHost", self.host.get().strip(),
        ])
        self.log("已启动动作识别上位机。")


def self_test(output_path: str | None = None) -> int:
    manifest = validate_local_payload()
    result = {
        "marker": "PL_RELOADER_SELF_TEST_PASS",
        "version": APP_VERSION,
        "payload_files": len(manifest["files"]),
        "bit_sha256": manifest["files"]["display_test_axi_action_uart.bit"]["sha256"],
        "hwh_sha256": manifest["files"]["display_test_axi_action_uart.hwh"]["sha256"],
        "ssh": str(find_openssh("ssh.exe")),
        "scp": str(find_openssh("scp.exe")),
        "askpass": str(askpass_helper()),
        "controller": str(controller_source()),
    }
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if output_path:
        Path(output_path).write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--self-test-output")
    args, _ = parser.parse_known_args()
    if args.self_test:
        return self_test(args.self_test_output)
    root = tk.Tk()
    ReloaderApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
