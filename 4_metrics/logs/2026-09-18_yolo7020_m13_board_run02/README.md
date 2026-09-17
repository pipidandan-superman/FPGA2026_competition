# M13 板上 run02（2026-09-18 02:0x，失败保留现场——唯一一次重试已用掉）

## 结果：无判定行——验证过全空闲的 DDR 窗口上再次硬性失联

```
发射前最后核验：WINDOW_0x08000000_used_pages 0 of 3584 ALL_CLEAN（T-0 复核）
                WORD_CLEAN_CHECK 0（nohup 发射同一条 ssh 内）
02:06:06  watcher ssh FAIL #1（距发射 ~2-4 分钟）
02:06:34  FAIL #2 / 02:07:02 FAIL #3 → BOARD_UNREACHABLE_3X
~02:07    ping 2/2 丢失（100%）、ssh ConnectTimeout=20 超时（ping_ssh_dead.txt）
02:0x     COM6 串口 30 秒纯静默，无 panic/soft-lockup（com6_capture_30s.txt）
```

按用户规则 3：**重试额度已用完，停手保留现场**。板端 ~/m13/board_run02.log
与 status_poll02.log 在冻结的页缓存里，硬断电后大概率丢失（python -u 只 flush
到页缓存，未 fsync）——若用户下次上电后文件幸存，`grep -c . board_run02.log`
+ 最后几行可判定冻在镜像拷贝中还是引擎启动后。

## 本次与 run01 的差异（全部按存证 README 晨间清单执行，仅一处证据驱动偏离）

| 项 | run01 | run02 |
|---|---|---|
| DDR 段 | 0x30000000（盲写，事后查 564/3254 页在用） | **0x08000000（发射前两次扫描 0/3584 页在用）** |
| 段选依据 | deploy_m13.md 默认 | **全址空间 kpagecount 扫描**（0x01000000–0x3F000000，48 个全空 14MB 窗口取最低可用之一，避开内核 <16MB 与 CMA 256–384MB） |
| 退化段 0x38000000 | — | **证据否决**：1803/3254 页在用（55%，比 run01 段更糟），盲跑必复冻 |
| PL 下载+身份读 | PASS | PASS（断电后重载 fpgamgr bin，STATE=operating，CSR_ID=0x594F4C31/VER=0x00020000） |
| 伴随观测 | 无 | **STATUS 轮询器**（每 2s 读 ldone_cnt，冻结时计数停在失败层） |
| drop_caches | 是 | 是（发射同链执行） |

## 决定性结论：DDR 段占用假设死亡

同一程序、同一驱动、同一夜、两块"占用状态天差地别"的物理段
（564 页在用 vs 0 页在用）→ **同样的无输出硬冻结**。
根因不在"踩没踩活页"。/proc/cmdline 已证 CMA=128M@0x10000000 与两段无交集。

## 修正后的根因排序（供用户决策，均未擅动）

1. **/dev/mem RAM 别名映射的写机制本身**（当前首要嫌疑）：
   pl_m11.py 用 `O_RDWR|O_SYNC + MAP_SHARED` mmap 物理 RAM 再整段赋值 13.3MB。
   run01 日志证据：冻点在 [stim] 之后、[ddr] mirror 完成打印之前 =
   **纯 CPU 写 RAM 阶段，引擎尚未启动**。若该 mmap 在本内核
   （5.15.19-xilinx，PetaLinux 2022.1）把 RAM 映成 Device/strongly-ordered，
   非对齐 memcpy 字节store 在 Cortex-A9 上 UNPREDICTED，可致总线级静默挂死
   ——与"无 panic 静默冻结、串口无声"完全吻合。
   run02 冻点待板端日志确认（若也是只到 [stim] 即坐实）。
2. **HP0/HP1 互连协议挂死**（无法排除 run02）：若 run02 已打出 [ddr]/[conv 0]
   则嫌疑升级至此；需 JTAG/ILA 级诊断。
3. **FCLK0 实际频率≠60MHz**（boot 遗留频率，引擎时序违约→首拍 HP 违约）：
   下次上电可零成本核验 `/sys/kernel/debug/clk/clk_summary` 的 fclk0 rate
   与 PL 侧 CSR 读稳定性（两 run 身份读均绿=GP0 通，但频率未证）。

## 下一步候选（全部待授权，本次一律未动）

- **A 路（推荐）：弃用 /dev/mem 写 RAM——PYNQ xlnk/CMA 分配缓冲**，
  pl_m11.py 改为 `pynq.buffer`/xlnk 分配（物理连续、内核登记、零碰撞），
  拿物理地址作 ddr_base，/dev/mem 只留 CSR 读写。这是 PYNQ 官方路径，
  根除嫌疑 1；若再冻则嫌疑锁死 2/3。
- B 路：驱动写法改 4 字节对齐循环写（诊断性区分 Device-memory 对齐假说）。
- C 路：JTAG/XSCT 挂死现场读 CPU PC（XSDB `targets; mrd` 级），确认冻在
  copy_to_user 还是驱动 doorbell。
- 前置零成本检查（下次上电立即做）：clk_summary 查 fclk0；两份板端日志
  幸存性检查。

## 现场保留清单

- 板：保持冻结态未再触碰（无第二次重载/重启/任何写操作）；
  上电时机的选择权在用户。
- PC 侧证据：本目录 4 件（README/com6/wacher/ping_ssh）+
  run01 目录不变；板侧脚本新增 poll_status02.py（已 scp，
  本地留档 2_fpga/3_yolo_zynq/pynq/poll_status02.py）+
  watch_run02.sh（本地）。
- 段位扫描原始数据：会话记录（48 窗口清单 + 4 段对照表），
  关键数字已全部写入本 README 与会话日志 §8。

## 判据行（本次未达成，目标不变）

`PL_M11_PASS convs=63 psops=65 compared=3553900 nerr=0 head_bytes=149100
 head_sha256=9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad`
