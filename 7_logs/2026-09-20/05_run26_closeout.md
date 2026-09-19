# run26 收官日志（B3 桥合同仿真门 + canonical packer + 静态 CSR 检查）

2026-09-20 凌晨　｜　判定：**run26 PASS**　｜　证据目录：
`E:\competition\4_metrics\logs\2026-09-19_yolo_gemm_b3_run26_bridge_contract\`

## 结论一句话

合同 v1.1 §14 定义的 run26 门四要件全闭环：桥 RTL V1.2 五项修复（R1-R5）
S1-S7 全绿（1664 checks / 0 errors）、canonical packer 三件套产出且 golden y
与 G0 逐位一致、静态 CSR/地址检查 23 行全 PASS、失败证据全留档。

## 本轮时间线（承 14 号暂停日志续跑）

1. **R4 落 RTL**：写译码 rst 分支补全全部配置寄存器清零（top.v 387-400）；
2. **R5 修复**：build_log3 终局守恒错（`stream ends mid-tile 128B`）暴露
   tlast 检查空真 → build_log4 加 EES_TL 诊断监视器取证：13 个 tile_done
   全部落在末 y 拍 ≥2 拍后、wv_d=wv_r=wtl_r=0、ypk_cnt=0——V1.1 两个并入窗
   结构性漏标，全 sim 零 tlast 弹出 → **三路合并修复**（呈现拍脉冲并路 +
   tl_late_pos 位置捕获回补；加固=覆盖前旧标记回写 yfifo_tl 向量）→
   build_log5（11×pop_tlast）→ build_log6 终证（12×pop_tlast、errors=0）；
3. **TB 三处**：S5b ld_pend_err 双位正控制+err_clr；S6b/c/d 延后/缺失/超长
   变体；S7 §11 七步正典恢复（含 loaded 清零正控制+重装载 LDSTAT 确认）；
4. **packer**（`pynq/b3_conv0_packer.py`）：数据链全权威源核实后编码，
   B3_CONV0_PACKER PASS；镜像 `be4d56f0…`、golden_y `eeb15bf9…`（vs G0 OK）、
   pad 5754 三方吻合、边界 tile 抽检全对（顶行全 0x80/左列恰 c=0/W 跨 g 异
   X 跨 g 同）；
5. **静态检查**：`csr_static_check.md`——§9↔V1.2 逐项 PASS、复位三分规则、
   §5↔packer 互证；三条注记进 run29 驱动纪律（**不写 0x40**、PCTL bit8、
   RO 写 SLVERR）。

## 关键语义沉淀（后续 run 必须遵守）

- **soft_rst 清 bank loaded**（§11 恢复正典七步，驱动合同级）；
- **R5 三路合并**为 V1.2 呈现逻辑正典，G4 随机反压下由 tl_late 回写加固
  保证多 tile 迟到标记不丢；
- LDLEN 0x40 只读镜像；tlast 短流缺失硬件不可检（BFM/BTT 判）。

## git

命名文件提交用户分支 `codex/full/pipidandan-superman`
（worktree `E:/competition_worktrees/FPGA2026_competition/pipidandan-superman`）：
RTL V1.2、TB、packer、run26 证据四件+静态检查+README/STATUS、7_logs
2026-09-20 四件套+本日志；*.bin 按纪律 `git add -f` 逐件申报 sha/size。
