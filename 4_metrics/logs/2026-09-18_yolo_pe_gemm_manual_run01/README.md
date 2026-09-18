# PE/GEMM 手册文档证据

- 日期：2026-09-18
- 类型：文档设计与来源可追溯性记录
- 输出：`1_docs/yolo_pe_design_manual_20260918.md`、`1_docs/yolo_gemm_design_manual_20260918.md`
- 读取来源：现有 PE/累加/重定量 RTL、`schedule.json`、`quant.json`、旧 GEMM/PE 架构文档。
- 本次没有修改 `2_fpga/`，没有新增 RTL，也没有宣称完成 RTL 仿真、综合或上板验证。
- `manifest.json` 保存输出文档和主要输入文件的 SHA-256 与字节数。
- 手册中的推荐参数是硬件设计起点，必须经过 PE oracle、RTL testbench、综合和板级测量后冻结。
