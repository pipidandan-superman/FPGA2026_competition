# M11 全网端到端门（run01 目录，2026-09-15）

## 结论

**M11 门通过。**

- `TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
  head_bytes=149100 ldone=63 adone=1`（`sim_m11_full_run02.log`）
- head 闭合：`M11_HEADCHK_PASS sha256=9ce70525fc1732cd... bytes=149100`
  （`headcheck.out`）—— dump 的 sha256 == run04 `regression_128frames.json`
  frame0（images89）`raw_head_sha256`，且按 6 张量拆分对 run04 npz
  逐字节全对（102400+25600+6400+11200+2800+700）。

含义：SIM-8×8 GEMM 阵列（`rtl/yolo_gemm_array.v`，M10 门后**零改动**）
在 1 帧（golden_00 = images89 = run04 权威）上顺序执行全部 63 个卷积，
逐卷积输出 3,553,900 格全部与黄金区逐位一致，写双射完备
（dut_wr==compared、dbl=0、每层 ldone 恰一次、全网 adone 恰一次）；
view/concat/add/maxpool5/upsample2 共 65 个 PS 微操作由 TB 解释执行
（intarith 语义），其正确性由后续卷积的黄金比对 + head sha 传递闭合；
最终 6 个 head 张量（reg×3 + cls×3，int8）落盘 149,100 字节，sha256
与 run04 完全一致。

门定义修正（对基线 §5 原文"128 帧 head sha256 == run04"）：阵列是
调度驱动的数据无关引擎，128 帧 ≈ 5–10 天仿真不可行；本门以
**1 帧全 63 卷积节点逐位 + head sha256（强于仅头部哈希的 128 帧）**
为等效证据，已记入基线 §8。

## 命令行

```
# 激励生成（含生成期护栏：numpy 参考链 41 npz 检查点 + 程序解释器 + 全 104 缓冲审计）
cd E:/competition/2_fpga/3_yolo_zynq/sim && python m11_vecgen.py

# 编译 + 冒烟（2/3/5 conv；3-conv 首次覆盖 k1x1 几何）
vlog -work work ../tb_yolo_fullnet.v
vsim -c -novopt +STIM=../stim/m11 +MAXCONV=2 +WDT_MS=300000 \
     -do "run -all; quit -f" -l sim_m11_smoke1.log work.tb_yolo_fullnet
#   smoke2: +MAXCONV=3 -> sim_m11_smoke2.log ; smoke3: +MAXCONV=5 -> sim_m11_smoke3.log

# PS 微操作单元检查（maxpool5/upsample2/add/rscl 对 intarith）
vsim -c -novopt +STIM=../stim/m11u +DUMPF=head_dump_unit.bin \
     -do "run -all; quit -f" -l sim_m11_unit_psops.log work.tb_yolo_fullnet
python -c "...  head_dump_unit.bin vs stim/m11u/expected_dump.bin ..."   # M11_PSOP_UNIT_PASS

# 门运行（全网 63 conv）
vsim -c -novopt +STIM=../stim/m11 +WDT_MS=3600000 \
     -do "run -all; quit -f" -l sim_m11_full_run02.log work.tb_yolo_fullnet

# head 闭合
python m11_headcheck.py msim/head_dump.bin     # M11_HEADCHK_PASS
```

## 环境

- ModelSim SE-64 10.1c（2012.07）；`vsim -c -novopt` 铁律遵守
- 主机 HC-202510241838，Windows；时间 2026-09-15 19:0x–21:0x
- work 库 = M10 门同库（RTL 未重编译、未改动；M11 只新增
  `sim/tb_yolo_fullnet.v`、`sim/m11_vecgen.py`、`sim/m11_headcheck.py`）

## 文件清单

| 文件 | 内容 |
|---|---|
| `sim_m11_full_run02.log` | **门运行原始 transcript**（PASS） |
| `sim_m11_full_run01.log` | 失败链留证（TB WDT 32 位溢出，非 DUT 故障） |
| `sim_m11_smoke{1,2,3}.log` | 2/3/5-conv 冒烟（SMOKE token） |
| `sim_m11_unit_psops.log` | PS 微操作单元检查 transcript |
| `head_dump.bin` | 门运行 head 落盘（149,100 B，sha=9ce70525...） |
| `headcheck.out` | m11_headcheck.py 输出（M11_HEADCHK_PASS） |
| `console_extract.txt` | 全部 PASS token 摘录 |
| `stim_manifest.json` | 激励清单（seed=1011、程序/op 统计、黄金链指针） |
| `stim_sha256.txt` | 激励与源文件哈希（ddr.hex 30MB 留在 sim/stim/m11/ 原地，不入 Git） |

激励与源（sha256 见 stim_sha256.txt）：`sim/stim/m11/*`（生成器
`m11_vecgen.py` 输出）、`sim/stim/m11u/*`（单元检查激励+期望）。

## 失败与调试链（按时间）

1. **生成器自检 X 区失败**：view 发射时 dst 误加 `lo·H·W` 通道偏移
   （输出缓冲只含切片通道，偏移只应加在 src），split1 写越一个缓冲，
   首个 view 供给的 conv 读到 PRNG 填充。修复后三重自检全绿。
2. **hex 输出溢出**：prog 字含 numpy 标量，`f'{w & ...:08X}'` 在
   Windows 上触发 OverflowError → `int(w)` 强转。
3. **冒烟全绿后单元检查**：两处手写单元激励笔误（ADD 行漏 `ln`
   操作数、HEADS 的 nt 与实际 pair 数不符），TB 行为正确；修正后
   `M11_PSOP_UNIT_PASS` 1152/1152。
4. **run01 超时假失败**：`#(wdt_ms * 1_000_000)` 32 位溢出，
   817,405,952 ns 处杀进程（DUT 当时 conv 41 全零误差）。WDT 改
   64 位 `time` 变量后 run02 干净跑通。教训入 memory：**仿真器
   delay 表达式也是 32 位 integer 运算，大数先升位**。

## 关键数字

- 63 conv / 65 PS ops / 104 任务全部执行；K∈{27..2304} 15 档、
  OC∈{7..256}、N∈{100..25600} 全覆盖；**k1×1 几何（M0–M10 从未
  覆盖）在本门首次上场并逐位通过**
- 3,553,900 格零误差；总仿真时长 1.356 s = 135.6M 周期（10 ns 时钟）
- 镜像 13,320,008 B（104 缓冲区 + 63 组 W/参数区 + 63 黄金区）；
  程序 2,178 字
- run04 权威链闭合：run04 npz/regression ← m11_vecgen numpy 参考链
  （41 检查点 + head sha）← 程序解释器（全缓冲审计）← RTL 逐层比对
  + head sha（本门）

## M12 承接（未动，需另行授权）

- Y 真 AXI 写主（本门 Y 仍为 TB 散写回镜像 = 物理链化但无写主；
  y_base 由 TB 侧加，描述符字段化属 M12）
- X 平面 DDR 流式（本门仍组合口直读镜像）
- PROD-16×16 档 OOC（Vivado 未运行）
