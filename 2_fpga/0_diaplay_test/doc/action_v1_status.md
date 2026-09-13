# 第一版动作控制：实现、证据与上板入口

更新时间：2026-09-13。用户已批准第一版执行，第二版蓝牙动作输出尚未执行。
当前状态：`MODEL_AXI_UART_FIVE_ACTIONS_PASS / AXI_1000_COMMANDS_PASS / HOT_RELOAD_UNRESOLVED / MANUAL_GUI_REPEAT_IN_PROGRESS / GIT_NOT_PUBLISHED`。
真实视频模型的Down/Stop/Thumbs Down/Thumbs up/Up均已通过连续三帧判定，经PS AXI-Lite寄存器驱动PL UART/LED；两轮1500推理帧、18条输出126字节COM4完全匹配。
确定动作1000条及重复提交验证通过，含清灯1001帧7007字节；视频并行正常。用户正在不自动关闭的上位机中重复验证。
热重载仍有已复现的首帧失败：成功运行后跨进程再次加载同一C失败，在动作服务启动前发生；恢复原A视频再切同C成功，根因尚未证明，不能称稳定部署已完成。
最新证据：[完整链路报告](../../../4_metrics/logs/2026-09-13_action_v1_end_to_end_run01/REPORT.md)。历史失败/NOT_STARTED条目保留，不代表当前完整链路未执行。

当前在线临时服务为`ees331-action-e2e-manual2.service`，部署目录`/home/xilinx/action_e2e_20260913_run01`，无时限、无开机自启、无自动重试。PC为`gui_manual`，不要未经用户确认关闭或重新加载。
原SD与原视频服务文件未覆盖；下次冷启动仍为原视频基线，不会自动启用动作Overlay。不要在原视频Overlay上直接启动AXI控制客户端。
以本文最后的证据表为准，历史方案中的 NOT_STARTED 不再表示当前源码状态。

## 控制路径及默认行为

```text
OV5640 → PL采集/VDMA → PS/PYNQ → UDP5000 → PC模型
                                               │
                                   新推理帧的稳定动作判定
                                               │ UDP5001
                       PS单进程ActionService → AXI-Lite寄存器
                                               │
                                  PL动作执行器 ├→ ACTION_LED
                                               └→ UART TX A17 → PC COM4抓取
```

模型仍在 PC 运行。本版没有把模型迁移到 PL，也不使用 PC→COM4 发送动作的旁路。
保留原 SD Linux 基础；配对的新 BIT/HWH 由新应用加载，不修改 BOOT.BIN 或重制 SD 镜像。

- 自动动作：Down、Stop、Thumbs Down、Thumbs up、Up；暂不判左右。
- 三个不同且新鲜的推理帧连续同类，每帧置信度均 >=0.75，第三帧形成一个命令。
- 同一个视频帧的 GUI 刷新不计数；无效、过低置信度、冲突或另一类别打断连续计数。
- 同类动作持续存在时不每三帧重复发送。切换动作需重新连续三帧。
- 连续一秒没有有效动作，发送一次 CLEAR；随后恢复有效动作重新计数。
- 启动同步后和正常退出时各通过 AXI 发送 CLEAR，不能把它们误算为模型误判。
- 下发或确认超时后显示错误并停止新命令，不自动重试未知完成状态的命令。
- 本版仅验证 LED/数据链；不是机械臂安全控制系统。网络中断时软件 CLEAR 不保证送达。

## 动作与串口映射

| ACTION | 模型语义 | 指示灯/管脚 | 自动模型下发 |
|---|---|---|---|
| 0x00 | CLEAR | 全部动作灯熄灭 | 超时/启动/退出 |
| 0x01 | Down | LED1 U6 | 是 |
| 0x02 | Left | LED2 U5 | 否，仅注入验证 |
| 0x03 | Right | LED3 V7 | 否，仅注入验证 |
| 0x04 | Stop | LED4 W7 | 是 |
| 0x05 | Thumbs Down | LED5 W6 | 是 |
| 0x06 | Thumbs up | LED6 W5 | 是 |
| 0x07 | Up | LED7 U7 | 是 |

V4 保留摄像头 cfg_done，不用作动作灯。COM4：9600、8N1、无流控、只接收。

```text
A5 5A SEQ8 ACTION CRC8 0D 0A
```

SEQ8 是 AXI 32 位递增序号的低八位；CRC8 为 ATM 多项式 0x07、初值0、MSB先行，
计算前四字节。例如序号1/Stop：`A5 5A 01 04 1B 0D 0A`。
PL 在接收 START 时锁存序号/动作，LED one-hot 更新；整帧最后停止位发完才置 DONE。
PS 核对完成序号、计数和帧签名后 ACK，再向 PC 返回确认。

蓝牙独立工程保持原状；当前主 BD 不含透明桥，也没有 BLE 输出。
第二版经后续批准后才增加蓝牙输出，不能同时保留透明桥驱动同一 BT_RX。

## 工程与源码入口

- 独立工程：`2_fpga/2_axi_lite_test/proj/action_v1/AXI_LITE_test.xpr`，BD `AXI_LITE_test`。
- 主视频工程：`2_fpga/0_diaplay_test/proj/display_test_zynq7020_school/display_test_zynq7020_school.xpr`，BD `display_test`。
- 拖入 BD 的 Verilog 顶层：`rtl/control/video_axi_action_uart_top.v`。
- 复用模块：`2_fpga/2_axi_lite_test/rtl/axi_lite_slave.v`、`axi_action_reg_bank.v`、
  `axi_action_control_top.v`、`action_command_executor.v`、`action_uart_tx.v`。
- ABI：[action_control_abi.md](../../2_axi_lite_test/doc/action_control_abi.md)。
- PS：`pynq/camera_action_v1.py` 复用 `camera.py` 视频通路；动作驱动/协议/服务在独立工程 `pynq`。
- PC：`3_host/model_env/stable_action.py`、`action_link.py`、`gesture_viewer.py`。
- 串口板测：`3_host/model_env/action_board_test.py`、`serial_capture.ps1`。
- 构建：独立 `proj/build_action_v1.tcl`；主工程 `proj/integrate_action_v1.tcl`、
  `validate_action_v1.tcl`、`build_action_v1.tcl`。

主设计控制时钟50MHz，PS GP0→SmartConnect→`axi_action_0`；CSR `0x43C00000/4KiB`，
VDMA `0x43000000/64KiB` 不变。驱动从 HWH 解析地址，不硬编码物理地址访问。
复位保持已验证的低有效 aux_reset_in 接常数1，dcm_locked=1、mb_debug_sys_rst=0。
寄存器访问使用既有 ARM C 屏障层 `mmio_ordered.c`。

## 构建规则与已知基线约束

每次使用新的 `4_metrics/logs/<run-name>/run.tcl`，设置 `run_dir` 后 source 构建脚本，
通过 `4_metrics/scripts/run_vivado_standalone_ees.ps1` 启动。不得覆盖失败日志。
发布脚本 `pynq/prepare_action_release.py` 拒绝未通过构建、仿真RTL哈希不符、
HWH合同不符、XSA内BIT/HWH不匹配或已有输出目录。

M19参考时钟和AA22摄像头PCLK沿用板级非CCIO走线例外，PLL采用BUF_IN。
新主工程的M19输入缓冲位于时钟向导内部，因此不能继续引用旧 `clk_in1_0_IBUF`。
物理约束分离到 `proj/action_v1_clock_impl.xdc`，仅实现阶段使用，构建后检查实际属性。
AMD文档说明[XDC支持的Tcl命令边界](https://docs.amd.com/r/2023.1-English/ug903-vivado-using-constraints/About-XDC-Constraints)
及[综合/实现约束文件属性](https://docs.amd.com/r/2022.1-English/ug903-vivado-using-constraints/Synthesis-and-Implementation-Constraint-Files)。
原视频外部接口仍存在未指定输入/输出延迟、非CCIO及CDC告警；正时序余量不等于全接口
物理时序已证明，必须继续做动态HDMI/UDP共存实机验收。

## 上板操作与验收门（已执行到视频首帧失败，后续暂停）

当前修正布局的配对包：`2_fpga/0_diaplay_test/release/action_v1_uart_run02/`，
`release_manifest.json` 为 `ACTION_V1_RELEASE_PASS`、`board_validated=false`。
旧run01包将同名XSA与BIT并列，触发PYNQ3.0.1元数据选择错误，不应部署；保留作失败证据。
run02包将XSA移入build_artifacts/，原生元数据解析及ACTL身份板测通过，但视频首帧检查失败，
同样不得标记整体板测PASS或设为自启动。BIT/HWH与已仿真构建版本完全相同。
Windows上位机：`8_tools/EES331_Action_Viewer_v1.0/`，使用其中的
`Start_Action_Verification.ps1` 显式启用动作控制。它不会自行下载Overlay。

1. 恢复有线链路，先只读核对 SSH、PYNQ、COM4、当前服务/进程及原BIT/HWH哈希。
   用户确认动态 HDMI，PC保存原UDP基线。网络/画面异常就停止，不尝试AXI访问。
2. 将新发布包上传到新的板端目录，不覆盖原视频目录；校验清单中所有哈希，
   板端编译 `gcc -O2 -fPIC -shared mmio_ordered.c -o libmmio_ordered.so`。
3. 公告切换窗口，停止旧视频服务并确认进程退出/VDMA停稳，保留原服务恢复命令。
   加载新包前只做HWH静态审核，确认复位/地址/PS合同后分步加载、识别、单命令。
4. 解决已记录的首帧问题后，启动 `sudo bash run_action_v1.sh --evidence <新的板端证据目录> --seconds 900`。
   该程序独占视频和AXI，在同一进程内启动动作服务；不用旧camera.py同时占硬件。
5. 在PC关闭占用COM4或UDP5000的工具，再运行注入板测（先不启动模型动作发送器）：

   ```powershell
   & E:/competition/3_host/model_env/run_python.ps1 E:/competition/3_host/model_env/action_board_test.py --run-dir E:/competition/4_metrics/logs/<new-com4-run> --rounds 1000
   ```

   必须1000条完成、序号/CRC/全帧/执行计数一致，重复命令不增加串口帧；视频持续接收。
   加 `--visual` 时0..7每档两秒，用户核对各灯。该脚本只读取COM4，不从COM4发命令。
6. 再启动动作上位机，依次以五种启用动作验证新帧→稳定判决→PS/AXI确认→实际LED/串口。
   Left/Right只显示预测，不自动发送；移开手一秒应CLEAR。人工确认画面流畅、动作语义正确。
7. 新应用正常退出后恢复原Overlay和视频服务，验证UDP恢复并由用户确认动态HDMI。
   保存原失败，不能用后续成功覆盖。完成物理验收后才更新board_validated和Git个人分支。

当前串口存在仅证明USB接口枚举，不证明PL UART帧、LED或模型识别通过。
本版不改SD启动文件、不设自启动、不进行蓝牙动作输出、不关机。

## 证据表

证据目录均位于 `4_metrics/logs/2026-09-13_<suffix>`：

| suffix | 结果/范围 |
|---|---|
| action_v1_source_run01 | 改动前源/工程快照及哈希 |
| action_v1_rtl_run01 | PASS：1002命令，254494项检查；AXI/UART/LED自检 |
| action_v1_reset_baud_run01 | PASS：官方reset模型及真实50MHz/9600，2帧完整解码 |
| action_v1_independent_build_run01 | PASS：独立BD/位流，setup11.112ns、hold0.051ns |
| action_v1_main_bd_run03 | PASS：主BD验证/地址/时钟/复位 |
| action_v1_hwh_tests_run02 | PASS：最终发布HWH正例和7项负例 |
| action_v1_python_run03 | PASS：13项离线测试；后续补测见新增结果 |
| action_v1_python_run04 | FAIL：测试夹具到达时间重复，被去重；计时分辨率0.015625s，已修订夹具 |
| action_v1_python_run05 | PASS：14项最终回归，含真实UDP联调及初始化网络失败可见性 |
| action_v1_main_build_run01 | FAIL：虽生成BIT，但旧M19网名约束Critical Warning，拒绝发布 |
| action_v1_main_build_run02 | FAIL：XDC不支持if，属性未生效；拒绝发布 |
| action_v1_main_build_run03 | PASS：完整综合/布局布线/位流；setup10.402ns、hold0.020ns，黑盒0/DRC错误0/Critical Warning0 |
| action_v1_timing_audit_run01 | PASS：实现后总线偏斜8项全部MET，最小余量18.902ns，时钟报告已归档 |
| action_v1_viewer_build_run04 / viewer_smoke_run03 | PASS：最终打包EXE模型/Tk/稳定门/动作协议离线自检 |
| action_v1_board_run01 | BLOCKED_PRECHECK：有线适配器Disconnected/0bps，SSH无banner；未上板 |
| action_v1_online_precheck_run01 | 网络恢复，只读SSH及原视频服务检查通过；用户确认HDMI/UDP正常 |
| action_v1_board_run02 | 基线61变化帧PASS；上传/编译后元数据失败，同名XSA布局问题；尚未停视频/下载 |
| action_v1_board_run03 | 修正布局后下载/独立SSH/ACTL身份PASS；视频首帧FAIL；原视频恢复60变化帧及用户HDMI确认PASS |

另保留 smoke_run01 / viewer_build_run01 的沙箱启动失败、main_bd_run01/run02 的历史失败。
所有新阶段结果须同步至 `7_logs/2026-09-13/03_validation_summary.md`。
主设计资源：LUT5093、寄存器7850、BRAM20.5、DSP9。无无时钟寄存器或未约束内部端点；
原视频外部接口延迟/CDC限制仍如上所述，不宣称零普通告警或完整物理验收。

最新现场：[board_run03/REPORT](../../../4_metrics/logs/2026-09-13_action_v1_board_run03/REPORT.md)。
当前新视频失败根因尚未证实：VDMA配置/启动代码未改，共同视频模块HWH参数和共同端点
连接无实质变化；下一步检查实现时钟及摄像头初始化，必要时加入针对性观测后重新验收。
不得盲目重复加载失败位流；当前板卡运行已恢复的原视频服务。未发送任何动作命令。
