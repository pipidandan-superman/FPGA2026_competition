"""Offline ext4 injection for the verified EES-331 PYNQ camera service."""
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

from hardware import BuildError, digest

APP_XSA_SHA256 = "d69fb256b66106da87514fc3821fe177bbe538c128e74485f43a4a265f092ebc"
APP_DIR = "/home/xilinx/ees331_camera"
APP_FILES = {
    "camera.py": "0755",
    "run_camera.sh": "0755",
    "install.sh": "0755",
    "inspect_board.py": "0755",
    "ees331-camera.service": "0644",
    "ees331_camera.network": "0644",
    "uEnv.txt": "0644",
}
SYSTEM_FILES = {
    "ees331-camera.service": ("/etc/systemd/system/ees331-camera.service", "0644"),
    "ees331_camera.network": ("/etc/network/interfaces.d/ees331_camera", "0644"),
}
ERROR_MARKERS = (
    "File not found by ext2_lookup",
    "No such file or directory",
    "Command not found",
    "while looking up",
    "Ext2 inode is not a directory",
    "Filesystem is read-only",
)


def _save(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def _tool_env(tool):
    env = os.environ.copy()
    tool = Path(tool).resolve()
    candidates = [tool.parent]
    if tool.parent.name.lower() == "sbin" and tool.parent.parent.name.lower() == "usr":
        candidates.append(tool.parent.parent.parent / "bin")
    env["PATH"] = os.pathsep.join(str(p) for p in candidates) + os.pathsep + env.get("PATH", "")
    return env


def find_debugfs(explicit=""):
    candidates = []
    if explicit:
        value = Path(explicit)
        if value.is_dir():
            candidates.extend((value / "debugfs.exe", value / "usr/sbin/debugfs.exe"))
        else:
            candidates.append(value)
    configured = os.environ.get("EES331_DEBUGFS", "")
    if configured:
        candidates.append(Path(configured))
    located = shutil.which("debugfs") or shutil.which("debugfs.exe")
    if located:
        candidates.append(Path(located))
    candidates.extend((
        Path("C:/cygwin64/usr/sbin/debugfs.exe"),
        Path("C:/cygwin/usr/sbin/debugfs.exe"),
    ))
    checked = []
    for candidate in candidates:
        candidate = candidate.expanduser()
        if not candidate.is_file():
            checked.append(str(candidate))
            continue
        result = subprocess.run(
            [str(candidate), "-V"],
            env=_tool_env(candidate),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        if result.returncode == 0 and "debugfs" in result.stdout.lower():
            return candidate.resolve(), result.stdout.strip()
        checked.append(str(candidate))
    raise BuildError(
        "整合 PYNQ 应用需要 Cygwin e2fsprogs 的 debugfs。"
        "请安装 e2fsprogs，或在高级设置中选择 debugfs.exe。已检查："
        + "; ".join(checked)
    )


def _cygpath(path):
    path = Path(path).resolve()
    drive = path.drive.rstrip(":").lower()
    if not drive:
        raise BuildError("ext4 暂存文件必须位于带盘符的本地路径。")
    tail = path.as_posix().split(":", 1)[1]
    return f"/cygdrive/{drive}{tail}"


def _run(args, log_path, env, timeout=1200):
    result = subprocess.run(
        [str(a) for a in args],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    Path(log_path).write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise BuildError(f"{Path(args[0]).name} 失败，见 {log_path}。")
    return result.stdout


def _debugfs_exists(debugfs, image, path, env):
    result = subprocess.run(
        [str(debugfs), "-R", f"stat {path}", str(image)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    output = result.stdout
    return result.returncode == 0 and "Inode:" in output and not any(marker in output for marker in ERROR_MARKERS)


def _parent_name(path):
    item = Path(path)
    parent = item.parent.as_posix()
    return (parent if parent != "." else "/", item.name)


def _ensure_dirs(debugfs, image, directories, env, commands):
    known = {"/"}
    for target in directories:
        current = ""
        for component in Path(target).parts:
            if component in ("/", "\\"):
                continue
            parent = current or "/"
            current = (current + "/" + component) if current else ("/" + component)
            if current in known:
                continue
            if not _debugfs_exists(debugfs, image, current, env):
                commands.extend((f"cd {parent}", f"mkdir {component}", f"set_inode_field {component} mode 040755"))
            known.add(current)


def _write_file_commands(debugfs, image, local, destination, mode, uid, gid, env, commands):
    parent, name = _parent_name(destination)
    if _debugfs_exists(debugfs, image, destination, env):
        commands.extend((f"cd {parent}", f"rm {name}"))
    commands.extend((
        f"cd {parent}",
        f"write {_cygpath(local)} {name}",
        f"set_inode_field {name} mode 010{mode}",
        f"set_inode_field {name} uid {uid}",
        f"set_inode_field {name} gid {gid}",
    ))


def prepare_application_bundle(assets, boot, xsa_sha256, staging):
    assets = Path(assets)
    boot = Path(boot)
    staging = Path(staging)
    if xsa_sha256.lower() != APP_XSA_SHA256:
        raise BuildError(
            "当前内置摄像头 PYNQ 应用只允许配对 XSA "
            + APP_XSA_SHA256
            + "；新 XSA 需要重新核对 VDMA 地址、寄存器和板测后更新应用契约。"
        )
    staging.mkdir(parents=True, exist_ok=False)
    records = {}
    for name in APP_FILES:
        source = assets / name
        if not source.is_file():
            raise BuildError("内置 PYNQ 应用资源缺失：" + name)
        target = staging / name
        shutil.copyfile(source, target)
        records[name] = {"size": target.stat().st_size, "sha256": digest(target.read_bytes())}
    for name in ("overlay.bit", "overlay.hwh"):
        source = boot / name
        if not source.is_file():
            raise BuildError("启动包未生成配对 Overlay：" + name)
        target = staging / name
        shutil.copyfile(source, target)
        records[name] = {"size": target.stat().st_size, "sha256": digest(target.read_bytes())}
    manifest = {
        "application": "ees331-camera",
        "version": "2026-09-11",
        "xsa_sha256": xsa_sha256.lower(),
        "service": "ees331-camera.service",
        "board_address": "192.168.240.10/24",
        "peer": "192.168.240.2:5000",
        "cma": "128M@0x10000000",
        "files": records,
        "hardware_status": "REQUIRES_COLD_BOOT_VALIDATION",
    }
    _save(staging / "deployment_manifest.json", manifest)
    return manifest


def inject_application(root_image, staging, debugfs_path, evidence_dir, log=lambda line: None):
    root_image = Path(root_image)
    staging = Path(staging)
    evidence_dir = Path(evidence_dir)
    debugfs, version = find_debugfs(debugfs_path)
    env = _tool_env(debugfs)
    e2fsck = debugfs.parent / "e2fsck.exe"
    if not e2fsck.is_file():
        raise BuildError("debugfs 同目录缺少 e2fsck.exe，不能执行 ext4 完整性检查。")
    log("使用 ext4 工具：" + str(debugfs))
    _run([e2fsck, "-fn", root_image], evidence_dir / "rootfs_e2fsck_before.log", env)

    directories = {
        APP_DIR,
        "/etc/network/interfaces.d",
        "/etc/systemd/system",
        "/etc/systemd/system/multi-user.target.wants",
    }
    commands = []
    _ensure_dirs(debugfs, root_image, sorted(directories), env, commands)
    commands.extend((
        "cd /home/xilinx",
        "set_inode_field ees331_camera mode 040755",
        "set_inode_field ees331_camera uid 1000",
        "set_inode_field ees331_camera gid 1000",
    ))
    for name, mode in APP_FILES.items():
        _write_file_commands(
            debugfs, root_image, staging / name, f"{APP_DIR}/{name}", mode, 1000, 1000, env, commands
        )
    for name in ("overlay.bit", "overlay.hwh", "deployment_manifest.json"):
        mode = "0644"
        _write_file_commands(
            debugfs, root_image, staging / name, f"{APP_DIR}/{name}", mode, 1000, 1000, env, commands
        )
    for name, (destination, mode) in SYSTEM_FILES.items():
        _write_file_commands(debugfs, root_image, staging / name, destination, mode, 0, 0, env, commands)
    link = "/etc/systemd/system/multi-user.target.wants/ees331-camera.service"
    link_parent, link_name = _parent_name(link)
    if _debugfs_exists(debugfs, root_image, link, env):
        commands.extend((f"cd {link_parent}", f"rm {link_name}"))
    commands.extend((f"cd {link_parent}", f"symlink {link_name} ../ees331-camera.service"))

    command_file = evidence_dir / "rootfs_debugfs_write.cmd"
    command_file.write_text("\n".join(commands) + "\n", encoding="ascii")
    output = _run(
        [debugfs, "-w", "-f", command_file, root_image],
        evidence_dir / "rootfs_debugfs_write.log",
        env,
    )
    errors = [line for line in output.splitlines() if any(marker in line for marker in ERROR_MARKERS)]
    if errors:
        raise BuildError("ext4 写入日志包含错误：" + " | ".join(errors[:4]))

    expected = {}
    readback = evidence_dir / "rootfs_readback"
    readback.mkdir(exist_ok=False)
    commands = []
    destinations = {
        **{f"{APP_DIR}/{name}": staging / name for name in APP_FILES},
        f"{APP_DIR}/overlay.bit": staging / "overlay.bit",
        f"{APP_DIR}/overlay.hwh": staging / "overlay.hwh",
        f"{APP_DIR}/deployment_manifest.json": staging / "deployment_manifest.json",
        **{destination: staging / name for name, (destination, _) in SYSTEM_FILES.items()},
    }
    for index, (destination, source) in enumerate(destinations.items()):
        parent, name = _parent_name(destination)
        target = readback / f"{index:02d}_{name}"
        commands.extend((f"cd {parent}", f"dump {name} {_cygpath(target)}"))
        expected[str(destination)] = {
            "source_sha256": digest(Path(source).read_bytes()),
            "readback": target,
        }
    command_file = evidence_dir / "rootfs_debugfs_readback.cmd"
    command_file.write_text("\n".join(commands) + "\n", encoding="ascii")
    output = _run(
        [debugfs, "-f", command_file, root_image],
        evidence_dir / "rootfs_debugfs_readback.log",
        env,
    )
    errors = [line for line in output.splitlines() if any(marker in line for marker in ERROR_MARKERS)]
    if errors:
        raise BuildError("ext4 读回日志包含错误：" + " | ".join(errors[:4]))
    result_files = {}
    for destination, record in expected.items():
        target = record.pop("readback")
        if not target.is_file():
            raise BuildError("ext4 未读回文件：" + destination)
        actual = digest(target.read_bytes())
        if actual != record["source_sha256"]:
            raise BuildError("ext4 文件读回哈希不匹配：" + destination)
        result_files[destination] = {**record, "readback_sha256": actual}
    link_output = subprocess.run(
        [str(debugfs), "-R", f"stat {link}", str(root_image)],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    ).stdout
    (evidence_dir / "rootfs_service_link.log").write_text(link_output, encoding="utf-8")
    if 'Fast link dest: "../ees331-camera.service"' not in link_output:
        raise BuildError("systemd 服务启用链接读回不匹配。")
    _run([e2fsck, "-fn", root_image], evidence_dir / "rootfs_e2fsck_after.log", env)
    result = {
        "result": "PYNQ_ROOTFS_INJECTION_PASS",
        "debugfs": str(debugfs),
        "debugfs_version": version,
        "files": result_files,
        "service_link": "../ees331-camera.service",
        "filesystem_check": "PASS",
        "hardware_status": "REQUIRES_COLD_BOOT_VALIDATION",
    }
    _save(evidence_dir / "rootfs_application_validation.json", result)
    return result
