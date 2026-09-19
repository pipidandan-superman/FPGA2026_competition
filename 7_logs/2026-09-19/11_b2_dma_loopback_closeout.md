# 11 — B2 DMA 回环板级收官：BOARD_B2_PASS + skill 两处优化（run24）

日期：2026-09-19 晚　　结论：**一次上电一跑全绿**，GEMM+CSR+DMA 三从机
共存成为板上新基线。

## 过程（用户分工：GUI 加 DMA+接线+比特流；我：文件预检+板测，零仿真——官方 IP）

1. **配置指导**：axi_dma 7.1 逐项给出（SG 关/64b 流+映射/长度 20/仅对齐/
   同步时钟），用户 GUI 完成回环直连+连线自动化+比特流（17:59）。
2. **预检（PC 纯文件级）全绿**：时序 WNS+6.087/DRC0/DSP68 不变；地址表
   DMA=0x40400000/64K、GEMM/CSR 原样；回环/HP0/M02 连线逐条核；DMA 配置
   从 .xci（2025.2 为 JSON）逐参核；寄存器模型从 xci memory_maps 逐字转录
   进驱动（偏移/字段/复位值零猜测）。证据 preflight_bd_check.txt。
3. **上板（用户在场通电）七步正典**：
   - 预检新发现：**相机已接回**——ees331-camera 带**真实帧流**跑了 ~70s
     （journal 心跳 frames 38724→38854、VDMA 活跃）后才 failed 终态，且
     dmesg 有显式 `bitstream unlocked, ref=0` + `client exits pid(594)`。
     旧档案"相机已拆、35s 无帧失败"过时。我首轮等待循环在 active 即 break
     差点误判——教训：**预检必须等终态**。
   - 上传配对+双侧 sha 一致 → root 加载 → CK1 合同（4 IP、phys_addr 三址
     全中）→ CK4 zocl 锁 1→2 → CK5 fork 双首读（GEMM+DMA）+三 ID 全中。
4. **路径 A（GEMM 回归）**：S1/S2/S3+soft_rst 与 run23 **逐值相同**
   （128/32/128、STATUS 0x28/0x38、stale 0x25）——BD 加 M02+HP0 未波及。
5. **路径 B（DMA 回环）**：DB1 复位态（DMASR=0x1、SGIncld=0 硅上证实）→
   DB3 4096B 对拍 OK → DB4 尺寸扫描 137/**1**/1000/8192 全过（1B 部分
   拍）→ DB5 连发×3 → DB6 停止+软复位（DMACR 回 0x1002x 与 XCI 复位值
   逐位一致）→ DB7 交叉存活性（复位后 DMA 256B 恢复 + GEMM 新种子全幅
   S1 重跑 128/128）。
   总账 wop=3462 rb_ok=416 rb_bad=0 db_ok=9 db_bad=0 → **BOARD_B2_PASS**。
6. **板级结论**：HP 口启用不构成 overlay 障碍（fpga_manager 只写 PL）实证；
   CMA(allocate)+HP 非一致口免 cache 维护正典成立；DMA 与 GEMM 同位流
   共存互不干扰。
7. **skill 优化（用户指令落盘，经用户二次纠正后按通用性归位）**：
   - SKILL.md（通用方法论）：第 1 步补"预检等终态，active≠终态"；scope 节
     补"PS-PL 口使能（GP/HP/ACP/IRQ）是 FSBL 侧配置，不碍 overlay"；第 2 步
     补"寄存器模型从 IP 生成元数据（XCI memory maps）转录，不凭记忆"；
   - ees331.md（板卡画像）：仅更新相机服务既有条目的过时事实（接回+70s
     真帧后 failed+dmesg 显式释放）；
   - **IP/工程特定内容不进 skill**（用户原则：skill 是通用 overlay 方法论）：
     AXI DMA 驱动纪律归 PG021+驱动文件头注释（pl_b2_loopback.py docstring），
     地址表/连线/run 证据归本 README 与 4_metrics；原则已沉淀记忆
     skill-generality-principle。

## 证据

`4_metrics/logs/2026-09-19_yolo_gemm_b2_run24_dma_loopback/`（README +
preflight_bd_check.txt + board_run24.log + bit/hwh 配对 + pl_b2_loopback.py
+ run_b2.sh）；板上 /home/xilinx/gemm_b2_run24/ 双侧同。

## 下一步

B3：DMA+GEMM 大 KC 连通（需桥接设计立项：MM2S 流 → GEMM 装载口的握手
协议，用户单独授权）；板上现挂 run24 三从机基线。
