# AXI-Lite辅助复位接线修复

仅改独立BD辅助复位输入：低有效aux_reset_in从const_zero移到const_one。build.tcl加入极性/连线门控，rebuild_reset_fix.tcl在既有proj工程执行修复与重建。before.bd、release_before保留原错误发布；after.bd、recreate_bd.tcl和完整Vivado日志为修复证据。

先行官方IP仿真：../2026-09-13_axilt_reset_sim_run01/process_status.json PASS，AXILT_OFFICIAL_RESET_PASS，模拟错误接线一直复位、正确接线释放及两次CSR身份读取。官方生成IP仿真网表与四RTL复制到该run，自动生成WDB按技能要求删除，完整控制台保留。

构建PASS，100MHz，WNS2.925ns/WHS0.013ns，LUT719/FF1116，BRAM0/DSP0，DRC错误0、黑盒0。未改变4份RTL。完整warning留在vivado_console.log，包括未用复位输出、无关board catalog与模块引用提示，不隐藏。

发布审核首次因检查器比较字符串1和Vivado十六进制0x1而失败；改为数值比较并增加测试后PASS，原BD修复无误。release/artifact_manifest.json新增reset_contract，BIT/HWH/XSA字节配对通过；通过后的4文件已同步回独立proj/release，原版保留在release_before，不覆盖故障证据。

实机1000轮与3次重载见../2026-09-13_axilt_reg_board_run02/REPORT.md。主工程集成尚未执行。
