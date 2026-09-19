# M13 板上首跑 run01（2026-09-18 深夜，失败保留现场）

## 结果：无判定行——首层启动后板卡硬性失联（网络+串口全无响应）

```
board_run.log 全部输出（仅 1 行）：
[stim] prog=2178w lut=16128B mirror=13320008B n_conv=63
之后静默 ~10 分钟 → ssh connect timeout → ping 0/3（ping_dead_3pkts.txt）
→ COM6 串口 8 秒静默（无 panic 输出）
```

按用户规则第 3 条停止重试：恢复需物理断电（用户晨间操作），
届时按 deploy_m13.md 退化路径做**唯一一次**重试（--ddr-base 0x38000000）。

## 已成功完成的阶段（分段验证纪律）

| 阶段 | 结果 |
|---|---|
| 传送+哈希 | 9 件全对（pl_m11.py f67f0c5efafdd8f5 / bit cde1a4a077bf7830 / ddr.bin 3e29738cd56b6550 …） |
| PL 占用审计 | ees331-camera 服务 failed（非 running）、无 /dev/video /dev/uio 占用、boot_id 3297febf-… 记录 |
| 比特流下载 | **格式关**：fpga_manager 只认逐 32 位字字节交换 .bin（内核 zynq-fpga.c has_sync 要求 dword 对齐 66 55 99 aa）。.bit 与 SMAPx32 均被拒；手工转换 `yolo_a2_fpgamgr.bin`（sha 51a1927adcd4df18，Python `>u4→<u4`）通过 |
| 身份读 | `CSR_ID=0x594F4C31`（YOLO1）`CSR_VER=0x00020000`（V1.2）STATE=operating —— **PL 活、GP0 AXI 应答正常** |
| 全程序执行 | stim 装载 OK → conv0 START 后静默 → 板失联 |

## 失败分析（候选根因，按可能性排序）

1. **DDR carve-out 0x30000000 与内核/CMA 内存冲突**（首要嫌疑）：
   驱动先把 13.3MB 镜像直写 0x30000000 起，引擎再经 HP0/HP1 读写同区。
   若该物理段被内核页表/CMA（camera 服务遗留 VDMA 缓冲即 CMA 分配）占用，
   直写 = 踩内存 → 内核整体冻结（与"无 panic 静默死亡"吻合）。
   退化路径（deploy_m13.md 既定）：--ddr-base 0x38000000 重试一次。
2. 引擎 HP 通路在真硬件上协议级挂死拖垮互连（TB BFM 宽松、PS7 严格）：
   若晨间换段重试仍同点位死亡，此嫌疑升级；届时需 JTAG/ILA 级诊断。
3. 注：CSR/GP0 通路已被身份读证明正常，故障面收敛在 HP×DDR 数据面。

## 晨间重试清单（待用户断电重启板后，一次机会）

板上文件已就位（~/m13/：驱动两件+stim 三 bin+n_*.hex+yolo_a2_fpgamgr.bin
+board_load_m13.sh/board_run_m13.sh）。流程：
1. 用户断电重启板，等 ~1 分钟起来；
2. ping 通后：`printf '%s\n' "$EES331_SSH_PW" | ssh … "sudo -S -p '' sh -c 'cp ~/m13/yolo_a2_fpgamgr.bin /lib/firmware/ && echo 0 > /sys/class/fpga_manager/fpga0/flags && echo yolo_a2_fpgamgr.bin > /sys/class/fpga_manager/fpga0/firmware'"`（重载 PL）；
3. 跑：`sudo /usr/bin/python3 -u /home/xilinx/m13/pl_m11.py --stim /home/xilinx/m13/m11 --ddr-base 0x38000000`（board_run_m13.sh 内地址需同步改，或直接命令行）；
4. 成功判据：`PL_M11_PASS convs=63 psops=65 compared=3553900 nerr=0 head_bytes=149100 head_sha256=9ce70525fc1732cd…`。

## 板端环境事实（本轮钉死）

- PetaLinux 2022.1（PYNQ 3.0.1 镜像，kernel 5.15.19-xilinx-v2022.1，armv7l）
- python3=系统 1.21.5 可用；PYNQ venv 在 /usr/local/share/pynq-venv（其
  Bitstream 类报 "No Devices Found"，设备服务器路径不可用，勿走）
- sudo 需密码（stdin 喂）；devmem 不存在（用 python /dev/mem 替代）
- 无 fpgautil；下载唯一路径=fpga_manager+字节交换 .bin
- ees331-camera.service enabled 但当前 boot failed（journal 末尾心跳正常，
  板时钟 stale Oct 22，以 boot_id 为准）；恢复原业务=systemctl restart
  ees331-camera（自会重载其 overlay，本次测试未动其任何文件）
