# YOLOv8 P0-B 板级基线验证 run02 — P0-B PASS

## 结果

**P0-B 全门通过（run02 一轮完成），P0 整体就此收官**（P0-A 离线冻结 + P0-B 板级验证）。
用户确认上电后，run01 的阻塞点（板卡在线性）已消除：ping 0% 丢、ARP 动态表项
`46-2e-60-16-ac-3f`、SSH 身份可读。全程按 `zynq-pynq-overlay-workflow` 分级门执行。

## 门与结果

| 门 | 内容 | 结果 |
|---|---|---|
| L 在线性 | ping/ARP/SSH（专用网卡 192.168.240.2→192.168.240.10） | PASS |
| I 身份 | `pynq` / Linux 5.15.19-xilinx-v2022.1 armv7l / boot_id `1daced01-23ab-459b-88e2-16f583698faf`（新启动） | PASS |
| O 所有权 | camera 服务 failed 终态（ExecMainStatus=1）、camera.py 进程亡、/dev/dri 无持有者、dmesg `locked ref=1 → unlocked ref=0 → client exits pid(595)` | 空洞所有权，放行 |
| CK1-CK5 基线 Overlay 身份 | 驱动自含：ip_dict 4 IP、地址 GEMM 0x43C00000/CSR 0x43C10000/DMA 0x40400000；download 返回 + fpga0=operating + zocl 锁计数 1→2（新鲜 UUID `9eead4e7…`）；牺牲首读 OK；GEMM_ID 0x20260919 / CSR_ID 0x594F4C32 / CSR_VER 0x0300 | PASS |
| CK_F 频率 | raw FPGA0_CLK_CTRL=0x00200500（verify-only 零 SLCR 写）；IO PLL FBDIV=30→1000 MHz，÷5÷2 = **真 100.000 MHz**；pynq 报告 150.0（1.5× 偏置，仅记录） | PASS |
| B1 smoke（GEMM） | S1 rb=128 bad=0 y_count=128 STATUS=0x28；S2 rb+=32 幻影槽保旧 25 y_count=32；S3 rb+=128 y_count=128 STATUS=0x38；soft_rst STATUS=0 y_count=0 ID 保持 | PASS，与 run23/24/25 逐位相同 |
| B2 smoke（DMA） | DB1 复位态 0x1/0x1；DB3 CMA 16384B（src 0x10048000/dst 0x1004C000）；DB4 尺寸扫 137/1/1000/8192 全 cmp=OK（DMASR 0x1002）；DB5 连发×3；DB6 停止/复位 DMACR 回 0x10002；DB7 恢复 256B + S1 重跑 rb=416 | PASS，与 run24/25 逐位相同 |
| R 恢复性/终态 | 驱动进程退出（zocl client 释放 pid 1357）后 `/dev/mem` 三读全中（GEMM_ID/CSR_ID/0x00200500）`P0B_POSTCHECK_PASS`；fpga0=operating；getty active；camera 服务保持终态未触碰；ping 0% 丢 | PASS |

总账：`wop=3462 rop=863 rb_ok=416 rb_bad=0 db_ok=9 db_bad=0`，`BOARD_FREQ100_PASS`，
DRIVER_EXIT=0——与 run25 attempt-3 完全一致（同种子 ⇒ 逐位相同期望纪律再获验证）。

## 板上终态

**P0 基线 = 100 MHz GEMM+CSR+DMA 三从机 overlay 挂载**（bit sha `0e0ae185…`）。
相机服务不是恢复目标（ees331 画像正典）；按画像"板上基线=最后一次授权测试所挂"，本次
授权测试即挂载 P0 基线。板上目录 `~/p0b_run02/`（bit/hwh/驱动/后检脚本，sha 双侧核对一致）。

## 工件（上传前后 sha256 双侧一致）

| 文件 | SHA-256 |
|---|---|
| display_test_wrapper.bit | `0E0AE18571394CF017FCD145115B87F01966865D18D12686B1CFC032A7020BA0` |
| display_test_wrapper.hwh | `8016AC63ECBE544D82277EBCCEBAD203868101A854B3B55F4A0C5D500C28019F` |
| pl_freq100_run25.py（作 P0-B 驱动复用） | `F151E4898C0FD0A2A5A4293915E4A185F93E1AEC4F9472B6C9346EBA357D990B` |
| postcheck_p0b.py（本轮新增后检） | `8C7678CC979562C37CF86BF05A17CDEC0E33D87DD83415A95E1CB473CAA3C3EC` |

## 证据文件

- `raw_liveness_probe.txt` — 全程原始转录（在线性→身份→所有权→上传→驱动→后检）
- `board_run02.log` — 驱动 + 后检输出摘录
- `board_validation_manifest.json` — 结构化状态

## 下一步

P0 收官 ⇒ 进入 P1/B3：真实 Conv0 的 DMA→GEMM→DDR→G0 golden（B3 合同冻结与桥接
设计仍待用户授权，4 个决策点见 HANDOFF/启动指南）。

## 本会话独立复核说明

本 run02 证据在本会话开始前已存在并已完成执行；本会话没有再次下载 Overlay、
没有重启服务，也没有重跑 GEMM/DMA。仅通过 SSH 做只读复核：板端 ping PC
2/2、`fpga0=operating`、`ees331-camera=failed`、`serial-getty=active`，并再次
执行无写入的 `postcheck_p0b.py`，读回 GEMM_ID/CSR_ID/FPGA0_CLK_CTRL 与
`P0B_POSTCHECK_PASS` 一致。因此当前板上状态沿用 run02 的 Claude 执行结果，没有
发生第二次 Overlay 冲突。
