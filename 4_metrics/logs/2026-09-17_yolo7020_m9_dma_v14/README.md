# 2026-09-17 yolo7020 M9 DMA 门 — V1.4（A2 批：命令 FIFO + 双在途 AR + WIDE 双模）

## 结果（三门全绿）

| 跑 | stim | 判决行 |
|---|---|---|
| LEGACY+BYTE | sim/stim/dma（V1.0 黄金原样复用，磁盘未动） | **TB_DMA_PASS bytes=210904 cmds=33 ars=1666 peak_ost=2** |
| PIPE+BYTE | 同上 | **TB_DMA_PASS bytes=210904 cmds=33 ars=1666 peak_ost=2** |
| PIPE+WIDE | sim/stim/dma_w（新宽模集，seed 911） | **TB_DMA_PASS bytes=154488 cmds=40 ars=1229 peak_ost=2** |

- LEGACY 字节总数 210,904 与 V1.0/V1.3 黄金逐字节一致（黄金文件
  mtime 9-15 未触碰）；ars=1666 突发链序列不变（V1.4 重定时承诺
  兑现：同一 (addr,beats) 链、同一顺序）。
- PIPE 峰值在途 AR=2：命令 FIFO(4) 背靠背背压 + 前视断言（≥2）成立
  ——xsim 2025.2，`-R -testplusarg PIPE`。
- WIDE：40 命令全 len%8==0（合同），64b 字直出 + sink 背压随机停停，
  黄金按"每字累加 8 字节"同格式复用（count=字节数、sum64=逐字节和）。

## 本跑覆盖的 RTL / TB

- rtl/yolo_dma.v **V1.4**（本门首过；B0 冻结点仍为 V1.3，A2 链
  M10/M11 重做时随 gemm_array V2.0 批切换）。
- sim/tb_yolo_dma.v **V2.0**：参数化核（WIDE/STIM_DEF）+ 双顶层
  tb_yolo_dma / tb_yolo_dma_w；多在途 BFM（突发队列深 4 + 头突发
  4..11 拍延迟建模 HP 延迟——零延迟 BFM 下前视永不触发）；AR 监视
  器按命令队列（V1.0 接受沿锁 exp_next 在前视下失效）；记分板
  结算沿 ACCEPT→DONE 且 done 判先于字节判（同拍竞态：done(cmd i)
  与 cmd i+1 首字节可同 posedge）。
- sim/dma_vecgen.py：`--wide` 增 dma_w（40 条/154,488B/cross4k=8/
  max_bursts=512），字节集路径代码不变、未执行（stim/dma 原样）。

## 抓获缺陷留档（两处同型：occupancy 记数、指针不推进）

1. TB BFM `bq_rp` 头完成不前进 → 所有命令复读 cmd0 首字
   （首跑现象：每命令 got 恒 a4e0…0f）。AR 监视器零错误佐证 DUT
   突发序列正确，隔离出 BFM 责任。
2. DUT 影子 FIFO `sf_rp` 在 cmd_start 不前进（sf_cnt 有 --）→
   sf_head 恒指 cmd0 条目（len=8/words=1）：dbytes 每命令装载 8、
   dwords 归 0 使每拍 R 皆伪 cmd_start → done 每 8 字节一脉冲、
   字节流整体错位到后续命令（次跑现象：cmd1 首字正确后早 done、
   cmd2 收到 cmd1 的 word1、k_sb 越过 33 读到 X）。
   两处均为"写了占用计数、漏了指针推进"同一模板，修复后三门绿。

## 工具坑留档

- xsim 旧进程持旧快照运行时 xelab 重建同名 snapshot → 磁盘快照
  损坏，后续加载报 `Simtcl 6-50 engine failed to start`；taskkill
  残留 xsim.exe/xsimk.exe 后重建 snapshot 恢复。长跑期间避免对同
  名 snapshot 重建（或换名）。
- `-testplusarg STIM=../stim/dma`（带 = 值）被 xsim CLI 拒
  （"Expected a switch but found ."）；裸 `-testplusarg PIPE` 正常。
  STIM 改为 TB 参数默认值（宽模顶层默认 ../stim/dma_w）绕开。
- TB 看门狗 `#(wdt_ms * 1_000_000)` 整型乘法 2^31 回绕产生负延迟
  警告 → `* 64'd1_000_000`（V1.0 TB 同病，一并修）。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim
python dma_vecgen.py --wide          # stim/dma_w（一次性）
cd xsim
cmd //c "F:\vivado2025\2025.2\Vivado\bin\xvlog.bat \
  E:\competition\2_fpga\3_yolo_zynq\rtl\yolo_dma.v \
  E:\competition\2_fpga\3_yolo_zynq\sim\tb_yolo_dma.v -log m9_v14_xvlog.log"
cmd //c "F:\vivado2025\2025.2\Vivado\bin\xelab.bat -debug typical \
  tb_yolo_dma -s m9b14 -log m9_byte_xelab.log"
cmd //c "F:\vivado2025\2025.2\Vivado\bin\xsim.bat m9b14 -R \
  -log m9_byte_legacy.log"                    # 门1 LEGACY+BYTE
cmd //c "F:\vivado2025\2025.2\Vivado\bin\xsim.bat m9b14 -R \
  -testplusarg PIPE -log m9_byte_pipe.log"    # 门2 PIPE+BYTE
cmd //c "F:\vivado2025\2025.2\Vivado\bin\xelab.bat -debug typical \
  tb_yolo_dma_w -s m9w14 -log m9_wide_xelab.log"
cmd //c "F:\vivado2025\2025.2\Vivado\bin\xsim.bat m9w14 -R \
  -testplusarg PIPE -log m9_wide_pipe.log"    # 门3 PIPE+WIDE
```
