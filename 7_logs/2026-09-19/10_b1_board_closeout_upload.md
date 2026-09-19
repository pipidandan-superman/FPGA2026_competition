# 10 — B1 GEMM 板级收官 + 三门证据上传（run21/22/22b/23 → git af407c0）

日期：2026-09-19（白班尾）　　结论：**BOARD_B1_PASS 一跑全绿，三门证据已推个人分支**

## 本轮闭环内容

1. **run22b 修复**（前段事故收口）：用户 GUI 旧内存态会话保存踩掉 .xpr + 中止跑
   留半复位态 → 三段修复（重加源引用→BD 重开验证→reset_run 全链重建）→
   **与原跑逐位同值**：bit 4,045,696B / WNS+4.954 / WHS+0.024 / DSP68 / DRC0。
   事故教训已沉淀独立记忆 vivado-gui-batch-session-lockout（单写者模型，
   批处理前用户关 GUI、跑动中不开、脚本显式 close_project）。
2. **run23 板级门**（用户在场，上板前确认"bd没问题，已通电"）：
   - 七步 overlay 正典全程（zynq-pynq-overlay-workflow skill）：
     预检（boot_id 冷启动 6min / ees331-camera failed=相机已拆非目标 /
     fpga0 operating=开机残留 / /dev/dri 空置——pgrep 撞远端 shell 自匹配
     用 ps 排除）→ 独立目录 + bit/hwh 同基名配对上传 + 双侧 sha 一致 →
     root venv python + XILINX_XRT=/usr 加载 → CK1 HWH 合同
     （**phys_addr**=0x43c00000/64K + CSR 0x43c10000 双从机）→
     CK2/3/4 download+operating+dmesg zocl 锁 +1 → CK5 fork 牺牲子进程首读
     （run06 纪律）+ 双身份命中（GEMM 0x20260919 / CSR 0x594F4C32 V0x0300）。
   - 功能三场景（序列=run21 TB 正典，oracle=Python 独立复刻 run15/21 数学）：
     | 场景 | 判据 | 结果 |
     |---|---|---|
     | S1 全幅 8×16 K=64 act=1 | 128 点回读+y_count=128 | **0 错**，STATUS=0x28 |
     | S2 掩码 0x5A/0x0F0F K=40 act=0 | 32 点+幻影槽保旧值 | **0 错**，stale@0 got=exp=0x25 |
     | S3 双块 K=96 乒乓+计算窗并发装载 | 128 点+y_count=128 | **0 错**，STATUS=0x38 |
     总账 wop=2464 rop=601 **rb_ok=288 rb_bad=0**；CK9 soft_rst 清扫绿
     （STATUS=0/y_count=0/ID 不变）→ CK10 **BOARD_B1_PASS**。
   - 板级结论：GEMM 数据通路真实硅片全功能闭环；2464 次 GP0 写零挂死
     （M13 写毒在本架构确证不存在）；y_count/tile 边界语义板上复现。
   - 装载完成判据升级：STATUS.bit3 ∧ LDLEN 双长度组合（严于 TB 单粘滞位，
     堵 S3 双 48 同长块陈旧粘滞假通过窗）；PS[r] 取 1..62 跳 TB 的 s=0 hh-X 角点。
3. **git 上传**（授权链："无误后上传"）：
   - worktree E:/competition_worktrees/FPGA2026_competition/pipidandan-superman
   - **86ae8a7** feat：yolo_gemm_top.v V1.0 + run21 TB + ycap IP 四件套 +
     axi_gemm_test BD 子树（18 文件，RTL 引用不拷贝）
   - **bb13563** evidence：run21/22/23 三门 19 文件；.log/.bit/.hwh 按
     .gitignore 豁免规则 `add -f` 并在提交信息申报 sha256
     （bit 6082d8b5… / hwh ed17c546…）；xsa 不入库（可再生）
   - 合并 origin/main（PR #9 gesture v2 权重重构 MODEL.md）遇一处冲突：
     main 侧 v2 现役+v1 折叠存档 vs 我方 2026-09-14 Zynq 部署节（f7c55a1 所加，
     base 无、非 main 删除）→ 双保留：main 骨架 + Zynq 节移出折叠块放文末，
     附 2026-09-19 状态更新行（原 BOARD_NOT_RUN 等占位旗标已过时）
   - **af407c0** merge → push **8fca71b..af407c0** 全量落远端；main 未动

## 证据位置

- 板级：`4_metrics/logs/2026-09-19_yolo_gemm_b1_run23_board/`（board_run23.log
  全程 + pl_gemm_b1.py + run_b1.sh + bit/hwh 配对 + README）
- BD/比特流：`4_metrics/logs/2026-09-19_yolo_gemm_b1_run22_bd_bitstream/`
  （run22_console.log + run22b_console.log + 三 rpt + README 含修复节）
- 远端：github pipidandan-superman/FPGA2026_competition 个人分支
  codex/full/pipidandan-superman @ af407c0

## 下一步（均需用户单独授权，板上动作用户在场）

- **B2**：PS-DMA 独立回环（DMA IP 集成 + BD 扩展 + 仿真门 + 板级）
- **B3**：DMA+GEMM 大 KC 连通
- **B4**：全联（GEMM+CSR+DMA+视频链）
- 顺序决策与资源预算见 1_docs/yolo_gemm_g2g4g7_execution_plan_20260919.md
