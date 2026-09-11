import copy,json,os,subprocess,sys,tkinter as tk,unittest,zipfile
from pathlib import Path

R=Path(__file__).resolve().parent; W=R.parents[2]; APP=W/'3_host/pynq/sd_boot_builder_v02'
sys.path.insert(0,str(APP)); sys.path.insert(0,str(W/'4_metrics/logs/2026-09-10_sd_builder_toolkit_run01/python_deps'))
from hardware import BuildError,read_xsa,ps_parameters
from board_profile import compatible_board,dts_rules,validate_generated
from builder import ASSETS,Builder,DEFAULT_BASE,validate_dtb
from images import verify_base,BASE_HASH
from fdt_reader import parse,be,text
from app import Application,MODES

XSA=W/'2_fpga/3_pynq_test/vitis/pynq_test_wrapper.xsa'
BASE=(ASSETS/'system.dtb').read_bytes()
REF=ps_parameters((ASSETS/'reference.hwh').read_bytes())[1]
DTC=Path('F:/vivado2025/2025.2/Vitis/bin/dtc.exe')

def generate(name,updates,usb_role='otg'):
    ps=dict(REF); ps.update(updates)
    profile=compatible_board(ps,REF)
    if profile['requirements']: raise BuildError('\n'.join(profile['requirements']))
    folder=R/'dt_tests'/name; folder.mkdir(parents=True,exist_ok=True)
    (folder/'base.dtb').write_bytes(BASE)
    def run(args):
        result=subprocess.run([str(DTC),*args],cwd=folder,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        with (folder/'dtc.log').open('ab') as f:f.write(result.stdout)
        if result.returncode: raise AssertionError(result.stdout.decode(errors='replace'))
    run(['-I','dtb','-O','dts','-o','base.dts','base.dtb'])
    (folder/'board.dts').write_text(dts_rules(ps,REF,BASE,usb_role),encoding='utf-8')
    run(['-I','dts','-O','dtb','-o','system.dtb','board.dts'])
    data=(folder/'system.dtb').read_bytes(); validate_dtb(data,ps); validate_generated(data,ps)
    run(['-I','dtb','-O','dts','-o','roundtrip.dts','system.dtb'])
    return parse(data)

class Rules(unittest.TestCase):
    def test_auxiliary_hwh_supported(self):
        path=R/'auxiliary_hwh.xsa'
        with zipfile.ZipFile(XSA) as source,zipfile.ZipFile(path,'w') as out:
            for name in source.namelist(): out.writestr(name,source.read(name))
            out.writestr('smartconnect.hwh','<SYSTEM><MODULES><MODULE MODTYPE="smartconnect"/></MODULES></SYSTEM>')
        summary,_=read_xsa(path,ASSETS)
        self.assertEqual(summary['auxiliary_hwh'],['smartconnect.hwh'])
        self.assertEqual(summary['status'],'AUTO_READY')

    def test_ambiguous_system_hwh_rejected(self):
        path=R/'ambiguous_hwh.xsa'
        with zipfile.ZipFile(XSA) as source,zipfile.ZipFile(path,'w') as out:
            for name in source.namelist(): out.writestr(name,source.read(name))
            name=next(n for n in source.namelist() if n.endswith('.hwh'))
            out.writestr('second_system.hwh',source.read(name))
        with self.assertRaisesRegex(BuildError,'系统 HWH'): read_xsa(path,ASSETS)

    def test_real_display_xsa_sd_disabled_rejected(self):
        with self.assertRaisesRegex(BuildError,'PCW_SD0_PERIPHERAL_ENABLE'):
            read_xsa(W/'2_fpga/0_diaplay_test/vitis/display_test_wrapper.xsa',ASSETS)

    def test_baseline_auto(self):
        info,_=read_xsa(XSA,ASSETS)
        self.assertEqual(info['status'],'AUTO_READY')
        self.assertEqual(info['board_profile']['requirements'],[])
        d=generate('baseline',{})
        self.assertEqual(be(d['/axi/ethernet@e000b000/ethernet-phy@0']['reset-gpios'],4),47)

    def test_uart0_auto(self):
        d=generate('uart0',{'PCW_UART0_PERIPHERAL_ENABLE':'1','PCW_UART0_UART0_IO':'MIO 50 .. 51'})
        self.assertEqual(text(d['/aliases']['serial1']),'/axi/serial@e0000000')
        self.assertEqual(be(d['/axi/serial@e0000000']['port-number']),1)
        self.assertEqual(text(d['/aliases']['serial0']),'/axi/serial@e0001000')

    def test_usb_auto(self):
        d=generate('usb',{'PCW_USB0_PERIPHERAL_ENABLE':'1','PCW_USB0_USB0_IO':'MIO 28 .. 39',
                         'PCW_USB0_RESET_ENABLE':'1','PCW_USB0_RESET_IO':'MIO 46'},'host')
        self.assertEqual(text(d['/axi/usb@e0002000']['dr_mode']),'host')
        self.assertEqual(be(d['/ees331-usb-phy']['reset-gpios'],4),46)
        self.assertEqual(be(d['/ees331-usb-phy']['reset-gpios'],8),1)

    def test_usb_incomplete_rejected(self):
        ps=dict(REF,PCW_USB0_PERIPHERAL_ENABLE='1')
        with self.assertRaisesRegex(BuildError,'MIO 28'): compatible_board(ps,REF)

    def test_qspi_auto(self):
        d=generate('qspi',{'PCW_QSPI_PERIPHERAL_ENABLE':'1','PCW_QSPI_QSPI_IO':'MIO 1 .. 6'})
        flash=d['/axi/spi@e000d000/flash@0']
        self.assertIn(b'n25q256a',flash['compatible'])
        self.assertEqual(be(flash['reg']),0)
        self.assertEqual(be(flash['spi-max-frequency']),50000000)

    def test_i2c_auto_software_bus_speed(self):
        d=generate('i2c',{'PCW_I2C0_PERIPHERAL_ENABLE':'1','PCW_I2C0_I2C0_IO':'EMIO','PCW_I2C_PERIPHERAL_FREQMHZ':'25'})
        self.assertEqual(be(d['/axi/i2c@e0004000']['clock-frequency']),100000)

    def test_spi_auto_chip_select(self):
        d=generate('spi',{'PCW_SPI1_PERIPHERAL_ENABLE':'1','PCW_SPI1_SPI1_IO':'EMIO','PCW_SPI1_GRP_SS2_ENABLE':'1'})
        self.assertEqual(be(d['/axi/spi@e0007000']['num-cs']),3)

    def test_can_auto_external_clock(self):
        d=generate('can',{'PCW_CAN0_PERIPHERAL_ENABLE':'1','PCW_CAN0_CAN0_IO':'EMIO','PCW_CAN0_PERIPHERAL_FREQMHZ':'24'})
        self.assertEqual(be(d['/ees331-can0-clock']['clock-frequency']),24000000)

    def test_can_missing_clock_rejected(self):
        ps=dict(REF,PCW_CAN0_PERIPHERAL_ENABLE='1',PCW_CAN0_CAN0_IO='EMIO')
        with self.assertRaisesRegex(BuildError,'频率'): compatible_board(ps,REF)

    def test_sd_card_detect_disabled(self):
        d=generate('sd_cd',{'PCW_SD0_GRP_CD_ENABLE':'0'})
        self.assertIn('broken-cd',d['/axi/mmc@e0100000'])

    def test_fclk_and_gpio_auto(self):
        d=generate('clock_gpio',{'PCW_FPGA_FCLK0_ENABLE':'1','PCW_FPGA_FCLK2_ENABLE':'1','PCW_GPIO_EMIO_GPIO_WIDTH':'12'})
        self.assertEqual(be(d['/axi/slcr@f8000000/clkc@100']['fclk-enable']),5)
        self.assertEqual(be(d['/axi/gpio@e000a000']['emio-gpio-width']),12)

    def test_controller_disable(self):
        d=generate('enet_disable',{'PCW_ENET0_PERIPHERAL_ENABLE':'0'})
        self.assertEqual(text(d['/axi/ethernet@e000b000']['status']),'disabled')

    def test_external_sd1_specific_requirement(self):
        profile=compatible_board(dict(REF,PCW_SD1_PERIPHERAL_ENABLE='1'),REF)
        self.assertTrue(any('SD1' in s for s in profile['requirements']))

    def test_gpio_or_clock_parameter_not_blanket_dtb_gate(self):
        ps=dict(REF,PCW_FCLK0_PERIPHERAL_DIVISOR0='5',PCW_DDR_WRITE_TO_CRITICAL_PRIORITY_LEVEL='3')
        self.assertEqual(compatible_board(ps,REF)['requirements'],[])

    def test_bad_bank_rejected(self):
        with self.assertRaisesRegex(BuildError,'BANK1'): compatible_board(dict(REF,PCW_PRESET_BANK1_VOLTAGE='LVCMOS 3.3V'),REF)

    def test_original_z2_rejected(self):
        with self.assertRaisesRegex(BuildError,'PYNQ-Z2'):
            verify_base(W/'3_host/pynq/download/pynq_z2_v3.0.1.img')

    def test_accepted_base_is_ees331(self):
        result=verify_base(DEFAULT_BASE)
        self.assertEqual(result['sha256'],BASE_HASH)
        self.assertEqual(result['board'],'EES-331')

    def test_missing_bit_still_rejected(self):
        target=R/'missing_bit.xsa'
        with zipfile.ZipFile(XSA) as s,zipfile.ZipFile(target,'w') as t:
            for n in s.namelist():
                if not n.endswith('.bit'): t.writestr(n,s.read(n))
        with self.assertRaisesRegex(BuildError,'bit'): read_xsa(target,ASSETS)

    def test_gui_hides_advanced_and_uses_new_base(self):
        root=tk.Tk(); root.withdraw()
        try:
            ui=Application(root); root.update_idletasks()
            self.assertFalse(ui.advanced_shown)
            self.assertEqual(ui.dtb.get(),'')
            self.assertIn('ees331',ui.base.get())
            self.assertNotIn('pynq_z2',ui.base.get())
            self.assertIn('v0.2',root.title())
            ui.toggle.invoke(); root.update_idletasks()
            self.assertTrue(ui.advanced_shown)
            # Read widget texts, including hidden advanced labels.
            def labels(widget):
                out=[]
                try: out.append(str(widget.cget('text')))
                except tk.TclError: pass
                for c in widget.winfo_children(): out+=labels(c)
                return out
            self.assertFalse(any('PYNQ-Z2' in s for s in labels(root)))
            ui.mode.set('Linux 启动后由 PYNQ 自动加载')
            self.assertEqual(MODES[ui.mode.get()],'linux')
        finally: root.destroy()

if __name__=='__main__': unittest.main(verbosity=2)
