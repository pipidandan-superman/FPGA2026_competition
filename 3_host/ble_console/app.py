"""Tkinter front end for the extensible EES-331 BLE GATT console."""

from __future__ import annotations

import argparse
import json
import queue
import sys
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import messagebox, ttk

from ble_backend import BackendEvent, BleWorker
from config_store import AppConfig, default_config_path, load_config, save_config
from protocols import encode_payload, find_characteristic, format_payload


APP_NAME = "EES331 BLE Console"
APP_VERSION = "1.0.0"


class BleConsoleApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title(f"{APP_NAME} v{APP_VERSION}")
        self.root.geometry("1180x780")
        self.root.minsize(980, 680)

        try:
            self.config = load_config()
            config_error = ""
        except Exception as exc:  # noqa: BLE001 - GUI must recover bad config
            self.config = AppConfig()
            config_error = str(exc)

        self.worker = BleWorker()
        self.devices_by_label: dict[str, dict[str, object]] = {}
        self.characteristics: list[dict[str, object]] = []
        self.connected = False
        self.notify_active = False
        self.periodic_job: str | None = None
        self.session_log_path = self._create_session_log()

        self._create_variables()
        self._build_ui()
        self._apply_config_to_ui()
        self.worker.start()
        self.root.after(50, self._poll_events)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self._log("INFO", f"启动 {APP_NAME} v{APP_VERSION}")
        self._log("INFO", f"配置文件：{default_config_path()}")
        self._log("INFO", f"会话日志：{self.session_log_path}")
        if config_error:
            self._log("WARN", f"配置读取失败，已使用默认值：{config_error}")

    def _create_variables(self) -> None:
        self.status_var = tk.StringVar(value="未连接")
        self.device_filter_var = tk.StringVar()
        self.address_var = tk.StringVar()
        self.scan_timeout_var = tk.StringVar()
        self.connect_timeout_var = tk.StringVar()
        self.device_choice_var = tk.StringVar()
        self.service_uuid_var = tk.StringVar()
        self.write_uuid_var = tk.StringVar()
        self.notify_uuid_var = tk.StringVar()
        self.response_var = tk.BooleanVar()
        self.tx_mode_var = tk.StringVar()
        self.append_var = tk.StringVar()
        self.tx_payload_var = tk.StringVar(value="55 AA 31 32")
        self.interval_var = tk.StringVar()
        self.periodic_var = tk.BooleanVar(value=False)
        self.preset_var = tk.StringVar()

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(3, weight=1)

        connection = ttk.LabelFrame(self.root, text="1. 设备扫描与连接")
        connection.grid(row=0, column=0, sticky="ew", padx=8, pady=(8, 4))
        connection.columnconfigure(3, weight=1)

        ttk.Label(connection, text="名称过滤").grid(row=0, column=0, padx=5, pady=5)
        ttk.Entry(connection, textvariable=self.device_filter_var, width=16).grid(
            row=0, column=1, padx=5, pady=5
        )
        ttk.Label(connection, text="扫描秒数").grid(row=0, column=2, padx=5, pady=5)
        ttk.Entry(connection, textvariable=self.scan_timeout_var, width=7).grid(
            row=0, column=3, sticky="w", padx=5, pady=5
        )
        self.scan_button = ttk.Button(connection, text="扫描", command=self._scan)
        self.scan_button.grid(row=0, column=4, padx=5, pady=5)
        ttk.Label(connection, text="状态").grid(row=0, column=5, padx=5, pady=5)
        ttk.Label(connection, textvariable=self.status_var, foreground="#0060a8").grid(
            row=0, column=6, padx=5, pady=5
        )

        ttk.Label(connection, text="扫描结果").grid(row=1, column=0, padx=5, pady=5)
        self.device_combo = ttk.Combobox(
            connection,
            textvariable=self.device_choice_var,
            state="readonly",
            width=52,
        )
        self.device_combo.grid(row=1, column=1, columnspan=3, sticky="ew", padx=5, pady=5)
        self.device_combo.bind("<<ComboboxSelected>>", self._device_selected)
        ttk.Label(connection, text="地址").grid(row=1, column=4, padx=5, pady=5)
        ttk.Entry(connection, textvariable=self.address_var, width=20).grid(
            row=1, column=5, padx=5, pady=5
        )
        self.connect_button = ttk.Button(connection, text="连接", command=self._connect)
        self.connect_button.grid(row=1, column=6, padx=5, pady=5)
        self.disconnect_button = ttk.Button(
            connection,
            text="断开",
            command=self._disconnect,
            state="disabled",
        )
        self.disconnect_button.grid(row=1, column=7, padx=5, pady=5)

        parameters = ttk.LabelFrame(self.root, text="2. 实时连接参数（修改后立即用于下一操作）")
        parameters.grid(row=1, column=0, sticky="ew", padx=8, pady=4)
        parameters.columnconfigure(1, weight=1)
        parameters.columnconfigure(3, weight=1)
        parameters.columnconfigure(5, weight=1)

        ttk.Label(parameters, text="Service UUID").grid(row=0, column=0, padx=5, pady=5)
        ttk.Entry(parameters, textvariable=self.service_uuid_var).grid(
            row=0, column=1, sticky="ew", padx=5, pady=5
        )
        ttk.Label(parameters, text="Write UUID").grid(row=0, column=2, padx=5, pady=5)
        ttk.Entry(parameters, textvariable=self.write_uuid_var).grid(
            row=0, column=3, sticky="ew", padx=5, pady=5
        )
        ttk.Label(parameters, text="Notify UUID").grid(row=0, column=4, padx=5, pady=5)
        ttk.Entry(parameters, textvariable=self.notify_uuid_var).grid(
            row=0, column=5, sticky="ew", padx=5, pady=5
        )
        ttk.Label(parameters, text="连接超时/s").grid(row=1, column=0, padx=5, pady=5)
        ttk.Entry(parameters, textvariable=self.connect_timeout_var, width=8).grid(
            row=1, column=1, sticky="w", padx=5, pady=5
        )
        ttk.Checkbutton(
            parameters,
            text="Write With Response",
            variable=self.response_var,
        ).grid(row=1, column=2, columnspan=2, sticky="w", padx=5, pady=5)
        ttk.Button(parameters, text="保存参数", command=self._save_config).grid(
            row=1, column=5, sticky="e", padx=5, pady=5
        )

        middle = ttk.Panedwindow(self.root, orient=tk.HORIZONTAL)
        middle.grid(row=2, column=0, sticky="nsew", padx=8, pady=4)

        services_frame = ttk.LabelFrame(middle, text="3. GATT服务与特征")
        send_frame = ttk.LabelFrame(middle, text="4. 数据收发")
        middle.add(services_frame, weight=3)
        middle.add(send_frame, weight=2)

        services_frame.columnconfigure(0, weight=1)
        services_frame.rowconfigure(0, weight=1)
        self.service_tree = ttk.Treeview(
            services_frame,
            columns=("uuid", "properties"),
            show="tree headings",
            height=11,
        )
        self.service_tree.heading("#0", text="类型")
        self.service_tree.heading("uuid", text="UUID")
        self.service_tree.heading("properties", text="属性")
        self.service_tree.column("#0", width=85, stretch=False)
        self.service_tree.column("uuid", width=330)
        self.service_tree.column("properties", width=180)
        self.service_tree.grid(row=0, column=0, sticky="nsew", padx=5, pady=5)
        self.service_tree.bind("<<TreeviewSelect>>", self._tree_selected)
        service_scroll = ttk.Scrollbar(
            services_frame,
            orient=tk.VERTICAL,
            command=self.service_tree.yview,
        )
        service_scroll.grid(row=0, column=1, sticky="ns")
        self.service_tree.configure(yscrollcommand=service_scroll.set)
        ttk.Button(
            services_frame,
            text="刷新服务",
            command=lambda: self.worker.submit("refresh_services"),
        ).grid(row=1, column=0, sticky="w", padx=5, pady=5)

        send_frame.columnconfigure(1, weight=1)
        ttk.Label(send_frame, text="预置指令").grid(row=0, column=0, padx=5, pady=5)
        self.preset_combo = ttk.Combobox(
            send_frame,
            textvariable=self.preset_var,
            state="readonly",
        )
        self.preset_combo.grid(row=0, column=1, sticky="ew", padx=5, pady=5)
        self.preset_combo.bind("<<ComboboxSelected>>", self._preset_selected)

        ttk.Label(send_frame, text="格式").grid(row=1, column=0, padx=5, pady=5)
        mode_frame = ttk.Frame(send_frame)
        mode_frame.grid(row=1, column=1, sticky="w")
        ttk.Radiobutton(mode_frame, text="HEX", value="hex", variable=self.tx_mode_var).pack(
            side=tk.LEFT
        )
        ttk.Radiobutton(mode_frame, text="UTF-8", value="utf8", variable=self.tx_mode_var).pack(
            side=tk.LEFT
        )

        ttk.Label(send_frame, text="行结束符").grid(row=2, column=0, padx=5, pady=5)
        ttk.Combobox(
            send_frame,
            textvariable=self.append_var,
            values=("none", "cr", "lf", "crlf"),
            state="readonly",
            width=10,
        ).grid(row=2, column=1, sticky="w", padx=5, pady=5)

        ttk.Label(send_frame, text="发送内容").grid(row=3, column=0, padx=5, pady=5)
        ttk.Entry(send_frame, textvariable=self.tx_payload_var).grid(
            row=3, column=1, sticky="ew", padx=5, pady=5
        )
        button_frame = ttk.Frame(send_frame)
        button_frame.grid(row=4, column=0, columnspan=2, sticky="ew", padx=5, pady=5)
        self.send_button = ttk.Button(
            button_frame,
            text="发送",
            command=self._send,
            state="disabled",
        )
        self.send_button.pack(side=tk.LEFT, padx=(0, 5))
        self.read_button = ttk.Button(
            button_frame,
            text="读取Notify UUID",
            command=self._read,
            state="disabled",
        )
        self.read_button.pack(side=tk.LEFT, padx=5)
        self.notify_button = ttk.Button(
            button_frame,
            text="订阅通知",
            command=self._toggle_notify,
            state="disabled",
        )
        self.notify_button.pack(side=tk.LEFT, padx=5)

        ttk.Checkbutton(
            send_frame,
            text="循环发送",
            variable=self.periodic_var,
            command=self._periodic_changed,
        ).grid(row=5, column=0, padx=5, pady=5)
        interval_frame = ttk.Frame(send_frame)
        interval_frame.grid(row=5, column=1, sticky="w")
        ttk.Entry(interval_frame, textvariable=self.interval_var, width=9).pack(side=tk.LEFT)
        ttk.Label(interval_frame, text=" ms（最小50）").pack(side=tk.LEFT)

        ttk.Label(
            send_frame,
            text="名称/PIN/波特率属于模块AT参数，必须经PL-UART配置桥且在未连接状态修改。",
            foreground="#9a5a00",
            wraplength=410,
        ).grid(row=6, column=0, columnspan=2, sticky="w", padx=5, pady=7)

        log_frame = ttk.LabelFrame(self.root, text="5. 实时通信日志")
        log_frame.grid(row=3, column=0, sticky="nsew", padx=8, pady=(4, 8))
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log_text = tk.Text(log_frame, wrap="none", height=13, state="disabled")
        self.log_text.grid(row=0, column=0, sticky="nsew")
        log_scroll_y = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        log_scroll_y.grid(row=0, column=1, sticky="ns")
        log_scroll_x = ttk.Scrollbar(log_frame, orient=tk.HORIZONTAL, command=self.log_text.xview)
        log_scroll_x.grid(row=1, column=0, sticky="ew")
        self.log_text.configure(
            yscrollcommand=log_scroll_y.set,
            xscrollcommand=log_scroll_x.set,
        )
        ttk.Button(log_frame, text="清空显示", command=self._clear_log).grid(
            row=2, column=0, sticky="w", padx=5, pady=4
        )

    def _apply_config_to_ui(self) -> None:
        config = self.config
        self.device_filter_var.set(config.device_name)
        self.address_var.set(config.device_address)
        self.scan_timeout_var.set(str(config.scan_timeout_s))
        self.connect_timeout_var.set(str(config.connect_timeout_s))
        self.service_uuid_var.set(config.service_uuid)
        self.write_uuid_var.set(config.write_uuid)
        self.notify_uuid_var.set(config.notify_uuid)
        self.response_var.set(config.write_with_response)
        self.tx_mode_var.set(config.tx_mode)
        self.append_var.set(config.append)
        self.interval_var.set(str(config.interval_ms))
        self.preset_combo["values"] = [item.name for item in config.presets]
        if config.presets:
            self.preset_var.set(config.presets[0].name)
            self._preset_selected()

    def _config_from_ui(self) -> AppConfig:
        config = AppConfig(
            device_name=self.device_filter_var.get().strip(),
            device_address=self.address_var.get().strip(),
            scan_timeout_s=float(self.scan_timeout_var.get()),
            connect_timeout_s=float(self.connect_timeout_var.get()),
            service_uuid=self.service_uuid_var.get().strip(),
            write_uuid=self.write_uuid_var.get().strip(),
            notify_uuid=self.notify_uuid_var.get().strip(),
            write_with_response=self.response_var.get(),
            tx_mode=self.tx_mode_var.get(),
            append=self.append_var.get(),
            interval_ms=int(self.interval_var.get()),
            presets=self.config.presets,
        )
        config.validate()
        return config

    def _save_config(self) -> None:
        try:
            self.config = self._config_from_ui()
            path = save_config(self.config)
        except Exception as exc:  # noqa: BLE001 - user input validation
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            return
        self._log("INFO", f"参数已保存：{path}")

    def _scan(self) -> None:
        try:
            timeout = float(self.scan_timeout_var.get())
            if timeout <= 0:
                raise ValueError
        except ValueError:
            messagebox.showerror(APP_NAME, "扫描秒数必须是正数", parent=self.root)
            return
        self.scan_button.configure(state="disabled")
        self.status_var.set("扫描中")
        self.worker.submit("scan", timeout=timeout)

    def _device_selected(self, _event: object | None = None) -> None:
        item = self.devices_by_label.get(self.device_choice_var.get())
        if item:
            self.address_var.set(str(item["address"]))

    def _connect(self) -> None:
        address = self.address_var.get().strip()
        if not address:
            messagebox.showerror(APP_NAME, "请扫描并选择设备，或填写设备地址", parent=self.root)
            return
        try:
            timeout = float(self.connect_timeout_var.get())
        except ValueError:
            messagebox.showerror(APP_NAME, "连接超时必须是数字", parent=self.root)
            return
        self.connect_button.configure(state="disabled")
        self.status_var.set("连接中")
        self.worker.submit("connect", address=address, timeout=timeout)

    def _disconnect(self) -> None:
        self.status_var.set("正在断开")
        self.worker.submit("disconnect")

    def _send(self) -> None:
        if not self.connected:
            return
        try:
            payload = encode_payload(
                self.tx_payload_var.get(),
                self.tx_mode_var.get(),
                self.append_var.get(),
            )
            if not payload:
                raise ValueError("发送内容不能为空")
            uuid = self.write_uuid_var.get().strip()
            if not uuid:
                raise ValueError("Write UUID不能为空")
        except ValueError as exc:
            messagebox.showerror(APP_NAME, str(exc), parent=self.root)
            self.periodic_var.set(False)
            return
        self.worker.submit(
            "write",
            uuid=uuid,
            payload=payload,
            response=self.response_var.get(),
        )

    def _read(self) -> None:
        uuid = self.notify_uuid_var.get().strip()
        if uuid:
            self.worker.submit("read", uuid=uuid)

    def _toggle_notify(self) -> None:
        uuid = self.notify_uuid_var.get().strip()
        if not uuid:
            messagebox.showerror(APP_NAME, "Notify UUID不能为空", parent=self.root)
            return
        action = "stop_notify" if self.notify_active else "start_notify"
        self.worker.submit(action, uuid=uuid)

    def _periodic_changed(self) -> None:
        if self.periodic_var.get():
            if not self.connected:
                self.periodic_var.set(False)
                messagebox.showerror(APP_NAME, "请先连接BLE设备", parent=self.root)
                return
            self._schedule_periodic(immediate=True)
        elif self.periodic_job:
            self.root.after_cancel(self.periodic_job)
            self.periodic_job = None

    def _schedule_periodic(self, immediate: bool = False) -> None:
        if not self.periodic_var.get() or not self.connected:
            self.periodic_job = None
            return
        try:
            interval = int(self.interval_var.get())
            if interval < 50:
                raise ValueError
        except ValueError:
            self.periodic_var.set(False)
            messagebox.showerror(APP_NAME, "循环发送间隔必须是不小于50的整数", parent=self.root)
            return
        if immediate:
            self._send()
        self.periodic_job = self.root.after(interval, self._periodic_tick)

    def _periodic_tick(self) -> None:
        self.periodic_job = None
        if self.periodic_var.get() and self.connected:
            self._send()
            self._schedule_periodic()

    def _preset_selected(self, _event: object | None = None) -> None:
        name = self.preset_var.get()
        for preset in self.config.presets:
            if preset.name == name:
                self.tx_mode_var.set(preset.mode)
                self.tx_payload_var.set(preset.payload)
                self.append_var.set(preset.append)
                return

    def _tree_selected(self, _event: object | None = None) -> None:
        selected = self.service_tree.selection()
        if not selected:
            return
        values = self.service_tree.item(selected[0], "values")
        if len(values) < 2:
            return
        uuid = str(values[0])
        properties = {item.strip().lower() for item in str(values[1]).split(",")}
        if "write" in properties or "write-without-response" in properties:
            self.write_uuid_var.set(uuid)
            self.response_var.set("write" in properties)
        if "notify" in properties or "indicate" in properties:
            self.notify_uuid_var.set(uuid)

    def _poll_events(self) -> None:
        while True:
            try:
                event = self.worker.events.get_nowait()
            except queue.Empty:
                break
            self._handle_event(event)
        self.root.after(50, self._poll_events)

    def _handle_event(self, event: BackendEvent) -> None:
        kind = event.kind
        data = event.data
        self._write_event_record(kind, data)

        if kind == "scan_started":
            self._log("INFO", f"开始扫描，超时 {data['timeout']} 秒")
        elif kind == "scan_complete":
            self.scan_button.configure(state="normal")
            self.status_var.set("扫描完成")
            self._show_devices(list(data["devices"]))
        elif kind == "connect_started":
            self._log("INFO", f"正在连接 {data['address']}")
        elif kind == "connected":
            self.connected = True
            self.status_var.set("已连接")
            self.connect_button.configure(state="disabled")
            self.disconnect_button.configure(state="normal")
            self.send_button.configure(state="normal")
            self.read_button.configure(state="normal")
            self.notify_button.configure(state="normal")
            self._log("INFO", f"连接成功，MTU={data['mtu_size']}")
        elif kind == "disconnected":
            self._set_disconnected_ui()
            reason = "主动断开" if data.get("expected") else "设备断开"
            self._log("WARN", reason)
        elif kind == "services":
            self._show_services(list(data["services"]))
        elif kind == "write_complete":
            hex_text, text = format_payload(bytes(data["payload"]))
            self._log("TX", f"{hex_text} | {text} | UUID={data['uuid']}")
        elif kind == "read_complete":
            hex_text, text = format_payload(bytes(data["payload"]))
            self._log("RX", f"READ {hex_text} | {text} | UUID={data['uuid']}")
        elif kind == "notification":
            hex_text, text = format_payload(bytes(data["payload"]))
            self._log("RX", f"NOTIFY {hex_text} | {text} | UUID={data['uuid']}")
        elif kind == "notify_started":
            self.notify_active = True
            self.notify_button.configure(text="停止通知")
            self._log("INFO", f"已订阅通知：{data['uuid']}")
        elif kind == "notify_stopped":
            self.notify_active = False
            self.notify_button.configure(text="订阅通知")
            self._log("INFO", f"已停止通知：{data['uuid']}")
        elif kind == "error":
            self.scan_button.configure(state="normal")
            if not self.connected:
                self.connect_button.configure(state="normal")
                self.status_var.set("操作失败")
            self._log("ERROR", f"{data['action']}：{data['message']}")
            messagebox.showerror(
                APP_NAME,
                f"{data['action']} 失败：\n{data['message']}",
                parent=self.root,
            )

    def _show_devices(self, devices: list[dict[str, object]]) -> None:
        name_filter = self.device_filter_var.get().strip().lower()
        self.devices_by_label.clear()
        for device in devices:
            name = str(device["name"])
            address = str(device["address"])
            if name_filter and name_filter not in name.lower():
                continue
            label = f"{name} | {address} | RSSI {device['rssi']} dBm"
            self.devices_by_label[label] = device
        labels = list(self.devices_by_label)
        self.device_combo["values"] = labels
        self._log("INFO", f"扫描到 {len(devices)} 个设备，过滤后 {len(labels)} 个")
        if labels:
            self.device_choice_var.set(labels[0])
            self._device_selected()

    def _show_services(self, services: list[dict[str, object]]) -> None:
        for item in self.service_tree.get_children():
            self.service_tree.delete(item)
        self.characteristics.clear()

        for service in services:
            service_id = self.service_tree.insert(
                "",
                tk.END,
                text="Service",
                values=(service["uuid"], ""),
                open=True,
            )
            for characteristic in service["characteristics"]:
                properties = list(characteristic["properties"])
                self.characteristics.append(dict(characteristic))
                self.service_tree.insert(
                    service_id,
                    tk.END,
                    text="Characteristic",
                    values=(characteristic["uuid"], ", ".join(properties)),
                )

        write_uuid = find_characteristic(
            self.characteristics,
            "write",
            self.write_uuid_var.get(),
        ) or find_characteristic(
            self.characteristics,
            "write-without-response",
            self.write_uuid_var.get(),
        )
        notify_uuid = find_characteristic(
            self.characteristics,
            "notify",
            self.notify_uuid_var.get(),
        ) or find_characteristic(
            self.characteristics,
            "indicate",
            self.notify_uuid_var.get(),
        )
        if write_uuid:
            self.write_uuid_var.set(write_uuid)
        if notify_uuid:
            self.notify_uuid_var.set(notify_uuid)
        self._log(
            "INFO",
            f"枚举 {len(services)} 个服务、{len(self.characteristics)} 个特征",
        )

    def _set_disconnected_ui(self) -> None:
        self.connected = False
        self.notify_active = False
        self.periodic_var.set(False)
        if self.periodic_job:
            self.root.after_cancel(self.periodic_job)
            self.periodic_job = None
        self.status_var.set("未连接")
        self.connect_button.configure(state="normal")
        self.disconnect_button.configure(state="disabled")
        self.send_button.configure(state="disabled")
        self.read_button.configure(state="disabled")
        self.notify_button.configure(state="disabled", text="订阅通知")

    def _create_session_log(self) -> Path:
        log_root = default_config_path().parent / "logs"
        log_root.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        return log_root / f"session_{stamp}.jsonl"

    def _write_event_record(self, kind: str, data: dict[str, object]) -> None:
        safe_data: dict[str, object] = {}
        for key, value in data.items():
            if isinstance(value, bytes):
                safe_data[key] = value.hex().upper()
            else:
                safe_data[key] = value
        record = {
            "time": datetime.now().isoformat(timespec="milliseconds"),
            "event": kind,
            "data": safe_data,
        }
        with self.session_log_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")

    def _log(self, level: str, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        self.log_text.configure(state="normal")
        self.log_text.insert(tk.END, f"[{stamp}] {level:<5} {message}\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state="disabled")

    def _clear_log(self) -> None:
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", tk.END)
        self.log_text.configure(state="disabled")

    def _on_close(self) -> None:
        self.periodic_var.set(False)
        if self.periodic_job:
            self.root.after_cancel(self.periodic_job)
        self.worker.stop()
        self.root.destroy()


def run_self_test(output_path: str = "") -> int:
    config = AppConfig()
    config.validate()
    payload = encode_payload("55 AA 31 32", "hex")
    if payload != bytes((0x55, 0xAA, 0x31, 0x32)):
        marker = "BLE_CONSOLE_SELF_TEST_FAIL"
        if output_path:
            Path(output_path).write_text(marker + "\n", encoding="utf-8")
        elif sys.stdout:
            print(marker)
        return 1
    marker = f"BLE_CONSOLE_SELF_TEST_PASS version={APP_VERSION}"
    if output_path:
        Path(output_path).write_text(marker + "\n", encoding="utf-8")
    elif sys.stdout:
        print(marker)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=APP_NAME)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--self-test-output", default="")
    args = parser.parse_args()
    if args.self_test:
        return run_self_test(args.self_test_output)

    root = tk.Tk()
    BleConsoleApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
