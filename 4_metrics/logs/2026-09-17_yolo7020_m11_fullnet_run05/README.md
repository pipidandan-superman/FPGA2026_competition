# M11 全网门 run05 —— A2 loader V2 承证（gemm_array V2.0c，2026-09-17）

用户授权链：`先M11，然后12，13. 上板看过结果后再决定是否继续优化`（2026-09-17）。
本跑 = A2 三件套 RTL 首次全网（63 conv + 65 PS op）承证，M12 OOC/M13 上板的前置门。

## 与 run04（v27 B0 基线）的差异

| 项 | run04 (v27) | run05 (A2) |
|---|---|---|
| gemm_array | V1.10（addrgen+conv_core 拼装） | **V2.0c**（ctrl+双 dma+xrowgen+wbuf/xbuf V3.0+pe_pack+acc+requant+silu_lut+dma_wr，Fix #9–#12） |
| X 供数 | 组合口 `x_addr_o/x_rdata_i` 直读镜像 | **DUT 第二条 AXI4 读主**（dma V1.4 + xrowgen V1.3 + xbuf V3.0 行段流式） |
| W 缓存 | wbuf V2.x 行为阵列 | **wbuf V3.0 + yolo_wbuf_bmg**（跨 n_tile 持久，BMG） |
| walk 序 | 固定 | **dsc_walk_i**（prog token16，e=8 逐层最优：38 oc 外序 / 25 n 外序） |
| TB | V1.1（X 组合服务） | **V1.2**（W/X 双 inline 4 深突发队列 BFM，活镜像服务，bfmerr 判据） |
| 激励 | prog token16=0 | prog.hex 仅 38 词 token16 0→1；ddr/lut/n_* 与冻结集逐字节同（manifest sha 承证） |

## 数值合同（冻结，与 run04 逐字段可比）

```
TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
                 head_bytes=149100 ldone=63 adone=1 bfmerr=0/0
python ../m11_headcheck.py head_dump.bin
  -> sha256 == 9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad
```

## 结果

- **SMOKE（MAXCONV=3，2026-09-17 22:4x–23:0x，a2_m11_smoke.log）**：
  ```
  TB_FULLNET_SMOKE convs=3 psops=2 compared=819200 dut_wr=819200
                   head_bytes=0 ldone=3 adone=1 bfmerr=0/0 wost=2 xost=2
  ```
  - conv0 @t=16.161ms walk=**1**（oc 外序）、conv1 @42.681ms walk=**1**、
    conv2 @52.130ms walk=**0**（n 外序）—— 两种 walk 序均实证 acc_err=0。
  - vs v27 run04 同层：conv0 23.273ms→16.161ms（**−31%**）、conv1 64.876ms→42.681ms
    （**−34%**）—— A2 装载/计算重叠的每层加速签名（SIM e=8）。
  - bfmerr=0/0：W/X 双 4 深突发队列 BFM 协议干净（对齐/arsize/arburst/OOB 全过）；
    wost=xost=2：两读主峰值在途 2。
- **FULL（63 conv + 65 PS op，2026-09-18 01:15 判定，a2_vsim_stdout.log）**：
  ```
  TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
                  head_bytes=149100 ldone=63 adone=1 bfmerr=0/0 wost=2 xost=2
  ```
  - 63 conv 全部 acc_err=0（非零计数 0）；bfmerr=0/0（W/X 双 BFM 协议干净）；
    ldone=63/adone=1（层/全帧门铃全响）。
- **headcheck（2026-09-18 01:15）**：
  `sha256(head_dump.bin) = 9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad`
  —— 与冻结合同**逐字节一致**（= PC 驱动自测同值）。Y 通路全网位精确。
- 墙钟/仿真时间/fps 对照：全帧 sim t=855.129ms（TB 时钟）；逐层步进表
  `conv_step_times_ms.txt`（conv,task,step_ms —— 板端逐层 ms 的对照基准，
  步进含层间 PS op 时间）。板端 60MHz first-light 判据见 m13 run01 README。

## 复现（cwd `sim/msim_a2`）

```
bash run_m11_a2.sh smoke   # MAXCONV=3 冒烟
bash run_m11_a2.sh         # 全网 + headcheck
```

## 哈希清单（sha256 前 16 位，2026-09-17）

```
24dc59f4cfd0cef9  rtl/yolo_gemm_array.v   (V2.0c, 与 M10 run13 同版)
430f3c64d86cb817  rtl/yolo_ctrl.v         (V2.0)
5f99ffd89b0b5ec7  rtl/yolo_dma.v          (V1.4, W/X 双实例)
5aa9487bfb09f2ba  rtl/yolo_xrowgen.v      (V1.3, 与 M7 run02 同版)
99b545b4e7543810  rtl/yolo_wbuf.v         (V3.0)
2a745db790f8351d  rtl/yolo_xbuf.v         (V3.0)
7072bbae3f337a75  rtl/yolo_pe_pack.v      (V1.2)
f4107fa2a63e1699  rtl/yolo_acc.v
1261433d7a07317c  rtl/yolo_requant.v      (V1.2g)
30423c61a4909f41  rtl/yolo_silu_lut.v
79598e4c225b5cbb  rtl/yolo_dma_wr.v
7402567aef5025c7  ip/yolo_wbuf_bmg/sim/yolo_wbuf_bmg.v
a173318cf6d0ef7d  ip/yolo_xbuf_bmg/sim/yolo_xbuf_bmg.v
cd505f9c73f20887  ip/yolo_xbuf_bmg/simulation/blk_mem_gen_v8_4.v
99df595c5e1eb8bb  sim/tb_yolo_fullnet.v   (V1.2)
f4731fc76341b3ba  sim/m11_vecgen.py       (walk 规则版)
e3a55410a64dd648  sim/stim/m11/ddr.hex    (与 v27 冻结集逐字节同)
929d9f33b481ffd6  sim/stim/m11/lut_all.hex(同上)
f5efb47be696653b  sim/stim/m11/prog.hex   (仅 38 词 token16 0→1)
ecf853505cc21a5b  sim/stim/m11/stim_manifest.json
```

注：addrgen/conv_core 已不入 A2 编译集（gemm_array V2.0 不再例化）。

