#!/usr/bin/env python3
"""Fail-closed contract check for the integrated video/AXI action UART HWH."""
import argparse
import json
import xml.etree.ElementTree as ET


def _parameters(module):
    return {item.get("NAME"): item.get("VALUE")
            for item in module.iter("PARAMETER")}


def _connections(port):
    return {(item.get("INSTANCE"), item.get("PORT"))
            for item in port.findall("./CONNECTIONS/CONNECTION")}


def _number(value):
    return int(float(value))


def validate_action_hardware_contract(path):
    """Validate the hardware/software boundary before programming the PL."""
    root = ET.parse(path).getroot()
    modules = {item.get("INSTANCE"): item for item in root.iter("MODULE")}
    required_types = {
        "axi_action_0": "video_axi_action_uart_top",
        "axi_vdma_0": "axi_vdma",
        "rst_ps7_0_50M": "proc_sys_reset",
        "control_const_one": "xlconstant",
        "control_const_zero": "xlconstant",
    }
    for name, expected in required_types.items():
        if name not in modules or modules[name].get("MODTYPE") != expected:
            raise ValueError(f"Missing or wrong module {name}: expected {expected}")

    external = {item.get("NAME"): item
                for item in root.findall("./EXTERNALPORTS/PORT")}
    required_external = {
        "PL_RS232_TX": "O",
        "ACTION_LED": "O",
        "sccb_cfg_done_0": "O",
        "clk_in1_0": "I",
        "resetn_0": "I",
    }
    for name, direction in required_external.items():
        if name not in external or external[name].get("DIR") != direction:
            raise ValueError(f"Missing or wrong external port {name}")
    if any(name in external for name in ("BT_RX", "BT_TX", "PL_RS232_RX", "BRIDGE_READY")):
        raise ValueError("Unexpected bridge/BLE ports in action v1")
    if "ble_uart_bridge_0" in modules:
        raise ValueError("Transparent bridge must not own UART outputs")
    if {("axi_action_0", "PL_RS232_TX")} != _connections(external["PL_RS232_TX"]):
        raise ValueError("COM4 does not originate in the action core")
    if {("axi_action_0", "ACTION_LED")} != _connections(external["ACTION_LED"]):
        raise ValueError("LED outputs do not originate in the action core")
    clock_port = external["clk_in1_0"]
    if (_number(clock_port.get("CLKFREQUENCY", "0")) != 100_000_000 or
            ("clk_wiz_0", "clk_in1") not in _connections(clock_port)):
        raise ValueError("Camera reference clock changed")

    axi = modules["axi_action_0"]
    axi_params = _parameters(axi)
    if (int(axi_params.get("C_BASEADDR", "-1"), 0) != 0x43C00000 or
            int(axi_params.get("C_HIGHADDR", "-1"), 0) != 0x43C00FFF):
        raise ValueError("AXI-Lite module address parameters are wrong")
    axi_ports = {item.get("NAME"): item for item in axi.findall("./PORTS/PORT")}
    if (_number(axi_ports["clk"].get("CLKFREQUENCY", "0")) != 50_000_000 or
            axi_ports["resetn"].get("SIGNAME") !=
            "rst_ps7_0_50M_peripheral_aresetn"):
        raise ValueError("AXI-Lite clock/reset contract is wrong")

    ranges = {(item.get("INSTANCE"), int(item.get("BASEVALUE"), 0),
               int(item.get("HIGHVALUE"), 0))
              for item in root.iter("MEMRANGE")}
    if ("axi_action_0", 0x43C00000, 0x43C00FFF) not in ranges:
        raise ValueError("AXI-Lite address segment is missing")
    if ("axi_vdma_0", 0x43000000, 0x4300FFFF) not in ranges:
        raise ValueError("VDMA address segment changed")

    vdma_params = _parameters(modules["axi_vdma_0"])
    required_vdma = {
        "C_NUM_FSTORES": 3,
        "C_INCLUDE_SG": 0,
        "C_M_AXIS_MM2S_TDATA_WIDTH": 24,
        "C_S_AXIS_S2MM_TDATA_WIDTH": 24,
        "C_MM2S_GENLOCK_MODE": 3,
        "C_S2MM_GENLOCK_MODE": 2,
    }
    for name, expected in required_vdma.items():
        if _number(vdma_params.get(name, "-1")) != expected:
            raise ValueError(f"Unsupported VDMA parameter {name}")

    reset = modules["rst_ps7_0_50M"]
    reset_params = _parameters(reset)
    if (reset_params.get("C_EXT_RESET_HIGH") != "0" or
            reset_params.get("C_AUX_RESET_HIGH") != "0"):
        raise ValueError("Expected active-low external and auxiliary resets")
    reset_ports = {item.get("NAME"): item
                   for item in reset.findall("./PORTS/PORT")}
    for port_name, constant, value in (
            ("aux_reset_in", "control_const_one", 1),
            ("dcm_locked", "control_const_one", 1),
            ("mb_debug_sys_rst", "control_const_zero", 0)):
        constant_params = _parameters(modules[constant])
        constant_out = modules[constant].find('./PORTS/PORT[@NAME="dout"]')
        if (int(constant_params.get("CONST_VAL", "-1"), 0) != value or
                constant_out is None or not constant_out.get("SIGNAME") or
                reset_ports[port_name].get("SIGNAME") != constant_out.get("SIGNAME")):
            raise ValueError(f"Unsafe reset wiring: {port_name}")

    return {
        "marker": "ACTION_HARDWARE_CONTRACT_PASS",
        "design": root.find("./SYSTEMINFO").get("NAME"),
        "axi_lite_base": "0x43c00000",
        "axi_lite_range": 4096,
        "vdma_base": "0x43000000",
        "control_clock_hz": 50_000_000,
        "board_clock_hz": 100_000_000,
        "bluetooth_ports": 0,
        "action_leds": 7,
        "uart_baud": 9600,
        "bridge_ready_external": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("hwh")
    args = parser.parse_args()
    print(json.dumps(validate_action_hardware_contract(args.hwh), indent=2))


if __name__ == "__main__":
    main()
