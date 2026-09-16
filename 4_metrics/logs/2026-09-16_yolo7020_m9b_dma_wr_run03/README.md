# M9b dma_wr 门 run03 —— V1.2 非对齐起始（2026-09-16）

## 结果：TB_DMA_WR_PASS（run03a 失败链留证[vecgen 黄金 bug，非 RTL] + run03b 全绿）

410,255 字节 DDR 侧逐字节值 + 写双射全对，45/45 命令计数/64b 加法校验和全对，
3,240 个 AW 全部 awaddr 8 对齐（内部下对齐）/ awsize=3 / INCR / 不跨 4KB /
地址链精确覆盖 / 无超取 / 单在途 / 每突发末拍 WLAST；**28 条非对齐命令
（head=0..7 全覆盖）首字 wstrb 掩 head、每字节落在 cmd_addr+k 精确地址**；
aw 30%/w 25%/源 30% 随机停停 + B 0–3 拍随机延迟下完成；源侧喂送 == DDR 侧
落盘（410,255 == 410,255）。

## 为什么扩展（M12 A1 阵列 Y 行段化前置）

阵列 Y 行段化器按行发 dma_wr 命令：行起始 = ybase + oc_g*n_total +
n_tile*N_EDGE。真实层 n_total∈{100,400,1600,6400,25600} —— 100=4·25 非 8
倍数（18 层），奇 oc 行起始 ≡4 mod 8；M10 合成层 n_total 任意。V1.1 合同
"cmd_addr 8 对齐"不成立 → dma_wr V1.2 非对齐起始支持。

## RTL 变更（rtl/yolo_dma_wr.v V1.1 → V1.2）

- 命令地址任意字节对齐：awaddr = cmd_addr 下对齐 8B（AXI awsize 对齐）；
- 装配计数 bcnt 从 head=cmd_addr[2:0] 起（源字节 k → 首 word lane head+k）；
- 首字 wstrb 掩 head lanes（9 位中间式 `(1<<bcnt)-1 & ~((1<<lo)-1)`，
  lo_r 首字发完清 0）；
- 覆盖字数 words = ceil((head+len)/8)（4KB 切分随之正确）。
- **head=0 时与 V1.1 逐位等价**（A 组 11 条对齐大长度命令零差异回归）。

## TB/vecgen 变更

- `dma_wr_vecgen.py` V2（seed 912）：A 组 11 条 8 对齐大长度（回归基线）
  + B 组 head=0..7 全覆盖小命令（len 1..8 逼首字掩码×尾字交互）+ C 组
  大长度非对齐（123456@head5 / 65536@head3 / 12288@head7 贴行尾 /
  136@head1）+ D 组 22 条随机小命令任意残差。断言新增 head 全覆盖、
  非对齐 ≥10。**黄金 sum 表达式修正**：`wa=addr+8*(i>>3)` 仅在 8 对齐时
  等价 F_byte(addr+i)，非对齐时 word 地址与 lane 双错（run03a 失败链，
  见下）；改为 `a=addr+i; f_word(a&~7)>>8*(a&7)`。
- `tb_yolo_dma_wr.v` V1.2：AW 链期望起点改 cmd_addr 下对齐、覆盖字数 =
  ceil((head+len)/8)（两处）；W 记分板按物理地址查值——原逻辑即对
  （unstrobe 的 head lanes 不检），零改动。

## 过程记录（run03a → run03b）

- **run03a（失败链，m9b_run03a_fail_vecgen_gold.log）**：45 命令 28 条 sum
  失配，**且仅 sum 一类错**——逐字节 F_byte 值/双写/缺写/计数/AW 链/WLAST
  全零错，bytes==fed；失配恰好全部落在 cmd 12..44（首条非对齐起），A 组
  0..11（全对齐）零失配 ⇒ DUT 行为正确、vecgen 黄金 sum 表达式 bug。
- **教训两条**：① 黄金第二来源（sum/checksum）的捷径表达式必须在扩展
  合同后重推导，不能沿用仅对旧域成立的简写；② 失败跑与通过跑必须用
  不同 log 名（本 run 首跑 transcript 被同名覆盖，失败链从会话记录重建）。
- **run03b（PASS，m9b_run03_pass_v1p2.log）**：零错误全绿；12.24ms 仿真。

## 命令与环境

```
cd E:\competition\2_fpga\3_yolo_zynq\sim
python dma_wr_vecgen.py                       # seed 912, 45 cmds / 410255 B
cd msim
vlog -work work ..\..\rtl\yolo_dma_wr.v ..\tb_yolo_dma_wr.v
vsim -c -novopt +STIM=../stim/dma_wr +WDT_MS=120000 -l m9b_run03.log ^
     -do "run -all; quit -f" work.tb_yolo_dma_wr
# 期望: TB_DMA_WR_PASS bytes=410255 fed=410255 cmds=45 aws=3240
```

主机 HC-202510241838（Windows 11 企业版）；ModelSim SE-64 10.1c（`-c -novopt`
铁律）；Python 3.12.10（numpy）。RTL/TB/激励 sha256 见 stim_sha256.txt（绝对路径，
5 stim hex + 3 源文件）。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS token 摘录）
3. m9b_run03_pass_v1p2.log（通过 transcript 原件）+ m9b_run03a_fail_vecgen_gold.log
   （失败链，会话记录重建——原件被同名覆盖，README 过程记录说明）
4. stim_manifest.json + stim_sha256.txt

## 结论

dma_wr V1.2 M9b 门通过。非对齐起始合同冻结：任意字节对齐命令地址，每
strobe 字节落在 cmd_addr+k。yolo_gemm_array V1.2（Y 行段化 + u_dma_wr
实例 + y_rdy 背压）开工。
