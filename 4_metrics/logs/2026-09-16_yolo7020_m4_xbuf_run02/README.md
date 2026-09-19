# 2026-09-16 yolo7020 M4 X 缓冲 门（run02，xsim + V2.0 BMG IP 版）

## 目标
M12 B0 修复批的 xbuf 侧门重跑：`yolo_xbuf` 存储从 16 列 × 2 bank 分布式
LUTRAM（OOC 实测 13824 LUTRAM = RAM64M × 3456，ooc_dbg1 层次化资源报告）
改为 **2 × Vivado 原生 blk_mem_gen IP**（用户指示：能用原生 IP/源语处
全部原生化）。外部契约不变：写 1 字节/拍、共享 k 地址 16 列广播读、
读延迟 1 拍、en=0 保持、双 bank 独立。

## IP 配置（ip/gen_xbuf_bmg.tcl，每 bank 一个实例）
- Simple Dual Port RAM：端口A 只写 128b × 2304 深，端口B 只读 128b
- 字节写使能 16 × 8bit：写侧 DINA={wdata×16} 广播 + WEA one-hot 列选
- Operating_Mode_A = READ_FIRST：同地址同拍写读 → 读旧值 == V1.0
  非阻塞参考语义
- 端口B 无输出寄存 → 读延迟 1 拍（与 V1.0 同）；ENB=ren（en=0 保持）
- 资源（单 bank）：**10 RAMB36E1 + 140 LUT + 0 DSP**（双 bank 20 RAMB36）

## 等价性设计要点（激励审计先行，sim/xbuf_stim_audit.py）
冻结 97464 操作审计锁定三个必须显式处理的角落：
1. **首读前 433 个写操作期望 dout=0** → `rd_active_q` 粘滞门控把输出
   钳 0 直到首个读落拍（不依赖 BMG 模型上电值）；
2. **保持拍（ren=0）rd_bank 变化 85859 次** → 读侧 bank 选择用寄存
   `rd_bank_q`（仅 ren=1 时采样），保持语义 = 上次读 bank 的保持数据
   （与 V1.0 输出寄存器永不重采样等价）；活选通必然大量失败；
3. **同 bank 同拍写读碰撞 0 次**（门不触碰碰撞语义；READ_FIRST 仍为
   真实流量保留 V1.0 语义）。
另：读未写地址 0 次、evld/保持期望与参考模型一致（AUDIT_OK）。

## 结果

**TB_XBUF_PASS compared=97464 ops (dout+vld)**——与 run01 同一冻结
激励（10 个 sha256 逐一相符 = 零漂移），一次通过。V2.0 与 Python
位模型逐位一致。

## 仿真环境
- xsim（Vivado 2025.2）+ 官方 BMG 预编译库：
  `xelab tb_yolo_xbuf glbl -s snap_m4 -L blk_mem_gen_v8_4_12 -L unisim
   -L unisims_ver -timescale 1ns/1ps`，自 sim/xsim 运行
- 原始日志：m4_xvlog.log / m4_xelab.log / m4_xsim.log（本目录）；
  IP 资源报告 yolo_xbuf_bmg_util.rpt；生成日志 ip/gen_xbuf_bmg_console.log

## 变更清单（数值路径不变）
- `rtl/yolo_xbuf.v` V1.0 → V2.0（BMG ×2 包装器；端口/时序/复位语义不变）
- 新增 `ip/yolo_xbuf_bmg/`（XCI + DCP）与 `ip/gen_xbuf_bmg.tcl`
- TB 未改（tb_yolo_xbuf.v 保持 V1.0——契约未动）

## 上游证据
2026-09-15_yolo7020_m4_xbuf_run01（V1.0 基准 PASS）；ooc_run01 失败链
（proj/ooc_gate/ooc_run01_vivado.log，保留不改写）。
