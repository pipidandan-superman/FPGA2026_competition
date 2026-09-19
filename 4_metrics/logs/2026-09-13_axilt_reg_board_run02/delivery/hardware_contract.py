"""Fail closed on the independent overlay's HWH reset wiring before download."""
import xml.etree.ElementTree as ET


def validate_reset_contract(path):
    root = ET.parse(path).getroot()
    modules = {m.get('INSTANCE'): m for m in root.iter('MODULE')}
    reset = modules['control_reset']
    params = {p.get('NAME'): p.get('VALUE') for p in reset.iter('PARAMETER')}
    if params.get('C_EXT_RESET_HIGH') != '0' or params.get('C_AUX_RESET_HIGH') != '0':
        raise ValueError('Expected active-low external and auxiliary resets')
    ports = {p.get('NAME'): p for p in reset.findall('./PORTS/PORT')}
    for port_name, constant, value in (('aux_reset_in', 'const_one', '1'),
                                       ('dcm_locked', 'const_one', '1'),
                                       ('mb_debug_sys_rst', 'const_zero', '0')):
        module = modules[constant]
        config = {p.get('NAME'): p.get('VALUE') for p in module.iter('PARAMETER')}
        output = module.find('./PORTS/PORT[@NAME="dout"]')
        if (int(config.get('CONST_VAL', '-1'), 0) != int(value) or output is None or
                not output.get('SIGNAME') or
                ports[port_name].get('SIGNAME') != output.get('SIGNAME')):
            raise ValueError('Unsafe reset wiring: ' + port_name)
    return dict(marker='AXILT_RESET_CONTRACT_PASS', aux_active_low=True,
                aux_constant=1, dcm_locked=1, debug_reset=0)
