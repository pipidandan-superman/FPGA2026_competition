"""EES-331 PS-to-Linux rules, separate from the archived v0.1 implementation.

Controller registers/IRQs/clock-provider IDs come from the Linux 5.15 board
template; XSA determines enable/routing/PS initialization. External devices
are supplied only by the verified EES-331 board profile, not inferred from IP.
"""
import re
from hardware import BuildError
from fdt_reader import parse,be,text

CONTROLLERS={
 'UART0':'serial@e0000000','UART1':'serial@e0001000',
 'SD0':'mmc@e0100000','SD1':'mmc@e0101000',
 'ENET0':'ethernet@e000b000','ENET1':'ethernet@e000c000',
 'USB0':'usb@e0002000','USB1':'usb@e0003000',
 'I2C0':'i2c@e0004000','I2C1':'i2c@e0005000',
 'SPI0':'spi@e0006000','SPI1':'spi@e0007000','QSPI':'spi@e000d000',
 'CAN0':'can@e0008000','CAN1':'can@e0009000','WDT':'watchdog@f8005000',
}

def enabled(ps,name):
    return ps.get(f'PCW_{name}_PERIPHERAL_ENABLE','0')=='1'

def integer(ps,key,default=0):
    try: return int(float(ps.get(key,str(default))))
    except (ValueError,TypeError): raise BuildError('XSA 参数不是有效数值：'+key)

def routing(ps,name):
    return ps.get(f'PCW_{name}_{name}_IO','<Select>')

def compatible_board(ps,ref):
    """Return actionable requirements, not a blanket DTB gate on any PCW diff."""
    errors=[]; requirements=[]; warnings=[]
    def expect(key,value):
        if ps.get(key)!=value: errors.append(f'{key}={ps.get(key)}；EES-331 需要 {value}')
    # Console, SD boot path, physical oscillator and DDR remain board constraints.
    for key,value in {
        'PCW_PRESET_BANK0_VOLTAGE':'LVCMOS 3.3V','PCW_PRESET_BANK1_VOLTAGE':'LVCMOS 1.8V',
        'PCW_UIPARAM_DDR_BUS_WIDTH':'32 Bit','PCW_UIPARAM_DDR_MEMORY_TYPE':'DDR 3',
        'PCW_SD0_GRP_WP_ENABLE':'0',
    }.items(): expect(key,value)
    if enabled(ps,'UART0'): expect('PCW_UART0_UART0_IO','MIO 50 .. 51')
    if enabled(ps,'ENET0'):
        for key,value in {'PCW_ENET0_ENET0_IO':'MIO 16 .. 27','PCW_ENET0_GRP_MDIO_ENABLE':'1',
                          'PCW_ENET0_GRP_MDIO_IO':'MIO 52 .. 53','PCW_ENET0_RESET_ENABLE':'1',
                          'PCW_ENET0_RESET_IO':'MIO 47'}.items(): expect(key,value)
    if enabled(ps,'USB0'):
        for key,value in {'PCW_USB0_USB0_IO':'MIO 28 .. 39','PCW_USB0_RESET_ENABLE':'1',
                          'PCW_USB0_RESET_IO':'MIO 46'}.items(): expect(key,value)
        warnings.append('USB0 已生成 ULPI/复位配置；USB 角色必须与 JP6/JP7 跳帽一致，仍需板测。')
    if enabled(ps,'QSPI'):
        expect('PCW_QSPI_QSPI_IO','MIO 1 .. 6')
        if ps.get('PCW_QSPI_GRP_SS1_ENABLE','0')=='1': errors.append('EES-331 只有单片 QSPI Flash，不支持双片配置。')
    if ps.get('PCW_SD0_GRP_CD_ENABLE')=='1': expect('PCW_SD0_GRP_CD_IO','MIO 0')
    if ps.get('PCW_SD0_GRP_POW_ENABLE','0')=='1': requirements.append('SD0 启用了外部电源控制，需要电源 GPIO/极性/稳压器描述。')
    for name in ('SD1','ENET1','USB1'):
        if enabled(ps,name): requirements.append(f'{name} 不是模板中的板载连接，需要扩展接口/PHY/供电描述（可用高级 DTB 覆盖）。')
    for name in ('I2C0','I2C1','SPI0','SPI1','CAN0','CAN1'):
        if not enabled(ps,name): continue
        route=routing(ps,name)
        if route=='<Select>': errors.append(name+' 已启用但没有 MIO/EMIO 路由，请重新生成完整 XSA。')
        elif 'EMIO' not in route.upper():
            requirements.append(f'{name} 使用 {route}；不属于模板默认扩展 EMIO，需要确认引脚连接并提供高级 DTB。')
        warnings.append(name+' 控制器可自动生成；外接从设备/收发器及其 Linux 驱动不由控制器使能自动确定。')
        if ps.get(f'PCW_{name}_RESET_ENABLE','0')=='1':
            requirements.append(name+' 使用外部设备复位，需要从设备复位属性，控制器模板不能代替。')
        if name.startswith('CAN') and ps.get(f'PCW_{name}_PERIPHERAL_CLKSRC')=='External':
            freq=float(ps.get(f'PCW_{name}_PERIPHERAL_FREQMHZ','-1'))
            if freq<=0: errors.append(name+' 使用外部时钟但 XSA 未给出有效频率。')
    for name in ('NAND','NOR'):
        if enabled(ps,name): requirements.append(name+' 存储器未列入当前板级模板，需要芯片/时序/分区描述。')
    for i in range(2):
        if enabled(ps,f'TTC{i}') and any(ps.get(f'PCW_TTC{i}_CLK{j}_PERIPHERAL_CLKSRC','CPU_1X')!='CPU_1X' for j in range(3)):
            requirements.append(f'TTC{i} 使用外部时钟，需提供匹配定时器时钟 DTB。')
    warnings.append('TTC 内部定时器保留给 Linux 时基；XSA 的外部 TTC I/O 使能不等同于移除 Linux 时钟节点。')
    # Protect known board geometry; allow timing/training settings to be regenerated.
    for key in ('PCW_UIPARAM_DDR_ROW_ADDR_COUNT','PCW_UIPARAM_DDR_COL_ADDR_COUNT',
                'PCW_UIPARAM_DDR_BANK_ADDR_COUNT'):
        if key in ref and ps.get(key)!=ref[key]: errors.append(key+' 与板载 DDR 几何结构不一致。')
    if errors: raise BuildError('XSA 与 EES-331 板载连接不兼容：\n'+'\n'.join(errors))
    return dict(requirements=requirements,warnings=warnings,
                controllers=[dict(name=n,enabled=enabled(ps,n),path='/axi/'+path,routing=routing(ps,n)) for n,path in CONTROLLERS.items()])

def dts_rules(ps,ref,base_data,usb_role='otg'):
    if usb_role not in ('otg','host','peripheral'): raise BuildError('无效 USB 角色。')
    d=parse(base_data)
    gpio=be(d['/axi/gpio@e000a000']['phandle']); clk=be(d['/axi/slcr@f8000000/clkc@100']['phandle'])
    used=[be(v['phandle']) for v in d.values() if 'phandle' in v]
    fresh=max(used)+1
    lines=['/include/ "base.dts"']
    def node(path,props): lines.append('&{'+path+'} { '+props+' };')
    for name,path in CONTROLLERS.items():
        if '/axi/'+path not in d: raise BuildError('基线 DTB 缺少 PS 控制器：'+name)
        node('/axi/'+path,'status = "'+('okay' if enabled(ps,name) else 'disabled')+'";')
    for i in range(2):
        name=f'UART{i}'
        if enabled(ps,name):
            baud=integer(ps,f'PCW_UART{i}_BAUD_RATE',115200)
            node('/axi/'+CONTROLLERS[name],f'current-speed = <{baud}>;')
            node('/axi/'+CONTROLLERS[name], 'cts-override;' if ps.get(f'PCW_UART{i}_GRP_FULL_ENABLE','0')=='0' else '/delete-property/ cts-override;')
    node('/aliases','serial0 = "/axi/serial@e0001000"; serial1 = "/axi/serial@e0000000"; mmc0 = "/axi/mmc@e0100000";')
    node('/axi/serial@e0001000','u-boot,dm-pre-reloc; port-number = <0>;')
    if enabled(ps,'UART0'): node('/axi/serial@e0000000','port-number = <1>;')
    baud=integer(ps,'PCW_UART1_BAUD_RATE',115200)
    node('/chosen',f'stdout-path = "serial0:{baud}n8"; bootargs = "console=ttyPS0,{baud} earlycon root=/dev/mmcblk0p2 rw rootfstype=ext4 rootwait devtmpfs.mount=1 uio_pdrv_genirq.of_id=generic-uio clk_ignore_unused";')
    mask=sum(1<<i for i in range(4) if ps.get(f'PCW_FPGA_FCLK{i}_ENABLE')=='1')
    node('/axi/slcr@f8000000/clkc@100',f'fclk-enable = <{mask}>; ps-clk-frequency = <33333333>;')
    width=integer(ps,'PCW_GPIO_EMIO_GPIO_WIDTH',0) if ps.get('PCW_GPIO_EMIO_GPIO_ENABLE')=='1' else 0
    node('/axi/gpio@e000a000',f'emio-gpio-width = <{width}>; /delete-property/ gpio-mask-high; /delete-property/ gpio-mask-low;')
    node('/axi/mmc@e0100000','bus-width = <4>; no-1-8-v; disable-wp; max-frequency = <50000000>; u-boot,dm-pre-reloc;')
    cd=ps.get('PCW_SD0_GRP_CD_ENABLE')=='1'
    node('/axi/mmc@e0100000',f'xlnx,has-cd = <{int(cd)}>; xlnx,has-wp = <0>; '+('/delete-property/ broken-cd;' if cd else 'broken-cd;'))
    for i in range(2):
        if enabled(ps,f'I2C{i}'):
            # I2C bus SCL is a software policy, NOT the 25/50 MHz PS input clock.
            node('/axi/'+CONTROLLERS[f'I2C{i}'],'clock-frequency = <100000>;')
        if enabled(ps,f'SPI{i}'):
            cs=[j for j in range(3) if ps.get(f'PCW_SPI{i}_GRP_SS{j}_ENABLE')=='1']
            node('/axi/'+CONTROLLERS[f'SPI{i}'],f'num-cs = <{max(cs)+1 if cs else 1}>;')
        if enabled(ps,f'CAN{i}') and ps.get(f'PCW_CAN{i}_PERIPHERAL_CLKSRC')=='External':
            hz=round(float(ps[f'PCW_CAN{i}_PERIPHERAL_FREQMHZ'])*1000000)
            lines.append('/ { ees331-can'+str(i)+'-clock { compatible = "fixed-clock"; #clock-cells = <0>; clock-frequency = <'+str(hz)+'>; phandle = <'+str(fresh)+'>; }; };')
            node('/axi/'+CONTROLLERS[f'CAN{i}'],f'clocks = <{fresh} {clk} {36+i}>;')
            fresh+=1
    if enabled(ps,'USB0'):
        lines.append('/ { ees331-usb-phy { compatible = "usb-nop-xceiv"; #phy-cells = <0>; reset-gpios = <'+str(gpio)+' 46 1>; phandle = <'+str(fresh)+'>; }; };')
        node('/axi/usb@e0002000',f'phy_type = "ulpi"; dr_mode = "{usb_role}"; usb-phy = <{fresh}>; usb-reset = <{gpio} 46 0>;')
        fresh+=1
    if enabled(ps,'QSPI'):
        node('/axi/spi@e000d000','#address-cells = <1>; #size-cells = <0>; is-dual = <0>; num-cs = <1>; flash@0 { compatible = "micron,n25q256a", "jedec,spi-nor"; reg = <0>; spi-max-frequency = <50000000>; spi-rx-bus-width = <4>; spi-tx-bus-width = <1>; };')
    if enabled(ps,'ENET0'):
        # Historical board UART verified PHY address 0. Reset is fixed MIO47.
        node('/axi/ethernet@e000b000',f'enet-reset = <{gpio} 47 0>;')
        node('/axi/ethernet@e000b000/ethernet-phy@0',f'reset-gpios = <{gpio} 47 1>; reset-assert-us = <10000>; reset-deassert-us = <10000>;')
    cpu=ps.get('PCW_ACT_APU_PERIPHERAL_FREQMHZ')
    if cpu and cpu!=ref.get('PCW_ACT_APU_PERIPHERAL_FREQMHZ'):
        # Do not retain old frequency scaling OPPs after changing PLL settings.
        node('/cpus/cpu@0','/delete-property/ operating-points;')
    return '\n'.join(lines)+'\n'

def validate_generated(data,ps):
    d=parse(data)
    handles={be(v['phandle']):k for k,v in d.items() if 'phandle' in v}
    if len(handles)!=sum('phandle' in v for v in d.values()): raise BuildError('DTB phandle 重复。')
    for name,node in CONTROLLERS.items():
        p=d.get('/axi/'+node,{})
        actual=bool(p) and p.get('status',b'okay\0')==b'okay\0'
        if actual!=enabled(ps,name): raise BuildError('设备树控制器状态与 XSA 不一致：'+name)
    for path,props in d.items():
        for prop,countprop in [('clocks','#clock-cells'),('resets','#reset-cells'),('phys','#phy-cells')]:
            if prop not in props: continue
            raw=props[prop]
            if len(raw)%4: raise BuildError('DTB引用长度错误：'+path+'/'+prop)
            cells=[be(raw,i) for i in range(0,len(raw),4)]; i=0
            while i<len(cells):
                if cells[i] not in handles: raise BuildError('DTB引用不存在：'+path+'/'+prop)
                target=d[handles[cells[i]]]
                if countprop not in target: raise BuildError('DTB provider 缺少 '+countprop)
                i+=1+be(target[countprop])
            if i!=len(cells): raise BuildError('DTB引用单元不匹配。')
        for prop in ('interrupt-parent','phy-handle','usb-phy'):
            if prop in props and be(props[prop]) not in handles: raise BuildError('DTB句柄引用不存在：'+path+'/'+prop)
        for prop in ('reset-gpios',):
            if prop in props and (len(props[prop])!=12 or be(props[prop]) not in handles): raise BuildError('GPIO引用无效。')
    return dict(result='AUTO_DTB_VALIDATION_PASS',controller_count=len(CONTROLLERS),phandle_count=len(handles))
