# P0 — PPU ABI 事实核验门 run01

- 日期：2026-09-18（深夜，图算子并行线首跑）
- 脚本：`ppu_abi_factcheck.py`（副本在本目录；源件 `2_fpga/parallel_task/3_oracle/`）
- 输入：rom_data 四件套 + schedule.json + run04 golden_index/golden npz（只读）
  + `rtl/ps_axi_pl/yolo_csr_pkg.sv`（只读）
- 命令：`python ppu_abi_factcheck.py <本目录>`
- 结果：**PPU_ABI_FACTCHECK_PASS，28/28**
  - 首跑 27/28：`concat max out bytes` 抓出手册 V1.0 初稿笔误（409600 是全图
    最大单缓冲=conv 输出；concat 最大输出实为 307200 = model.2.cat/model.14）。
    手册已改（§1 表），检查同步改 307200，复跑全绿。
- 覆盖：rom sha 四件、任务普查 104=63+41、req_pair(1.0) 恒等性、尺度比域
  [0.3956,1.8597]/50 样本/0 死通道/31 唯一对、add 同形断言、concat 通道核算
  +最大 4 输入、view 对半切、maxpool5/upsample2 形状、heads 149100 布局偏移、
  buffer 104 项/6,715,500 B/最大 409,600、PPU 流量 rd 2,427,500 + wr 2,389,100、
  golden 覆盖 12 图算子节点+每帧 53 可比节点（与 G0 一致）、CSR RTL 几何
  （128×32=16KB、窗口分页、word14 合同、opcode 0x10–0x15 未占用）。
- 产物：`factcheck_console.log`、`factcheck_result.json`（含输入 sha）。
