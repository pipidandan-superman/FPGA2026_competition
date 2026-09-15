# M9 dma 门 run01 — yolo_dma(2026-09-15)

## 结果:TB_DMA_PASS(CLOSED,5 跑过门:2 个 TB 比较陷阱 + 1 个真 RTL 串化器 bug + 1 个 TB 监视器宽度 bug)

210904 字节逐字节与 BFM 哈希一致,33/33 命令字节数 + 64b 加法校验和
全对,1666 个 AR 全部 8 对齐 / arsize=3 / INCR / 不跨 4KB / 地址链精确
覆盖 / 无超取,rlast 恰在各突发末拍;arready 30%、rvalid 25%、sink
背压 30% 随机停顿下完成。

## 工件

| 角色 | 文件 |
|---|---|
| RTL | `2_fpga/3_yolo_zynq/rtl/yolo_dma.v` V1.0(初版含串化器重构) |
| TB | `2_fpga/3_yolo_zynq/sim/tb_yolo_dma.v` V1.0 |
| 激励生成器 | `2_fpga/3_yolo_zynq/sim/dma_vecgen.py`(seed 909) |
| 激励 | `2_fpga/3_yolo_zynq/sim/stim/dma/`(n_cmds/cmd_addr/cmd_len/g_count/g_sum64,5 hex + manifest) |
| 本目录 | console_extract.txt / sim_dma.log(通过跑)/ sim_dma_run3_duplicate_byte.log(RTL bug 存档)/ stim_manifest.json / stim_sha256.txt |

## 合同(基线 §3.5/§5 M9 行)

- 命令(8 对齐地址 + 字节数 ≥1)在 S_IDLE 接受;done 单拍脉冲;
- 每 AR 拍数 = min(剩余字数, MAX_BURST=16, 距 4KB 边界拍数)——
  突发不跨 4KB 行;arlen=拍数−1、arsize=3(8B)、arburst=INCR;
- 字数驱动取数(len 上取整到整字,末字整字取回),字节数驱动交付
  (尾部只交付 len mod 8 字节,0→8,静态 tail_r 在命令接受时算好);
- 小端序逐字节(1B/拍)交付 sink,带背压;**串化器排空与状态无关**
  ——交付从不被取数 FSM 门控;
- R 拍接受条件:bcnt==0(缓冲空)或 bcnt==1 且 sink ready(末字节
  正离场);R 接受对 wbuf/bcnt 的写优先于移位;单在途 AR(arid 0)。

## 激励设计(33 命令,~21 万字节)

| 组 | 内容 | 目的 |
|---|---|---|
| 大长度 ×11 | 8/24/64/128/136/264/2048/4096/12288/65536/123456 B,地址残差贴 4KB 边界(4088/4096−64/4096−8 等) | 突发链切分、跨 4KB(8 条命令跨行)、多突发长流(max 965 突发) |
| 随机小命令 ×22 | 1..32 字,8 对齐随机残差 | 背靠背短命令 + done/接受握手 |

黄金 = BFM 数据函数 F(word_addr)(murmur 式 64b finalize,Verilog
f_word 与 python 逐位一致),字节 i = F>>8i;任意地址错/乱序/丢失/
重复都表现为逐字节错或校验和错。结构断言:≥30 命令、总字节 ≥10 万、
len∈{8,128,136}、全 8 对齐、≥1 跨 4KB、最大单命令突发数 >64。

## 过程记录(run1 → run5)

- **定稿前自查修掉三处**:① arready/out_ready 声明为 reg 却被连续
  assign 驱动 → 改 wire;② **out_ready 根本没有驱动器**(sink 背压
  从未接上)→ `assign out_ready = ~sink_stall;`;③ 末字尾长用动态
  `bytes_r<8 ? bytes_r : 8` 判定会受 sink 时序污染(bytes_r 含未交付
  旧字字节,可能错装 8)→ 改命令接受时静态算 `tail_r`。
- **run1(212230 错)**:TB 期望值没做字节掩码,按完整 64b 字比较;
  字节实际已对。修:中间 reg `expb = (F>>8*lane) & 8'hFF`。
- **run2**:TB 优先级陷阱——`a !== X >> s & mask` 按 `(a!==X>>s) &
  mask` 解析(`!==` 结合紧于 `&`),display 显示相等而比较仍失败。
  修:比较 `out_data !== expb[7:0]`。**与 M8 教训同族:位选/掩码必须
  括号或走中间变量。**
- **run3(209159 错)= 真 RTL bug**:got 流 = 期望流右移一字节
  (cmd3 idx10 起插重复字节)。根因:**字节串化器移位只写在 S_R 的
  else-if 分支**——FSM 中途回 S_AR 发下一 AR 时 out_valid 仍为 1 但
  wbuf 不再移位,同一字节被 sink 重复握手。重构:FSM + 串化器合并为
  单时钟块,**串化器在任意状态发火**(bcnt≠0 且 sink ready 即交付/
  移位),R 接受写优先,bytes_r==1 → S_DONE(单拍回 S_IDLE),删除
  S_DRAIN 状态,rready 加 beats_r≠0 保护。
  **经验:数据通路里的独立进程(串化/移位)不能挂在 FSM 的某个
  case 分支上——进程的生命周期与状态机正交,必须无条件运行。**
- **run4(101 错,数据 0 错)**:字节流完美、33/33 完成,但 AR 监视
  器假报 overfetch——`words_left_m[7:0]` 把 32 位剩余字数截成低 8 位
  (256/512/8192 → 0 → 16>0)。TB-only bug,run1–3 被字节错误洪流
  掩盖。修:`{24'd0, arlen+8'd1} > words_left_m`。
- run5 全绿(accepted,raw: sim_dma.log)。

## 环境与复现

- ModelSim SE-64 10.1c(vsim 必须 `-c -novopt`;6022380 ns 实测
  ~1 分钟);
- 复现:`python dma_vecgen.py` → `vlog -work work ../../rtl/yolo_dma.v
  ../tb_yolo_dma.v` → `vsim -c -novopt +STIM=../stim/dma +WDT_MS=60000
  -do "run -all; quit -f" work.tb_yolo_dma`(sim/msim 下)。

## 结论

M9 门通过,M0–M9 全绿。M10 集成注意:DMA 的 out_valid/out_data/
out_ready 直接接 wbuf/xbuf 写侧(或加一层写地址生成);done 脉冲接
ctrl 侧命令队列推进;MAX_BURST=16 为 AXI3 式上限,接 Zynq GP 口
(AXI4)时 HP 口支持 64 拍,如需更长突发在 M10 重参;单在途 AR 在
集成层如成带宽瓶颈,可加 2 深度 AR 流水(需相应扩 rlast 跟踪)。
