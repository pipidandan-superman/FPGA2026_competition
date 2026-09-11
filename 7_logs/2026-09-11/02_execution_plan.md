# 2026-09-11 执行计划

## PYNQ 镜像归档与 Git 交付

1. 固定清理前 IMG 清单，并对 222654 成功镜像与基础镜像建立本机归档副本。
2. 计算归档副本 SHA-256，保存来源、用途和板测状态清单。
3. 归档启动分区恢复镜像、启动 ZIP 和构建/应用清单。
4. 修订 README、教程、HANDOFF 和复现指引；统一使用 `9_pynq/sd`。
5. 在干净工作树逐文件复制、审核、暂存、提交并推送 `codex/full/pipidandan-superman`。
6. 删除动作若被安全审批拒绝，保留拒绝事实，不使用替代手段绕过审批。

## EES-331 工作区基线收敛

1. 固化 EES-331 最小系统 IMG、Vitis/JTAG 发布文件和 PYNQ 集成 IMG。
2. 移除旧 Builder、通用 PYNQ-Z2 下载镜像、阶段性 FPGA 工程、顶层缓存和可再生成构建树。
3. 更新 Builder 默认基线路径、工具说明、README、HANDOFF 和镜像清单。
4. 运行 Builder GUI 自检、SHA-256、项目路径审计和 Git 分支审计。

依次读取本地工作区/日志技能、历史交接、v0.2 hardware.py/board_profile.py/builder.py/README及IMG交付报告；核对官方 PYNQ Overlay 文档。
风险：把历史启动成功扩展为新包通过，或将 PL 下载误认为完整 XSA 热切换。按源码与历史证据分别说明。
回退：不改工程及板卡；在线搜索失败后直接读取官方文档。

## PYNQ 迁移执行
1. 归档用户 SD 串口/JTAG 截图，固定 XSA、main.c、HWH SHA256。
2. 经 COM6 读取 Linux 网络，增加临时 192.168.240.10/24 与 PC 192.168.240.2 通信；SSH 部署。
3. 在 /home/xilinx/ees331_camera 使用匹配的 overlay.bit/hwh；检查 PYNQ 下载、VDMA reset 寄存器和 allocate。
4. 移植现有寄存器写入顺序，使用连续内存取代裸机固定 DDR；保留 PL 的 SCCB/ADV7511 初始化。Linux socket 复用 OV56 协议。
5. 有界运行采集帧、VDMA 状态、接收 CRC/丢帧证据；停止 DMA 并确认 halted 后才释放内存。HDMI 实物显示另行观察。
6. 交付可重启脚本与启动说明；遇硬件异常停止首个失败阶段，保留原始日志。

执行完成：初次自动启动 S2MM 0x15810；增加等待时间单独试验失败。对照原 main.c 恢复“先 MM2S 首帧、一次启动清错、再检查新的读写帧切换”顺序后，SD 重启及持续显示通过。新脚本运行期任何错误立即停止，不循环清错。`install.sh` 安装业务开机服务和网络别名，配置备份保存在板端应用 backup 目录。

## Gate 1：归档并上传当前成果

1. 在 `4_metrics/logs/2026-09-11_pynq_checkpoint_upload_run01` 保存完整 Git preflight。
2. 更新根 `README.md`、`HANDOFF.md` 和本日四件套，明确自动启动条件、PASS 结果、冷启动边界及 Builder 尚未注入 rootfs。
3. 使用 `E:/competition_worktrees/FPGA2026_competition/pipidandan-superman` 独立工作树，从个人分支最新提交合并 `origin/main`。
4. 逐文件复制 PYNQ 源码/脚本、文档和精选证据；不复制 `overlay.bit`、`overlay.hwh`、`current.hwh`、IMG、压缩包、依赖目录或批量日志。
5. 执行协议测试、Python 语法检查、路径审计、`git diff --cached --check` 和暂存清单审计。
6. 提交并推送 `codex/full/pipidandan-superman`，核对远端分支提交。

## Gate 2：扩展 SD Builder

仅在 Gate 1 推送确认后执行。为 full-image 构建增加可选 PYNQ 应用注入，离线写入 rootfs 的应用目录、`uEnv.txt`、网络配置和 systemd 服务，并生成 manifest 和读回校验。产出的 IMG 仍需物理冷启动板测，不能以离线读回代替。

## Gate 3：零基础教程

仅在 Gate 1 推送确认后执行。在 `1_docs` 编写 PYNQ 基础、Overlay/MMIO/CMA/VDMA、摄像头工程迁移、UDP、systemd、调试、恢复和新 XSA 迁移流程。

## Gate 2/3 实际执行

1. 在 Builder 增加 `rootfs.py`，用 Cygwin debugfs 对 IMG 内 ext4 分区离线注入，执行 e2fsck 和逐文件哈希读回。
2. 固定摄像头应用 XSA/bit/HWH 契约；仅允许完整 IMG + manual PL 模式。
3. 先用 128 MiB ext4 镜像做模块测试，再运行源码版完整 IMG 构建。
4. 打包 v0.2.1 EXE。首次全构建失败后，依据 XSCT 日志修复冻结程序 DLL/Tcl 环境隔离，再重新自检和完整构建。
5. 发布 EXE 与 SHA256，更新 Builder/工具说明和 Win32DiskImager 写卡步骤。
6. 编写 `1_docs/PYNQ零基础开发与EES331摄像头工程实战.md`。
7. 运行语法、协议、rootfs、Git diff 和项目路径审计，显式暂存后提交个人分支。

## v0.2.2 执行

为 Builder/GUI/CLI 增加 output_dir；先探测路径可写，继续在既有证据目录构建，成功后复制部署文件至目标盘的 pending 子目录，逐文件 SHA256 读回后同盘重命名发布。错误不覆盖既有包。执行针对输出功能的测试、冻结 EXE 自检及自定义输出完整 IMG 构建，再发布 EXE、说明和个人分支提交。
