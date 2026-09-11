import json
from pathlib import Path
import sys
import tkinter as tk
import unittest
import xml.etree.ElementTree as ET
import zipfile

R=Path(__file__).resolve().parent
APP=R.parents[2]/'3_host/pynq/sd_boot_builder'
sys.path.insert(0,str(APP))
sys.path.insert(0,str(R/'python_deps'))
from hardware import BuildError,read_xsa,bit_info
from builder import ASSETS,inspect,validate_dtb
from app import Application,MODES

XSA=R.parents[2]/'2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa'
FIXTURES=R/'test_inputs'
FIXTURES.mkdir(exist_ok=True)

def mutant(name,remove_bit=False,parameter=None,part=None,truncate_bit=False):
    target=FIXTURES/(name+'.xsa')
    with zipfile.ZipFile(XSA) as src,zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED) as dest:
        for n in src.namelist():
            if remove_bit and n.endswith('.bit'): continue
            data=src.read(n)
            if parameter and n.endswith('.hwh'):
                root=ET.fromstring(data)
                module=next(m for m in root.iter('MODULE') if m.get('MODTYPE')=='processing_system7')
                for p in module.findall('./PARAMETERS/PARAMETER'):
                    if p.get('NAME')==parameter[0]: p.set('VALUE',parameter[1]); break
                else: raise AssertionError('parameter not found')
                data=ET.tostring(root)
            if part and n=='xsa.json':
                obj=json.loads(data); obj['devices'][0]['part']['name']=part; data=json.dumps(obj).encode()
            if truncate_bit and n.endswith('.bit'): data=data[:-100]
            dest.writestr(n,data)
    return target

class InputTests(unittest.TestCase):
    def test_reference_requires_no_ps_rebuild(self):
        result=inspect(XSA)
        self.assertEqual(result['status'],'PROFILE_COMPATIBLE')
        self.assertFalse(result['requires_fsbl_rebuild'])
        self.assertGreater(result['bit_header']['payload_size'],4000000)

    def test_missing_bit_rejected(self):
        with self.assertRaisesRegex(BuildError,'bit'):
            inspect(mutant('missing_bit',remove_bit=True))

    def test_wrong_part_rejected(self):
        with self.assertRaisesRegex(BuildError,'器件'):
            inspect(mutant('wrong_part',part='xc7z010clg400-1'))

    def test_changed_uart_pins_rejected(self):
        with self.assertRaisesRegex(BuildError,'不兼容'):
            inspect(mutant('wrong_uart',parameter=('PCW_UART1_UART1_IO','MIO 12 .. 13')))

    def test_truncated_bit_rejected(self):
        with self.assertRaisesRegex(BuildError,'bit'):
            inspect(mutant('truncated_bit',truncate_bit=True))

    def test_standalone_bit_not_accepted(self):
        with self.assertRaisesRegex(BuildError,'XSA'):
            inspect(FIXTURES/'design.bit')

    def test_fclk_change_rebuilds_without_external_dtb(self):
        result=inspect(mutant('fclk_change',parameter=('PCW_FPGA_FCLK0_ENABLE','1')))
        self.assertTrue(result['requires_fsbl_rebuild'])
        self.assertEqual(result['status'],'PROFILE_COMPATIBLE')
        self.assertEqual(len(result['ps_changes']),1)

    def test_usb_change_requires_board_dtb(self):
        result,data=read_xsa(mutant('usb_change',parameter=('PCW_USB0_PERIPHERAL_ENABLE','1')),ASSETS)
        self.assertEqual(result['status'],'NEEDS_BOARD_DTB')
        with self.assertRaisesRegex(BuildError,'状态不一致'):
            validate_dtb((ASSETS/'system.dtb').read_bytes(),data['ps'])

    def test_reference_dtb_valid(self):
        _,data=read_xsa(XSA,ASSETS)
        self.assertIn('/chosen',validate_dtb((ASSETS/'system.dtb').read_bytes(),data['ps']))

    def test_gui_constructs_and_requires_xsa(self):
        root=tk.Tk(); root.withdraw()
        try:
            app=Application(root); root.update_idletasks()
            self.assertEqual(app.xsa.get(),'')
            self.assertTrue(app.full.get())
            self.assertEqual(MODES[app.mode.get()],'manual')
            self.assertFalse(app.busy)
        finally: root.destroy()

if __name__=='__main__': unittest.main(verbosity=2)
