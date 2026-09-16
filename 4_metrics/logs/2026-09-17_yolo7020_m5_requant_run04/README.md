# 2026-09-17 M5 requant 门 run04 — B0 迭代 12（requant V1.2g）

## 结果：TB_REQUANT_PASS compared=21465 vectors (y_pre+vld, pipe=7)

计数与 v24 run03 / v25 相同；TB 唯一改动 `localparam PIPE = 7`
（en→vld 间隔 6 拍），订单式记分板黄金 hex 复用。

## RTL 变更（V1.2f→V1.2g）

v25 OOC 唯一 owner（sum_r_reg/C→prod_c_w__2/PCIN −0.079）：33×32 乘法
2-DSP 级联，DSP1 组合穿透 4.036ns（sum_r 是 c1 加法器输出，无输入
寄存器可吸收）。修复：乘法操作数增设一级直通重寄存 sum_x_r/m_x_r
（c1b 沿，PIPE 6→7，纯输入侧重定时），s 链伸长一级（s_x_r）——数值
逐位不变（同一乘积仅晚一拍）。

门链位置：B0 迭代 12——**M5 run04** → M10 v26 → M12 csr v26 →
OOC v26。
