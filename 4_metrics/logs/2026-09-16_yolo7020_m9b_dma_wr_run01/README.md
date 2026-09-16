# M9b dma_wr 门 run01 —— yolo_dma_wr（2026-09-16）

## 结果：TB_DMA_WR_PASS（CLOSED，2 跑过门：run01 失败链留证 + 修复后 run02 全绿）

210,488 字节 DDR 侧逐字节值 + 写双射全对，33/33 命令计数/64b 加法校验和全对，
1,663 个 AW 全部 8 对齐 / awsize=3 / INCR / 不跨 4KB / 地址链精确覆盖 / 无超取 /
**单在途**（前一突发 WLAST 前不再发 AW），每突发末拍 wlast 恰好置起、无 beat 越界；
awready 30%、wready 25%、源背压 30%、B 响应 0–3 拍随机延迟随机停停下完成；
**源侧喂送 210,488 == DDR 侧落盘 210,488**（两侧独立计数闭合）。
done 语义 = 末字发出且发一收一的 B 计数对齐（多突发命令 965 突发排空覆盖）。

## 文件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_dma_wr.v` V1.1（V1.0 两处 AXI 缺陷修复，见下） |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_dma_wr.v` V1.1（生产者竞态修复，见下） |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/dma_wr_vecgen.py`（seed 911） |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/dma_wr/`（n_cmds/cmd_addr/cmd_len/g_count/g_sum64 五 hex + manifest） |
| 本目录 | console_extract.txt / m9b_run01_fail_v1p0.log（失败链原始 transcript）/ m9b_run02_pass_v1p1.log（通过 transcript）/ stim_manifest.json / stim_sha256.txt |

## 合同（基线 §3.5/§5，M12 A1 承接：Y 真 AXI 写主）

- 命令（8 对齐地址 + 字节数 ≥1）在 S_IDLE 接受；done 单拍 = 末字发出且所有 AW 的 B 收齐；
- 每 AW 拍数 = min(剩余字数, MAX_BURST=16, 距 4KB 边界拍数）——突发不跨 4KB 行；
- **每突发末拍必带 WLAST**；突发链化：burst 末拍后 words未尽→S_AW 发下一 AW，尽→S_DR 排空 B；
- 源字节拉取制（src_valid/src_data/src_ready，源保持到接受）；**小端装配：源字节 k → 字节通道 k**（读通道串行化的精确逆：地址 A 的字 == 读通道 rdata(A) 逐位）；
- 尾字 wstrb = (1<<bcnt)−1 低位有效；W beat 允许间隙（装配受源节拍）；
- B：单 id 保序，bready 常高，状态无关独立计数（M9 纪律：响应不挡 AW/W 引擎）。

## 激励设计（33 命令，~21 万字节，镜像 M9 seed 909 → 911）

| 组 | 内容 | 目的 |
|---|---|---|
| 大长度 ×11 | 8/24/64/128/136/264/2048/4096/12288/65536/123456 B，地址残差贴 4KB 边界（4088/0/4096−64 等） | 突发链切分、跨 4KB（7 条）、多突发长命令（max 965 突发，B 排空压力） |
| 随机小命令 ×22 | 1..32 字、8 对齐随机残差 | 背靠背短命令 + done/接受/源握手 |

黄金 = **DDR 侧语义**：地址 a 处字节必须等于 F_byte(a)=F(word(a))>>8·(a%8)
（F 为 M9 同款 murmur 式 64b finalize，Verilog/Python 逐位一致）。基地址错、
lane 交换、字节序错、丢失/重复/错位全部表现为逐字节值错或双写/缺写。
完备性 = 每命令写双射（命令相对位图：双写即时报错 + done 时全 1 巡检）+
计数/校验和 + AW 地址链精确覆盖闭合。命令间允许地址重叠（位图命令相对，
值按地址键，重叠不产生假失败）。

## 过程记录（run01 → run02，三个真 bug）

- **run01（失败链，m9b_run01_fail_v1p0.log）**：两类错误——① `ERR wlast@beat 2 of 2`
  ×8 与楔死（首个多突发命令处挂起，B 从站 busy 永不释放）；② word1 起字节
  整体错位（数值核对：word1 lane k = 字节 7+k，word2 = lag-2，b18≡b20=0x18
  使表面"反转"为错觉——run01 期 m9b_dbg_perm.py 临时脚本核对后删除）。
- **RTL V1.0 缺陷 ①（WLAST）**：`wlast_o = final_word_w`（命令末字）——AXI 要求
  **每突发**末拍置起；读通道 rlast 镜像时漏掉。修复：`wlast_o = (state==S_W) && (beats_r==1)`。
- **RTL V1.0 缺陷 ②（突发链化）**：状态转移挂 `final_word_w`——非末突发打完
  停在 S_W、beats_r 下溢继续发无 AW 的 beat。修复：转移挂 burst 末拍
  （beats_r==1），words_r==0 选 S_DR、否则回 S_AW；last_burst_r 冗余删除。
- **TB V1.0 生产者竞态**：握手在 negedge 计数，而 `src_ready` 是 DUT 状态组合且
  **接受行为本身改变它**（bcnt→8 拉低、w_fire 清零又拉高）→ 接受拍 P 漏计、
  P+1 拍多计成对出现，同字节重复呈现（= 错位观测的直接机制）。修复：握手
  改 posedge 本拍捕获（valid/ready 与 DUT 判决输入同值同拍），呈现仍 negedge
  驱动。**教训入册：ready 由 DUT 状态组合驱动的valid源侧握手，必须 posedge 采样**。
- **run02（PASS，m9b_run02_pass_v1p1.log）**：零错误全绿；仿真时长 6.27ms。

## 环境

- 主机 HC-202510241838（Windows 11 企业版）；ModelSim SE-64 10.1c（vsim `-c -novopt`
  铁律）；Python 3.12.10（numpy 激励生成）；RTL/TB/激励 sha256 见 stim_sha256.txt。

## 复现

```
cd E:\competition\2_fpga\3_yolo_zynq\sim
python dma_wr_vecgen.py                       # 生成 stim/dma_wr/（seed 911）
cd msim
vlog -work work ..\..\rtl\yolo_dma_wr.v ..\tb_yolo_dma_wr.v
vsim -c -novopt +STIM=../stim/dma_wr +WDT_MS=2000 -l m9b_run02.log ^
     -do "run -all; quit -f" work.tb_yolo_dma_wr
# 期望: TB_DMA_WR_PASS bytes=210488 fed=210488 cmds=33 aws=1663
```
