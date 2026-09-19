# 13. P0-B 板级基线验证 run02 收官（P0 整体完成）

## 结论

用户再次上电后，run01 的唯一阻塞（板卡在线性）消除，P0-B 一轮全门通过：
**P0-B PASS ⇒ P0 整体收官**（P0-A 离线冻结 + P0-B 板级验证）。
证据：`4_metrics/logs/2026-09-19_yolov8_p0_board_validation_run02/`。

## 门序（全部 PASS）

1. **L 在线性**：ping 0% 丢、ARP 动态 `46-2e-60-16-ac-3f`、SSH 登录成功
   （run01 为 TIMEOUT，本次同方法复测即恢复——上次为链路/启动态问题，非方法论缺陷）。
2. **I 身份**：hostname `pynq`、5.15.19-xilinx-v2022.1 armv7l、新 boot_id
   `1daced01-…`（板钟 2022-10-22 停走属已知，用 boot_id 不用墙钟）。
3. **O 所有权（空洞，放行）**：ees331-camera failed 终态（ExecMainStatus=1）、
   camera.py 无进程、/dev/dri 无持有者、dmesg 呈 `locked ref=1 → unlocked ref=0 →
   client exits pid(595)` 正典终态链。
4. **基线 Overlay（复用 run25 驱动，其自含 CK 门）**：三件套上传 sha 双侧一致 →
   CK1 HWH 合同（4 IP/三地址）→ CK2-4 download+operating+zocl 锁 1→2（新鲜 UUID）→
   CK5 牺牲首读+三重身份（GEMM_ID 0x20260919 / CSR_ID 0x594F4C32 / VER 0x0300）→
   CK_F 真 100.000 MHz（raw 0x00200500，verify-only）。
5. **B1 smoke**：S1/S2/S3+soft_rst 全过，y_count 128/32/128、幻影槽 25、
   STATUS 0x28/0x38——与 run23/24/25 逐位相同。
6. **B2 smoke**：DB1-DB7 全过（尺寸扫/连发×3/复位回 0x10002/恢复+S1 重跑），
   总账 wop=3462 rb_ok=416 rb_bad=0 db_ok=9 db_bad=0 → `BOARD_FREQ100_PASS`。
7. **R 恢复性/终态**：驱动进程退出（zocl client 释放）后 `/dev/mem` 三读全中
   （`P0B_POSTCHECK_PASS`，本轮新增 postcheck_p0b.py）；fpga0=operating、getty active、
   相机服务保持终态未触碰、ping 0%。

## 板上终态

**P0 基线（100 MHz GEMM+CSR+DMA 三从机）挂载**，板上目录 `~/p0b_run02/`。
相机服务按 ees331 画像不是恢复目标。

## 与 run01 的差异说明

run01 fail-closed 正确：当时只做只读探测、零写入、判定 BLOCKED 而非板卡故障定论。
本轮同一方法学下链路恢复，证明 run01 判定无谎报。B1/B2 smoke 属 P0-B 对既有
run23/24/25 结论在新启动上的复核（同种子逐位相同纪律），不是重做仿真门。

## 下一步

P1/B3：真实 Conv0 的 DMA→GEMM→DDR→G0 golden。B3 桥接合同 4 决策点仍待用户授权
（① MM2S 流→GEMM 装载口握手合同；② B2 回环保留/移除；③ y 回写 B3 vs B4，建议 B4；
④ 频率门已闭）。板上动作用户在场。

## Git

本批 commit `d0a51a8`（run02 证据 5 件 + 13 号日志 + 指南/三件套）。勘误：提交时
以为需"补推上批未达远端的 5de8ec7"，实际推送输出 `5de8ec7..d0a51a8` 证明远端
本已在 `5de8ec7`——上批 443 一次性 URL 推送已达远端，只是 raw-URL 推送不更新
本地 origin 引用造成 ahead-1 陈旧引用假象。
