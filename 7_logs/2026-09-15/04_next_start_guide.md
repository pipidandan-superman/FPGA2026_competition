# 2026-09-15 下次启动指南

## 当前：G3 M11 全网端到端门全绿收批（2026-09-15 晚，M12+ 待新授权）

1. **批次状态**：M0–M10 全 CLOSED + **M11 全网门（TB_FULLNET_PASS +
   M11_HEADCHK_PASS，"ok，先做M11"授权批）**。1 帧（golden_00=images89=
   run04 权威）SIM-8×8 顺序执行全部 63 conv：3,553,900 格逐位零误差、
   写双射完备；65 个 PS 微操作（view/concat COPY+RSCL/add/maxpool5/
   upsample2/heads）由 TB 扮 PS 按 intarith 语义解释执行；head 落盘
   149,100B sha256 == run04 frame0 且 6 张量拆分对 npz 逐字节全对。
   **k1×1 几何首次覆盖并通过**（M0–M10 全 k3×3）。RTL 零改动。
   入口：`4_metrics/logs/2026-09-15_yolo7020_m11_fullnet_run01/`
   （TB `sim/tb_yolo_fullnet.v` + 生成器 `sim/m11_vecgen.py` + 闭合器
   `sim/m11_headcheck.py`）。门定义修正（128帧→1帧全节点+head sha）与
   M12 数据面承接清单已入基线 §8。
   **本批执行窗已收：M12（OOC/Vivado）/M13（板卡）均未动，需另行单独授权。**
2. **下一批 = M12 OOC 综合（PROD-16×16）**（基线 §5/§9；需用户单独
   授权再开）。动工前先对基线 §8 记录架构决策，起步要点（M11 承接
   清单，基线 §8 末行）：
   - **Y 真 AXI 写主**：M11 的 Y 仍是 TB 散写回 DDR 镜像（物理链化但
     无写主）；y_base 由 TB 侧加 → 描述符字段化 + 写通道 RTL 属 M12。
   - **X 平面 DDR 流式**：M11 仍组合字节口直读镜像（DDR 流式推迟至今）。
   - **PS 微操作硬件化与否**：COPY/RSCL/ADD/MAXP5/UPS2/HEADS 目前是
     TB 内解释器（微码 2178 字 + 13.3MB 镜像布局已冻结可复用）——
     硬件化 or PS 软件驱动，动工前决策入 §8。
   - PROD-16×16 OOC：150MHz 必过 / 200MHz 目标；REQUANT_UNITS 重参
     （SIM-8×8 为 3 路 → 16×16 档 ceil(256/27)=10 路）。
3. **TB/vecgen 惯例（M0–M11 成文沿用）**：寄存输出 negedge 驱动 /
   posedge+#1 采样；**状态机黄金先 step 后发射**；流握手 posedge NBA
   捕获、随机停顿寄存器 negedge 更新；每门必带真实数据回归（M0/M3/
   M4/M10/M11 均靠它抓住真 bug）；生成期护栏先于仿真；**黄金服务用
   连续 assign**；**哨兵 0xA5 合法值歧义**（双侧同值视为相等 + 写双射
   计数机器检查兜底）；**大数值 delay 表达式必须先升 64 位 time**
   （M11 run01 假失败：`#(wdt_ms*1_000_000)` 32 位溢出精确命中杀进程
   时刻；M10 的 9e8 < 2^31 从未触发）。
4. **工具链铁律（不变）**：vsim 必须 `-c -novopt`；三目/拼接进有符号
   运算必须 `$signed()`；bash 每条命令自带 `cd`；`-do "run -all;
   quit -f"` 必须引号；`-l` 会覆盖前一日志（留证先改名归档）；
   Verilog 保留字（`edge`）不可作形参；`!==`/`==` 结合紧于 `&`/`|`，
   掩码必须括号或中间变量；Windows 上 hex 发射的 numpy 标量先
   `int()` 强转；`$fopen(path,"wb")` + `$fwrite(fd,"%c",byte)` 落
   二进制。
5. 数值口径：valid drop +0.0176（G2）；test +0.0571 未参与调参仅报告；
   golden 对齐源不变（g2 run04 golden/ + regression_128frames.json）。
6. 前序状态：PS 上板 run01 CLOSED（128/128 head 位级一致）；G3 conv0 核
   golden00/02 零差异（frozen 参照，勿改）。

## 前一：G3 M10 阵列集成门全绿收批（2026-09-15 晚，M11+ 待新授权）

1. **批次状态**：M0–M9 单元门 + **M10 阵列集成门（TB_GEMM_ARRAY_PASS，
   6 层 438447 格全比对，真实层 R1/R2 逐位一致）** 全部 CLOSED。
   conv_core 已升 **V1.2**（oc 越界部分选择零扩展；M0 门 run02 回归
   11/11 同数 PASS）；yolo_gemm_array.v 为新顶层（loader/预取/requant
   平铺解码集成，门内修 3 个自身 bug，失败链全部留证）。
   入口：`4_metrics/logs/2026-09-15_yolo7020_m10_gemm_array_run01/`
   （M0 回归 `2026-09-15_yolo7020_m0_conv_core_run02/`）。
   **本批执行窗已收：M11（全网络 23 层）/M12/M13、Vivado、bitstream、
   板卡操作均未动。**
2. **下一批 = M11 全网络**（基线 §5/§9；需用户新授权再开）。起步要点：
   - 激励扩展：m10_vecgen.py 已含真实层重组链（rom_data + run04 npz
     位级复现）；M11 需按 schedule.json 23 层全展开（含 concat/route
     上采样层的数据面组织——若纯 GEMM 阵列不覆盖，需 PS 侧协作层协议，
     属架构决策，动工前对基线 §8 记录）。
   - X 平面来源：M10 门 X 服务为组合口直读 DDR 镜像（基线 §8 已记
     "X-plane comb port, DDR streaming deferred to M11"）——M11 要把
     X 喂给 xbuf/im2col 链或定义层间驻留策略。
   - W 驻留策略：M10 为每 tile DMA 装载 W bank；全网络下按层 W 体量
     评估（大 K 层 576/2304 已过，23 层连跑的带宽/时序见基线 §6 预算）。
   - Y 写回：M10 门用 TB 散写捕获；M11 需真 DMA 写通道或 PS 搬运协议。
3. **TB/vecgen 惯例（M0–M10 成文沿用）**：寄存输出 negedge 驱动 /
   posedge+#1 采样；**状态机黄金先 step 后发射**（后沿采样 ⇒ 后沿
   发射）；流握手 posedge NBA 捕获、随机停顿寄存器 negedge 更新；
   每门必带真实数据回归（M0/M3/M4/M10 均靠它抓住真 bug）；生成期护栏
   （宽度断言、键空间分离、未写地址不可读）先于仿真；**黄金服务用
   连续 assign**（M10 教训：变址数组读的 always@(*) 求值疑点一类全消）；
   **哨兵法比对注意 0xA5 合法值歧义**（双侧同值视为相等 + 写双射计数
   机器检查兜底）。
4. **工具链铁律（不变）**：vsim 必须 `-c -novopt`；三目/拼接进有符号
   运算必须 `$signed()`；bash 每条命令自带 `cd`；`-do "run -all;
   quit -f"` 必须引号；`-l` 会覆盖前一日志（留证先改名归档）；
   Verilog 保留字（`edge`）不可作形参；`!==`/`==` 结合紧于 `&`/`|`，
   掩码必须括号或中间变量。
5. 数值口径：valid drop +0.0176（G2）；test +0.0571 未参与调参仅报告；
   golden 对齐源不变（g2 run01 golden/ + regression_128frames.json）。
6. 前序状态：PS 上板 run01 CLOSED（128/128 head 位级一致）；G3 conv0 核
   golden00/02 零差异（frozen 参照，勿改）。

## 边界（沿用）

- `2_fpga/0_diaplay_test` 只读；新建内容仅限 `3_yolo_zynq`；文件不越 `E:\competition`。
- 板卡加载/重配置需用户单独授权；测试集不参与调参；数据本体不入 Git。
- main 受保护：提交走个人分支 + PR（PR #8 仍待队友审核）。

## 后续可选（单变量，按需）

- G2 裕量提升：偏置校正 / p99.9 网格 / 计划第 17 行 QAT 决策。
- HaGRID OOD 评估（COCO→YOLO bbox 转换 + user_id 划分）；方向类数据缺口见调研文档。
- PS 性能：45.3s/帧 是纯 numpy 未优化值；若需要实时性可做 NEON/定点后处理，
  但与 PL 加速主线正交，仅按需。
