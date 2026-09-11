# 2026-09-09 Validation Summary

## 已验证事实（本次会话）

1. `1_docs/pdf/AMD赛题.pdf` 与 `1_docs/pdf/amd_sait题_mineru/amd.pdf` SHA-256 相同：
   `C6AD82ACD4F7BDCD13BD412E232ED85D05F2A87DD5E2CDD04F9D219F88B569FC`。
2. 旧 MinerU 产物 `1_docs/pdf/amd_sait题_mineru/parsed/` 为空目录，无 Markdown/content JSON，不满足复用条件（已向用户说明需重新解析）。

## MinerU 解析结果

- 证据目录：`E:\competition\4_metrics\logs\2026-09-09_amd_sait_pynq_mineru_run01`
- Marker：`MINERU_PARSE_PASS`（file_count=1，exit code 0，fallback=False，28.2 s）
- Markdown：`AMD赛题/auto/AMD赛题.md`；content JSON：`AMD赛题/auto/AMD赛题_content_list.json`（+ v2）
- 图片：23 张；中文质量检查：`pass`；PreferredSource：`content_list_json`
- 输入 SHA-256：见上。

## 赛题 PYNQ 条款核对（语义来源：上述 Markdown）

- 赛题 2.1：PYNQ-Z2 为 Zynq-7000 XC7Z020 教育板，可用 Python/Jupyter 通过 Overlay 调用 FPGA。
- 赛题 3.2.2.4（本队所在具身智能赛道）：平台不限，PYNQ-Z2 是可借用板卡之一，适合“Python 一体化控制与快速原型”；明确写明“PYNQ 的 Python 环境只是统一调用接口，不能替代 FPGA/Zynq 设计，作品仍须包含 FPGA Overlay、Zynq PL/PS 协同设计或硬件逻辑”。
- 赛题 3.2.3.3 第 6 条：鼓励（非强制）使用 Python 打通 AI PC 与 PYNQ-Z2/KR260 的控制流程。
- 赛题 3.2.2.5 / 3.3.5.2：“PYNQ-Z2 Overlay 加载、IO 控制和传感器读取”等可作为加分 Skill；通用性 Skill 加分。
- 赛题 3.3（初级组）：“不限定实现方式，但推荐使用 PYNQ 框架”；高级组同样可提交 PYNQ Skill。

## 结论

- 对本队（赛题 3.2 具身智能赛道，EES-331/Zynq-7020 + Ryzen AI PC）：PYNQ 非强制。强制项是 Ryzen AI PC 上位机 + 含真实硬件逻辑的 AMD FPGA/Zynq 设计 + 两端通信数据流；Python 打通控制流程与 PYNQ Skill 属鼓励/加分项。
- 现行 Vivado/Vitis C 方案满足赛题硬性要求；是否引入 PYNQ 是工程路线选择，不是资格条件。

## PASS/FAIL 判定

- PASS 判据：marker 为 `MINERU_PARSE_PASS`，Markdown 与 content JSON 齐全，PYNQ 条款可从原文逐条引用。
- 本次结果：PASS（问答型会话，无板级/构建变更）。

## 任务 2 结果（同日追加：EES-331 PYNQ 从零部署计划）

### MinerU 复用披露

- 复用 `4_metrics/logs/2026-09-08_eth_zynq_psw_check_mineru_run01` 解析《EES-331 User Guide.pdf》：
  - 输入 SHA-256 匹配：`27C26F39F3E35132A89FAE2155FA23575E850B0A22E3D9DC64FD73186B3F5949`（当日实测一致）。
  - Marker `MINERU_PARSE_PASS`；Markdown 与 `*_content_list.json` 齐全 → 满足全部复用条件，未重新解析。

### 核实的关键事实（语义来源为上述复用产物 + Web 核实）

- EES-331：xc7z020clg484-1；1GB DDR3（MT41K256M16 RE-15E，与冻结工程 PS 配置一致）；SD0 启动 SW8=0,0,1,1,0,x；ENET0 PHY = Marvell 88E1518（MIO16~27，MDIO MIO52/53）；UART1 MIO48/49 转 USB。
- PYNQ-Z2：PHY 为 Realtek RTL8211E-VL、512MB DDR3 → 直接烧卡不可行，必须改 FSBL（DDR 1GB）+ 设备树（memory 节点 + PHY 节点）+ 重打 BOOT.BIN。
- PYNQ v3.0.1 = Zynq-7000 最新官方镜像代（Ubuntu 22.04，Vitis/PetaLinux 2022.2；sdbuild 需先手工填 prebuilt）。
- 冻结工程 PS 仅使能 UART1（ENET/SDIO/USB/QSPI 均关）→ PYNQ 部署需新建 PS 配置，不能复用冻结 XSA。

### 交付物

- 部署计划：`E:\competition\1_docs\doc\EES-331_PYNQ从零部署计划_2026-09-09.md`（v1.0）
  - 结论：可从零部署；推荐路线 A（适配 PYNQ-Z2 v3.0.1 预编译镜像）先行、路线 B（sdbuild 全量自建）按需跟进。
  - 阶段 0~5 各带 PASS 判据与证据要求；必改项清单 8 项；风险登记 7 项。
  - 文档内已链接两处 MinerU 证据 run（2026-09-09 AMD赛题、2026-09-08 EES-331 User Guide 复用）。

### 判定

- 计划文档交付：PASS（本会话无板级/构建动作，均为文档与解析证据）。

## 任务 3 结果（同日追加：Vitis 流程 vs PYNQ 流程对照说明）

- 用户要求以其现有 Vitis 四步流程（XSA→硬件平台→应用工程→C 开发）为参照，说明 PYNQ 对应开发路径与区别。
- 纯概念问答，不涉及文档解析与板级动作；结论已在会话中直接答复（运行期 Overlay 加载 + Python 解释执行 vs 编译期绑定 + C 交叉编译；Linux 接管 PS 外设后现有裸机网口/串口代码不可直接平移，PL 设计与 AXI 接口原样复用）。

## 任务 4 结果（同日追加：SD 启动机制答疑）

- 复用 EES-331 User Guide MinerU 产物第 9 节 + 按 MinerU 技能第 8 步查验"图形化配置"图（`auto/images/a7dfa9e7...jpg`），确认官方 SD0 配置：clk=MIO40、cmd=MIO41、data[0..3]=MIO42~45（1.8V fast）、CD=MIO0（3.3V）、WP 未接。
- 会话答复要点：启动模式由 SW8 拨码（硬件采样）决定，PS7 里使能 SD0/MIO 服务的是 FSBL 之后的软件链；上电后 ROM→FSBL→u-boot→kernel→rootfs 全自动，无需 JTAG。

## 任务 5 结果（同日追加：JTAG 入口角色变化答疑）

- 会话答复要点：转 PYNQ/Linux 后日常入口变为文件与网络（Overlay 运行时经 DevCfg/PCAP 加载 bit、应用即文件系统内 .py/.ipynb、经网口 scp/Jupyter 上传）；JTAG 退居三用途：ILA 波形调试、系统挂死救援（SW8 拨回 JTAG 模式）、FSBL/ps7_init 阶段验证（部署计划阶段 1 PASS 判据）。

## 任务 6 结果（同日追加：上电自启答疑）

- 会话答复要点：SD 卡常插 + SW8 常驻 SD 启动后，上电仅供电即全自动进系统（Jupyter 随 systemd 自启）；使用仍需一条访问通道（网线为主，串口建议调试期保留）；比赛演示可用 systemd/notebook 自启做到上电即演示形态。首次部署验证阶段仍按计划接串口看启动日志。

## 任务 7 结果（同日追加：网口双职责答疑）

- 会话答复要点：单物理网口承载"管理通道（ssh/Jupyter/scp，TCP）+ 视频流（UDP）"不构成冲突——端口互不相同、千兆带宽余量充足（480p 原始流约 140~210 Mbps，占比 <25%）、TCP 拥塞退让机制天然让大文件传输给 UDP 让路；真正需关注的是 Zynq-7020 A9 上 Python 发包速率（约 1.2 万包/秒）的 CPU 开销，缓解手段为批量发送/加大 SO_SNDBUF/必要时降帧率，实测以部署计划阶段 3 的 iperf 为准。

## 后续验证目标

- 部署计划阶段 0（资源确认）启动前需用户明确授权新建工程目录（建议 `2_fpga/2_pynq_port/`）。
- PYNQ 路线若启动，首启串口全量日志、dtb 修改前后、BOOT.BIN 各组件 SHA-256 必须入 `4_metrics/logs` run 目录。
