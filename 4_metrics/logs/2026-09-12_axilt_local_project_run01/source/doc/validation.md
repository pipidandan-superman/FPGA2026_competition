# 构建、验收与恢复

## Windows离线入口

在新的证据目录执行，run.ps1拒绝复用已有目录。
本机已观察到GUI环境读取失败；官方vivado.bat的独立启动冒烟通过后，
本轮后续采用standalone。目标版本Vivado2025.2。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\competition\2_fpga\2_axi_lite_test\proj\run.ps1 -Mode sim -GuiPid 22504 -Backend standalone -RunDirectory E:\competition\4_metrics\logs\YYYY-MM-DD_axilt_reg_sim_runNN
powershell -NoProfile -ExecutionPolicy Bypass -File E:\competition\2_fpga\2_axi_lite_test\proj\run.ps1 -Mode build -GuiPid 22504 -Backend standalone -RunDirectory E:\competition\4_metrics\logs\YYYY-MM-DD_axilt_reg_build_runNN
python -B -m unittest discover -s E:\competition\2_fpga\2_axi_lite_test\pynq -p test_driver.py -v
```

runNN、日期替换为本次唯一编号；GUI模式需要当前有效PID，standalone不读取该PID。
首次更换Vivado安装后先运行-Mode smoke。
构建读取既有板级BD的PS参数到run快照，批量设置电压/DDR/MIO配置，
仅修改控制时钟、GP0/HP/EMIO需求。源BD只读。

## 寄存器仿真出口

- 3个固定种子1/7/12345、全部16种WSTRB、AW/W同时和双向先后到达。
- 4KiB全部非法偏移/非对齐访问、所有RO写、B/R反压、读写并行。
- 1001条执行命令、输入快照、旧结果保持、ACK、重复及回绕序号。
- AW-only、W-only、B/R挂起和执行过程中复位。
- 单独寄存器层同周期读写返回旧值；延迟后端请求/响应测试。
- 运行日志同时有AXILT_REG_SIM_PASS、AXILT_DELAYED_BACKEND_PASS及自然结束；
  不得仅以编译/综合成功判定仿真通过。

## PYNQ上板入口

先确认EES-331通过现有SD启动到PYNQ、PC网线可达192.168.240.10，
并能SSH登录。测试Overlay会暂时替换PL视频逻辑。

将同一release目录中的axilt.bit、axilt.hwh、artifact_manifest.json，
以及本目录pynq中的软件复制到板上独立目录，例如/home/xilinx/axilt_test。
不要覆盖原/home/xilinx/ees331_camera。
先在板上编译C访问层：

```bash
cd /home/xilinx/axilt_test
cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared mmio_ordered.c -o libmmio_ordered.so
sudo /usr/local/share/pynq-venv/bin/python board_test.py --bit ./axilt.bit --manifest ./artifact_manifest.json --run-dir ./evidence/register_run01
```

Python路径以上次PYNQ环境为候选，运行前用板端实际环境确认。
脚本校验BIT/HWH哈希与HWH窗口、取得独占锁、确认原视频服务active后停服务，
执行1000轮合法访问、驱动拒绝重复命令以及3次Overlay重载恢复测试。
全部events.jsonl和result.json取回Windows对应4_metrics/logs/run中。
异常原样记录，提交后超时不重发命令。

脚本finally释放锁并恢复原视频服务。SERVICE_ACTIVE只证明服务运行；
随后使用原UDP接收器确认完整新帧持续增长、CRC/坏头/丢帧无新增，并确认HDMI动态画面。
这一步通过后才关闭寄存器板测验收。脚本不会改启动镜像、永久禁用服务或重启板卡。

板测只发送合法AXI访问；人为SLVERR可能触发Linux用户态总线异常，不在实机自动注入。
硬件非法访问语义由自检RTL仿真覆盖，软件拒绝重复提交独立标记。

## 阶段门槛

1. 寄存器仿真通过 -> 构建报告通过 -> 寄存器实机1000轮及3次重载通过，恢复视频。
2. 之后才实施/运行BRAM全长度仿真、官方IP仿真和1000命令板测。
3. 两阶段通过后提交集成清单；合并主工程后的共存测试是另一验收。

若当前板卡不可访问，保留源码、独立BIT/HWH/XSA及可执行板测入口，
标记REG_BOARD_PENDING，不将板测跳过写成PASS。

