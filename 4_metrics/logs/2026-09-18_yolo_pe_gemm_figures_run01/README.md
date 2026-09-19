# PE / GEMM 架构图生成证据

来源：`1_docs/yolo_pe_design_manual_20260918.md` 与 `1_docs/yolo_gemm_design_manual_20260918.md`。

命令：`python E:/competition/4_metrics/logs/2026-09-18_yolo_pe_gemm_figures_run01/draw_architecture.py`。

生成器：Matplotlib 3.10.9；Microsoft YaHei 字体。三张图分别生成 SVG、PNG、PDF，共九个文件。路径与 SHA-256 见 `manifest.json`。

视觉检查：三张 PNG 均读取检查；发现 GEMM 参数连线穿过说明框及字体缺少双向箭头，已修正并重新生成；最终 GEMM PNG 再次读取确认。图中文字、位宽、存储有效容量与手册一致。结果：FIGURE_RENDER_REVIEW_PASS。此状态仅代表图形生成和检查，不是硬件功能通过。

命令最终退出 0，九个文件生成，无缺字警告。未修改冻结 `2_fpga`；未运行 RTL 仿真、综合或板测。

路径审计命令：`powershell -ExecutionPolicy Bypass -File E:/competition/4_metrics/scripts/audit_project_skill_paths.ps1`。
审计结果：pass=false；唯一报告 `6_skill/vivado-bd-bitstream/SKILL.md : missing fixed E:\competition workspace path`。与上一手册任务相同，未修改该技能。
