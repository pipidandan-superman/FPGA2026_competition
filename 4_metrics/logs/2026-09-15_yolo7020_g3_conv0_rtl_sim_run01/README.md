# 2026-09-15 yolo7020 G3 conv0 RTL 仿真门（run01）

## 目标（计划 §10.3 G3 第一子步）
`rtl/yolo_conv0_core.sv`（首层 conv，1 MAC/拍数值优先版）在 ModelSim 中与
golden 激励逐字节零差异 —— G3 单模块 RTL vs golden 位级一致的首次闭环。

## 结果

| 用例 | 范围 | 结果 |
|---|---|---|
| 冒烟 golden00 | 500/409600 像素 | TB_CONV0_PASS（修复 2 处符号性 bug 后） |
| **全量 golden00** | 409600/409600 | **TB_CONV0_PASS** |
| **全量 golden02** | 409600/409600 | **TB_CONV0_PASS**（交叉样本） |

激励来自 `2_fpga/3_yolo_zynq/sim/stim/conv0_golden{00,02}/`
（golden_extract.py 三方自检：提取文件 ↔ runtime._conv ↔ golden npz）。

## 修复过程（按时间序）

1. **vsim 挂死（0 CPU 停在 banner / "Design is being optimized..."）**
   - 排除：输出管道缓冲、stdin 阻塞（`< /dev/null` 无效）、license（本地
     INCREMENT 文件，空壳 vsim 0.77s 启动正常）、work 库损坏（重建无效）。
   - hosts 文件为空 + 主机名仅解析到 IPv6 链路本地地址 —— 已按 Mentor 标准做法
     把机器名钉到 127.0.0.1（备份 `hosts.bak_20260915`），但未解决问题。
   - **根因：10.1c 设计优化阶段在此机器上挂死。对照历史成功记录
     （4_metrics/logs/2026-09-05 之后的 transcript），有效规避是 `-novopt`。**
   - 结论：本项目所有 vsim 命令一律带 `-novopt`（vlog 不受影响）。

2. **sum_b 符号性 bug（冒烟 421/500 错）**
   - `sum_b = {bias_rdata[31], bias_rdata} + acc;` —— 拼接是无符号的，把表达式
     毒化为无符号：acc=−32112 被零扩展，且下游 `sum_b * m_rdata` 变无符号乘
     （实测 prod=7.904e18 与无符号乘积精确吻合）。
   - 修复：`$signed({...}) + acc`。错误 421→163。

3. **pad 常数符号性 bug（剩 163/500 错）**
   - 逐 tap 打印对照 Python 真值定位：k/ih/iw/x_in/w 全对，仅 pad 项
     期望 (−128)×(−30)=+3840、DUT 得 −3840 —— 三目 `x_in ? x_rdata : -8'sd128`
     结果被按无符号零扩展成 +128。
   - 修复：`$signed(x_in ? x_rdata : -8'sd128) * w_rdata`。冒烟 500/500 PASS。

   教训（对后续所有 conv 模块适用）：10.1c 下**凡三目/拼接参与有符号运算，
   一律显式 `$signed()` 包裹**；不看值推断符号性。

4. TB 改造：PARTIAL 时写满 n_cmp 即比对并 `$finish`（原版要跑满全图才停）；
   看门狗 80ms→200ms（全量 409600×29 拍 ≈ 119ms）。

## 工件
- RTL：`2_fpga/3_yolo_zynq/rtl/yolo_conv0_core.sv`（含上述 2 处修复）
- TB：`2_fpga/3_yolo_zynq/sim/tb_yolo_conv0.sv`
- 证据日志：本目录 `console_extract.txt`（关键 PASS/FAIL 行 + 根因证据）
- 仿真库：`2_fpga/3_yolo_zynq/sim/msim/work`

## 下一步（G3 继续，计划 §10.3）
1. 合成测试矩阵：K=27 与最大 K=2304、非 tile 整数倍、全零/极值/随机激励
2. 并行/流水化架构（数值不变式：整数累加次序无关）
3. OOC 综合（时序/资源）
4. B1：单 conv 上板（需用户单独授权）

## 原始 transcript（2026-09-15 晚补录，未改动）

本目录建立时原始 console 输出留在 `2_fpga/3_yolo_zynq/sim/msim/` 未随目录
归档，现按四件套规则补录（19 件，逐字节复制、不改名不裁剪，sha256 见
`transcript_sha256.txt`）：

- 编译/启动探针：`vlog_tb.log`、`vlog_all.log`、`vlog_fix1.log`、
  `vsim_startup_test.log`（vsim 挂死排查）、`iso_dut.log`、`iso_dut_out.log`
- 冒烟链：`smoke.log`（421/500 错）、`smoke2.log`（163/500 错）、
  `smoke3.log`（500/500 PASS）、`smoke4.log` + 各 `*_stdout.log`
- 逐 tap 定位：`dbg1.log`–`dbg4.log`（pad 常数符号性 bug 证据）
- 门运行：`full00.log`、`full02.log`（各 409600/409600 PASS）

激励为 golden 派生确定性数据（无随机种子），三方自检见
`sim/golden_extract.py`；`console_extract.txt` 维持原状。
