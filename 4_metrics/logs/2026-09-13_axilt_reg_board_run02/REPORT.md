# AXI-Lite 寄存器板测 run02

状态：AXILT_REG_BOARD_TEST_PASS；1000轮与3次Overlay重载通过，UDP恢复通过，用户已确认最终HDMI正常。独立寄存器阶段完整验收通过；BRAM_NOT_STARTED。

根因与修复：前次BD的proc_sys_reset C_AUX_RESET_HIGH=0，但aux_reset_in接const_zero，导致CSR和互连常处复位。recovery_run01仅加载检查成功且SSH正常；本次改接const_one，4份自研RTL与原通过仿真版本逐字节相同。官方复位IP网表仿真同时重现错误接线保持复位、正确接线释放和两次CSR身份读取，reset_sim_run01 PASS。修复版构建reset_fix_build_run01 PASS：100MHz，WNS/WHS2.925/0.013ns，LUT719、FF1116、DRC错误/黑盒0。

## 实机证据

- board_result.json：REGISTER_TEST_PASS、completed1000、reloads3。
- events.jsonl：1000命令逐条参数、取反结果、接受/完成序号及执行计数，3次重新加载后复位与执行通过。
- register_test.log：实时完整控制台，板端每条事件flush+fsync。
- audit.json：独立复核1000条结果/序号/计数、3次重载、旧HWH拒绝、新HWH通过及15项Python单测。
- compile.log：ARM32访问库，SHA256 753b36efadfb1da6f626bd267b8d97da3d9e1d927a856852fca894e5b5429e23。
- video_before_synced.json：60完整帧，60种CRC，丢帧/CRC/坏头0。
- video_after.json：恢复后60完整帧，60种CRC，丢帧/CRC/坏头0；服务恢复已记录。
- physical_confirmation.json：用户确认恢复后的HDMI显示正常，标记AXILT_VIDEO_RESTORATION_PASS。
- delivery_hashes.json：实际上传软件与BIT/HWH的哈希，上传后SFTP回读逐字节验证。

BIT SHA256 a1eeb997b6691306b991b441d3eba48bbdcd05d11c6c3ed0ec5f2f40b996449e。
HWH SHA256 d9a611f938a6ed7806aabe3195a9e76f463960c3105d8881ee177f8e50bbcd4c。
板端目录 /home/xilinx/axilt_test_20260913_run02，旧run01保留。

## 保留的非成功记录

video_before.json最初直接在连续视频流中间接入，有61连续完整帧但1个起始残帧，因此旧接收器判FAIL。改为明确记录启动丢弃包并从首个pid0对齐后重新测量，不修改原结果，也不豁免对齐之后的任何CRC/坏头/丢帧。
本次上传准备首次因发布审计尚未完成而未上传；发布审计初次因新检查器将Vivado的CONST_VAL="0x1"误当不等于十进制1而拒绝，修正数值解析并增加单测后通过。此为工具解析缺陷，不是硬件接线再次失败。
首次失联run01记录位于../2026-09-13_axilt_reg_board_run01/REPORT.md；取回原始事件残片位于../2026-09-13_axilt_recovery_run01/run01_events.raw，未替换或修剪。

## 边界

重复序号实机覆盖软件拒绝，非法AXI和全部WSTRB/通道乱序属已有仿真；板测不注入SLVERR。
未重刷SD，原视频文件不变。仅加载流程证明现有PS/Linux可运行兼容的新PL，不意味着任意PS/设备树配置可随意替换。
板端PYNQ默认Zynq参考时钟50MHz，而本板晶振33.333MHz，因此Clocks.fclk0_mhz显示值不可直接当实测频率；HWH显式分频5x2配合IO PLL倍频30，对应100MHz。未调整系统PLL或凭显示值修改时钟。
