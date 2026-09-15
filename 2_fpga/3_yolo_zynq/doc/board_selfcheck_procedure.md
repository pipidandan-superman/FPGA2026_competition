# 板端 PS 自检规程（PS_SELFCHECK_ONBOARD）— 2026-09-15

首次把 G2 部署包 + PS numpy 运行时放到真实 ZYNQ PS（ARM Cortex-A9）上运行。
**不加载任何位流、不动 PL、不装服务、不改 SD/系统文件**；只读运行 + 独立
目录落证据。失败回退 = 删除板上 `/home/xilinx/yolo_selfcheck/`，即回原状态。

## 连接参数（源：8_tools/EES331_PL_Reloader_v1.4/README.md，用户确认未变动）

| 项 | 值 |
| --- | --- |
| 板地址 | `192.168.240.10`（SSH 端口 22） |
| 用户 / 密码 | `xilinx` / `xilinx` |
| PC 有线网卡 | 必须是 `192.168.240.2/24`（与既有工具前置检查一致） |
| 板上系统 | SD 启动的 PYNQ/Linux（镜像 ees331_pynq_sd_20260911_222654） |
| 原服务 | `ees331-camera`（HDMI/UDP 视频）照常运行，与本自检零交互 |

## 交付物（本次新增）

| 文件 | 位置 | 作用 |
| --- | --- | --- |
| `pynq/board_pack_selfcheck.py` | PC | 打包板端输入（128 帧 letterbox 画布 npz + 期望哈希）并本地预验；已跑：128/128 PASS，inputs.npz sha256 `653ca86641bc4f79…` |
| `pynq/board_selfcheck.py` | 板 | 板端运行器：传输完整性 → 包哈希 → 逐帧推理+解码比对 → 证据 JSON。numpy+stdlib，零 cv2/torch，Py3.6+ |
| `pynq/board_pack/` | PC→板 | inputs.npz(14MB) + expected.json + pack_manifest.json |
| `pynq/pc_askpass.cmd` | PC | SSH 密码经 `EES331_SSH_PW` 环境变量传递，不落盘 |

判分口径 = PS_RUNTIME_OFFLINE_PASS 同款：head = 原始 INT8 头字节 sha256
（硬门）；box = float64 解码精确相等。ARM/x86 libm 差异若出现，表现为
head 全过而 box 个别不等 → `PS_SELFCHECK_ONBOARD_HEAD_ONLY`，单独分析，
不静默放行。

## PC 侧命令序列（上板执行时逐条运行；scp/ssh 由 Git Bash 驱动，环境变量内联单次生效）

```bash
# 每条 ssh/scp 都带同一前缀（密码经环境变量→askpass，不进命令行/日志）：
#   EES331_SSH_PW=xilinx SSH_ASKPASS=<abs>/pc_askpass.cmd SSH_ASKPASS_REQUIRE=force
#   ssh/scp -o StrictHostKeyChecking=accept-new -o NumberOfPasswordPrompts=1 ...

# 0) 前置：PC 网卡 192.168.240.2/24；板 22 端口可达（PowerShell: Test-NetConnection）

# 1) 上传（部署目录独立，不覆盖板上任何既有文件）
scp pynq/{yolo_pkg,yolo_runtime,yolo_decode,intarith,board_selfcheck}.py xilinx@192.168.240.10:/home/xilinx/yolo_selfcheck/
scp -r 2_fpga/3_yolo_zynq/rom_data  xilinx@192.168.240.10:/home/xilinx/yolo_selfcheck/
scp -r pynq/board_pack              xilinx@192.168.240.10:/home/xilinx/yolo_selfcheck/

# 2) 板端先跑子集（默认前 8 帧；ARM 预计每帧数十秒级）
ssh xilinx@192.168.240.10 "cd ~/yolo_selfcheck && python3 board_selfcheck.py --frames 8"

# 3) 子集 PASS 后跑全量（--frames 0 = 128 帧）
ssh xilinx@192.168.240.10 "cd ~/yolo_selfcheck && python3 board_selfcheck.py --frames 0"

# 4) 取回证据 → 4_metrics/logs/<date>_yolo7020_ps_onboard_run01/
scp -r xilinx@192.168.240.10:/home/xilinx/yolo_selfcheck/selfcheck_result <本地证据目录>
```

## 边界与纪律

- 板卡上电/加载由用户执行与授权；本规程不改 BOOT.BIN、不触碰
  `0_diaplay_test` 位流与 `ees331_camera` 目录。
- 板上仅新增 `/home/xilinx/yolo_selfcheck/`；证据 JSON 含 python/numpy/
  cpuinfo/meminfo/boot_id 环境记录与逐帧 head/box/耗时。
- 板端 numpy 若为 1.x：`rne_shift` 已含 `s=int(s)` 修复，1.x/2.x 语义一致；
  版本随证据记录，不假设。
- 若 `--frames 8` 出现 head 不符：优先怀疑传输/包，看 [1][2] 两段哈希；
  [1][2] 全过而 head 不符才是真算术差异，逐帧 JSON 定位首错帧后停，不重试掩盖。
