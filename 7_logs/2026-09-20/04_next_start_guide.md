# 2026-09-20 下次启动指南（run26 收官后）

## 第一步

1. 读本目录 `05_run26_closeout.md`（run26 PASS 全叙事）与证据
   `4_metrics/logs/2026-09-19_yolo_gemm_b3_run26_bridge_contract/README.md`；
2. 核对 git：用户分支 `codex/full/pipidandan-superman` 应含 run26 收官批；
3. 核对磁盘：`pynq/b3_conv0_packer.py` + 证据目录 mirror/golden_y/meta
   三件套（SHA 见 03_validation_summary）。

## 当前态（勿重做）

- **run26 PASS**（桥 RTL V1.2 + TB + packer + 静态 CSR 检查全闭环）；
- run01-run25 基线不变；主树 635 条未提交记录与 4 个未跟踪审计文本不碰。

## 下一步（按用户睡前边界：run27 → run28 → 停）

1. **run27 G4**：新证据目录 `4_metrics/logs/2026-09-20_yolo_gemm_b3_run27_g4/`；
   TB 数据源=run26 证据目录三件套；单块 0/1/3198/3199 + 全量 3200 块 golden
   逐字节（y slot §7.2 reorder）+ accepted beats 259,200 + 随机双 tready +
   4KiB crossing + 双跑 SHA；负向 row_valid/n_mask 拒绝；
2. **run28**：批处理前查 Vivado GUI 进程（开着=决策点暂停）；BD 删回环接
   MM2S/S2MM（例化从 .veo 逐端口核对）；bit/HWH/静态端口检索/WNS/WHS/
   资源口径；
3. **run28 收口即停**：不开始 run29；任何板卡动作（上电/下载/板测）一律等
   用户回来并确认"已上电"。

## 刚开始时不要做

- 不要写 CSR 0x40（桥模式只读镜像，写得 SLVERR——见 csr_static_check.md B-②）；
- 不要在 DMA 传输中 soft_rst（挂起 tlast；§11 七步恢复正典）；
- 不要凭记忆写寄存器模型/端口名（.veo 逐端口核对；权威源转录）；
- 不推 main；git 只走命名文件 + add -f 申报。

## 成功标准

- run27 G4 全绿 + 证据齐套 + git；
- run28 bit/HWH+静态检索收口 + 证据齐套 + git；然后停，等用户。
