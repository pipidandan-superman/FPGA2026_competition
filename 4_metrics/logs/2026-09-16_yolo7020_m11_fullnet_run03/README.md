# M11 门 run03 —— 全网 63 conv 回归（阵列 V1.2a Y 真 AXI 写主承接，2026-09-16）

## 结果：TB_FULLNET_PASS + M11_HEADCHK_PASS

```
TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900 head_bytes=149100 ldone=63 adone=1
M11_HEADCHK_PASS sha256=9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad bytes=149100
```

**与 run02（阵列 V1.0 观测口时代）七项计数逐项同数**（convs/psops/compared/
dut_wr/head_bytes/ldone/adone 全同）；head sha256 == run04 frame0 ==
run02 headcheck。63 conv 全部 `acc_err=0`（transcript 中非零 acc_err 计数=0）。
激励零漂移：stim 6 hex + stim_manifest + m11_vecgen.py + m11_headcheck.py
与 run01 sha256 记录程序化比对**全 SAME**（见 stim_sha256.txt 尾注）。
本门是 M12 A1 第四件：V1.0→V1.2a 阵列换装（Y 观测口→真 AXI4 写主）后的
全网级回归，证明 Y 写路径重构对全部 63 conv + 65 PS 微操作数据面逐位无扰动。

## 本跑改动面（相对 run02）

- **RTL（数值路径改动，§5 全链重跑义务已履行：M8 run03 + M9b run03 +
  M10 run03 + 本门 + CSR/engine run01）**：yolo_gemm_array V1.2/V1.2a
  （Y 行段化器 + u_dma_wr V1.2 + dsc_ybase + ldone/adone 排空门控 +
  行首准入在途竞态修复）、yolo_ctrl V1.2（S_RQ rq_rdy 等待态）、
  yolo_dma_wr V1.2（非对齐起始）。
- **TB V1.1（tb_yolo_fullnet.v）**：Y 观测口比较器换 AXI4 写从 BFM 散写
  ——按物理地址进 word 打包镜像；程序字 24 = y_base（dsc_ybase 源）。
  激励/黄金/解释器逻辑零改动（m11_vecgen.py 与 run01 逐位 SAME）。
- 激励：stim/m11 全套沿用（vecgen 未重跑）。

## smoke 失败链（m11_run03_smoke.log，留证）

`TB_FULLNET_FAIL err=554495 ... dut_wr=614400(exp 614400) convs=2(exp 2)
first=(c0,i0)`，首错 conv0 i=0 dut=226 gold=87，conv0 acc_err=357407
（≈51200×7）、conv1 acc_err=554495。根因：**TB 散写 BFM 的 word 合并用
逐 lane NBA**——一拍内 8 个 strobe lane 对同一 8B 字各发一次非阻塞赋值，
互踩只留末 lane 值，字内前 7 字节变陈旧；DUT 侧逐字节全对（计数/双射/
first-diff 均指向镜像侧）。修复：**所有 strobe 拍合并成单 NBA**（按 lane
掩码拼 64 位后一次赋值）。smoke2 两 conv 全零误差：
`TB_FULLNET_SMOKE convs=2 compared=614400 dut_wr=614400 ldone=2 adone=1`。
教训：**验证侧镜像模型的写合并必须与被测写口的原子性同一粒度**——
逐 lane 时序赋值在"一拍多 lane 落同一字"场景必错。

## 命令与环境

```
cd E:\competition\2_fpga\3_yolo_zynq\sim\msim
# （前置）vlog 12 RTL + tb_yolo_fullnet.v 入 work_arr（阵列 V1.2a 全链）
# smoke 失败链: +MAXCONV=2 -l m11_run03_smoke.log ；修复后 smoke2 同命令
#   -l m11_run03_smoke2.log
vsim +STIM=../stim/m11 +WDT_MS=3600000 -do {run -all; quit -f} ^
    -l sim_m11_full_run03.log -c -novopt work_arr.tb_yolo_fullnet
cd ..\..   # sim
python m11_headcheck.py msim/head_dump.bin
# 期望: TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
#       head_bytes=149100 ldone=63 adone=1
#       M11_HEADCHK_PASS sha256=9ce70525...（== run04 frame0）
```

主机 HC-202510241838（Windows 11 企业版）；ModelSim SE-64 10.1c
（`-c -novopt` 铁律）。RTL/TB/激励 sha256 见 stim_sha256.txt（21 项绝对
路径：7 stim + 2 脚本 + 11 RTL + TB；8 项激励侧与 run01 记录零失配）。

## 证据清单

1. 本 README.md
2. console_extract.txt（PASS/SMOKE/FAIL token 摘录）
3. sim_m11_full_run03.log（通过 transcript 原件）+ m11_run03_smoke.log
   （失败链原件）+ m11_run03_smoke2.log（烟测通过原件）
4. head_dump.bin（149,100B 本跑落盘）+ headcheck.out（本目录内复跑输出）
5. stim_manifest.json（沿用 run01 原件——激励零改动）+ stim_sha256.txt

## 结论

M11 全网门在阵列 V1.2a（Y 真 AXI 写主）上回归通过，七项计数与 run02
同一、head sha 命中 run04 权威。**M12 A1 五件到此全绿**：M8 run03 ✓ +
M9b run03 ✓ + M10 run03 ✓ + M11 run03 ✓（本门）+ CSR/engine run01 ✓
→ A1 收口，B 段（OOC 综合）待用户另行确认。
