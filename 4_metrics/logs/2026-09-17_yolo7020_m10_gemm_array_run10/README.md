# M10 gemm_array 门 run10 — B0 迭代 11（requant V1.2f + addrgen V1.3 + gemm_array V1.8，2026-09-17）

## 结果：TB_GEMM_ARRAY_PASS（计数与 run06–run09 / v21–v24 逐一相同）

```
TB_GEMM_ARRAY_PASS layers=6 compared=438447 dut_wr=438447 gold_wr=3247 ldone=6 adone=1
$finish : Time: 47770370 ns
```

数值字节逐位不变；层完成时刻微小漂移（layer0 @29916000，v24 为
@29896000，+2 拍 = addrgen 呈现 +1、requant 尾 +1 的合法平移；总时长
回到 47770370 与 v24 相同——漂移被层间等待吸收）。

## 首跑 v25a FAIL（transcript 留档 m10_v25a_xsim_fail.log）

err=134307（首差 L=0 i=1 dut=0 gold=127）——gemm_array Y 尾是挂接
requant PIPE=5 的固定延迟 en 链（LUT en rq_en_d6_r、sideband d7、
SEG_IDLE 读 d7）：requant V1.2f PIPE=6 下 LUT 在 d6 采到上一拍滞留
的 y_pre，字节流整体错位。根因 = 本模块对 requant 延迟的隐性耦合，
V1.8 修复（M5/M7 单元门无法拦截——两单元各自正确，仅集成合同错位）。

## RTL 变更（相对 run09 / v24）

- `yolo_requant.v` V1.2e→V1.2f：prod2_r fabric 重寄存（DSP P 内发火
  修复），PIPE 5→6，纯输出侧重定时（M5 v25 PASS 承证）。
- `yolo_addrgen.v` V1.2→V1.3：两级输出寄存拆分窗口解码 + last_k
  超前一拍预测，呈现 +1 拍（M7 v25 PASS；v25a 对齐 bug transcript
  留档 m7_v25a_xsim_fail.log）。
- `yolo_gemm_array.v` V1.7→V1.8：Y 尾延迟链适配 PIPE=6——LUT en
  rq_en_d7_r、sideband 链延至 d8、SEG_IDLE 改读 d8、在途计数不变
  （d0..d8 峰值 8，仍 4 位）。ctrl 不动（S_DRAIN 由 acc 排空链决定）。

装填侧 addrgen 消费者为 vld/事件门控（xbuf WE 挂 xgen_vld_w、装载
FSM 挂 done 脉冲），+1 呈现平移被吸收——本轮 PASS 承证。

## 复现

```bash
cd 2_fpga/3_yolo_zynq/sim/xsim && bash run_m10_v25.sh
```

激励 = 冻结集 sim/stim/m10。原始日志：m10_v25_{xvlog,xelab,xsim}.log。

门链位置：B0 迭代 11——M5 v25 + M7 v25 → **M10 run10** → M12 csr v25
→ OOC v25。
