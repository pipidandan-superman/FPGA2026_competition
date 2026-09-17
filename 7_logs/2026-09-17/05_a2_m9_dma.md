# 2026-09-17（下午）A2 批 M9：yolo_dma V1.4 三门全绿

## 判决

- **TB_DMA_PASS LEGACY+BYTE bytes=210904 cmds=33 ars=1666 peak_ost=2**
  （V1.0 字节黄金 210,904B 原样复用、零漂移；突发链 1666 AR 序列不变）
- **TB_DMA_PASS PIPE+BYTE bytes=210904 cmds=33 ars=1666 peak_ost=2**
  （命令 FIFO 背靠背满背压；前视断言 ≥2 成立）
- **TB_DMA_PASS PIPE+WIDE bytes=154488 cmds=40 ars=1229 peak_ost=2**
  （stim/dma_w 新集：40 条全 len%8==0、cross4k=8、max 512 突发）
- 证据：4_metrics/logs/2026-09-17_yolo7020_m9_dma_v14/（三跑日志 +
  编译/装配日志 + README 缺陷留档）。

## RTL/TB 变更

- rtl/yolo_dma.v → **V1.4**：命令 FIFO(4)+影子 FIFO(4，满则背压
  规划器 pop)+规划器发火+1 拍结算（pop 胜 settle）+在途 AR≤2
  （blen_q 队列跟踪头突发余拍，含完成+发火同拍合队）+WIDE 生成式
  双模（字节 serdes = V1.3 语义逐拍；宽模单输出寄存 + pend_done
  只被消费它的 fire 清零——sink 停顿不丢 done）。
- 首稿清理：非法参数位选→localparam、bcnt 尾 mux 显式"命令首字/
  非首字"分派（dtail 陈旧值陷阱）、dbytes 在 r_fire∩byte_fire
  重合拍照常递减（start 装载同拍优先）、补 `timescale。
- sim/tb_yolo_dma.v → **V2.0**：参数化核 + 双顶层；多在途 BFM
  （突发队列深 4，头突发 4..11 拍延迟——零延迟下前视永不触发）；
  AR 监视器按命令队列；记分板结算 ACCEPT→DONE 且 done 判先于
  字节判（同拍竞态）；+PIPE 驱动 + 峰值在途断言；看门狗 64b 乘法。
- sim/dma_vecgen.py：+`--wide`（dma_w，seed 911）；字节集路径
  代码不变且未执行（stim/dma mtime 9-15 为证）。

## 抓获缺陷（两处同型：计数写了、指针没推进）

1. TB BFM bq_rp（现象：全命令复读 cmd0 首字；AR 监视零错误隔离出
   BFM 责任）。
2. DUT 影子 FIFO sf_rp cmd_start 不前进 → sf_head 恒 cmd0 条目
   （len8/words1）→ dbytes 每命令装 8、每拍 R 皆伪 cmd_start →
   done 每 8 字节一脉冲、字节流错位（cmd2 收到 cmd1 的 word1）。
   RTL 数值路径缺陷一处，属 A2 新码（V1.3 无此结构），已修并三门
   复验。§5 义务不变：后续 M10/M11/M12 随 A2 链各门重跑。

## 工具坑

- 旧 xsim 进程持旧快照时 xelab 重建同名 snapshot → 磁盘损坏，
  加载报 Simtcl 6-50；taskkill 残留进程 + 重建恢复。
- `-testplusarg KEY=VAL` 带 = 值被 xsim CLI 拒；裸 KEY 正常。
  STIM 改 TB 参数默认值绕开。

## A2 链进度

绿：M3（wbuf V3.0，TB_WBUF_PASS 21761 ops，实测 16 RAMB36/例×2）
/ M4（xbuf V2.2，16840 ops）/ **M9（本篇，V1.4 三门）**。
待做：xrowgen V1.0+M7 新门 → ctrl V2.0+M8 黄金重生成 →
gemm_array V2.0+M10（loader W/X 拆分、第二 DMA、REQUANT_UNITS、
acc 快照乒乓、X 组合口退役）→ csr dsc_walk 影子位+M12 →
M11 全网（vecgen 增 dsc_walk，ModelSim 为准）→ B0 OOC v28+ 解冻
（预期 wbuf BMG +32 RAMB36 增量）。
A2b 决策（X2/oc-pair，已书面向用户披露）待批，不阻塞 A2。
