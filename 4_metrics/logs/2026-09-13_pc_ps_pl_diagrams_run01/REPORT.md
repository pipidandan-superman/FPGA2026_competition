# PC / PS / PL 系统图集制图记录

任务：结合当前工程绘制完整总框图、PS/PL模块图、完整控制流程，参考外部12号图集，存放本工程doc。

## 交付范围

交付目录：`E:/competition/1_docs/doc/PC_PS_PL系统图集_20260913/`。

- 01：PC＋PS＋PL完整框图。
- 02A：视频、SCCB、AXIS、VDMA、DDR/HP、HDMI及所有时钟/复位分区。
- 02B：PS动作驱动、ACTL实例层级、AXI从接口、16个CSR、执行器、UART和LED。
- 03A/03B/03C：启动就绪、单动作事务、拒绝/超时/正常退出与恢复。

原生Visio六页；整体与单页PDF；六张高清PNG；六张SVG；本地浏览HTML、阅读说明、交付哈希。

## 当前事实核对

主依据是发布HWH和当前软件代码；HWH合同检查输出保存在 `hardware_inventory.json`，标记 `ACTION_HARDWARE_CONTRACT_PASS`。模块、总线、端口、频率、地址窗已展开。原始源清单与输入SHA256在 `source_manifest.json`，补充SV文件在 `additional_rtl_sources.json`。

关键核对：PC模型CPU推理；ACTL 50MHz；AXI地址0x43C00000/4KiB；VDMA地址0x43000000/64KiB；当前CMA帧槽落在HP1且读写均按地址路由至HP1；没有ACTL IRQ/已连接VDMA IRQ；UART 9600/8N1；固定动作位流无BLE桥。模型加速、腕部相机、Qwen语义及机械臂闭环仅标为规划。

原始发布manifest中的 `board_validated=false` 为构建时记录，不覆盖后续独立板测；当前验证事实明确来自v1.4两轮报告，其中第二轮断电是用户确认。此轮没有新上板动作。

## 参考读取

实际参考路径：`E:/post_student/2_doc/12_PC_PS_PL完整框图_参考硬件组PPT_20260913`。

MinerU证据：[本次解析目录](../2026-09-13_pc_ps_pl_diagrams_mineru_run01/)。

- backend=pipeline；model_source=local。
- 结果 `MINERU_PARSE_PASS`；输入SHA256 `AFE096EEF7FD88BEFCC235F64D037AF5F9921AFC17F3331BF0E602939BA7AF15`。
- Markdown和content_list JSON齐全；主体识别为图像1张。
- `ChineseQuality=review`，原因short_text；preferred_source=content_list_json；Fallback=false。
- 结合解析JSON、参考阅读说明及原preview进行了图像层次与线型人工复核，未把OCR结果宣称为完整文本质量PASS。

## 构建及修订

`build_scene.py` 产生全部原生形状、文字与折线坐标；`build_visio.ps1` 在私有隐藏Visio实例中生成六页VSDX与PDF/SVG。沙箱会话的COM启动报 `80070520` 后，经执行权限提升在用户会话成功生成；未操作用户已打开的文档。初次PowerShell5脚本中文编码导致语法错误，改用ASCII脚本元数据修正。

`verify_render.py` 检查Visio压缩包完整、原生文本与源场景逐项一致、无整图媒体嵌入；检查PDF文字缺失/越界及字体嵌入，生成PNG、单页PDF及contact sheet。已修正VDMA文本纵向越界、控制线跨PL标题及STATUS位图误写问题。外部参考目录中的临时 `~$$*.~vsdx` 锁文件因用户会话关闭而消失，明确排除在源内容哈希比较之外；正式参考文件哈希保持一致。

`closeout.py` 复核BIT/HWH/模型哈希，检查阅读说明本地链接，生成浏览入口、交付文件校验与最终marker。所有生成脚本、控制台输出、输入/输出哈希和渲染检查保留本目录。

## 验收

最终机器结果见 [verification.json](verification.json)，最终marker见 [result_marker.txt](result_marker.txt)，Visio原生重开结果见 [visio_build.json](visio_build.json)。

通过条件：六页完整；Visio重开成功；298个原生图形对象（含线条），180个粘接端点；源场景文字一致；PDF无缺字、无文字越界，全部字体嵌入；逐页渲染目检通过；固定BIT/HWH/模型哈希一致；正式输入文件哈希未变化；所有交付链接有效；项目skill路径审计通过。

本次结果仅为 `PC_PS_PL_DIAGRAMS_DOCUMENTATION_PASS`，不是新RTL功能、准确率、热重载可靠性或机械臂验收。未重建、下载或连接硬件，冻结2_fpga仅只读，未执行Git发布。
