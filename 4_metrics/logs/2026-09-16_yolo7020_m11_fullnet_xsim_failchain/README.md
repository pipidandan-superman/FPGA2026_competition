# 2026-09-16 yolo7020 M11 xsim 失败链——三路二分定位（已收口）

## 现象
M12 B0 修复批（pe_pack V1.1 DSP 源语 / xbuf V2.0 BMG IP / gemm_array
V1.2b）在 xsim 重跑 M11 全网门：conv0-4 干净，**conv5 (task=9,
oc=32 n=6400 k=48 kh=kw=1) 首错 i=0 dut=x，acc_err=204800/204800**，
后续层全毒化。终判 TB_FULLNET_FAIL err=2529900 dbl=0 unwritten=0
yaxi=0 dut_wr=3553900(exp 3553900)——写计数双射完好，数据为 X。
对照：M11 run03（ModelSim，V1.0 RTL）全网 PASS。

## 三路判决（全部同皮秒复现 t=119399015000）
1. **bisect1**：xbuf 回退 V1.0（无 BMG/IP）+ pe_pack V1.1 → 仍败
   ⇒ **xbuf V2.0 无罪**
2. **bisect2**：gemm_array V1.2a + pe_pack V1.0 + xbuf V2.0 → 仍败
   ⇒ **pe_pack V1.1 无罪** ⇒ 三处 RTL 改动全部排除
   ⇒ **根因 = xsim vs ModelSim 行为差异**（同 RTL 同 TB 同激励）
3. **XDBG 周期级看门狗**（当前失败配置）：X 首现
   ```
   t=119399015000 conv=5  (conv4 done @119396030000 后 2.985us)
   x_rdata=xx  x_addr=001c2000   ← 1843200 = conv5 xbase+32*6400
   rdata(权重DMA)/araddr/wbuf/输出流 wdata/wstrb 全干净
   xb.we=1 wr_bank=1 wcol=0 waddr=020 wdata=xx  ← X 正被写入 xbuf
   ```

## 已排除
- 激励漂移：ddr.hex/prog.hex 等 sha256 与 run03 记录逐一相同
- BMG 碰撞语义：tb_xbm_col 实测行为级给旧值（XBM_COL_OLD=0x11）
- $readmemh 预载：ddr.hex 1665001 行全合法 16 位 hex；单元微复现
  tb_memchk：img[230400]=476c599e13fea268 干净（xsim 单独读没问题）
- 字 230400（字节 1843200，conv4→conv5 间 RSCL dst 起点）在预载
  范围内，t0 干净 ⇒ X 是**运行中被写入**的
- Y 写 BFM 散播：wdata/wstrb 看门狗全程无 X，RMW 不可能造 X

## 关键结构事实
- conv5 是全网第一个 1×1 卷积（kh=kw=1, ic=48）；M10 六层激励全为
  3×3/2×2，该路径门级零覆盖
- xgen 装载与 conv4 计算双缓冲重叠：X 命中时 x_addr 已行进
  204800 字节 ⟹ 装载始于 conv4 计算期间
- conv5 输入窗 [1638400,1945600) = 2×COPY + 1×RSCL(写于 conv4
  layer_done 之后) —— RSCL 目标区在装载读它之前**尚未被 PS 任务
  写入**（时序竞争候选，待间谍判决）

## 进行中
- ~~镜像字间谍 run~~ → XDBG3（snap_xdbg3，判决落袋 2026-09-16）：
  ```
  [XDBG] FIRST X @t=119399015000 conv=5
  [XDBG2] direct img[230400]=x  nb 230398/230399=1616…/1619…（COPY2 区，干净）
  [SPYS] t=119.3ms w230400/w192000/w204800 全干净
  [SPYS] t=119.4ms w230400=x w192000=x w204800=0205…（COPY 干净写入）
  ```
  **判决：X 是 PS 任务链在 xsim 里写进镜像的**——ADD dst(1536000) 与
  RSCL dst(1843200) 变 X；COPY dst 干净落数；ADD 的 b 输入(1228800/
  1024000 采样点)干净。conv4 y 在 layer_done 比对时干净（compare 无
  错）却在 ADD 读时含 X ⟹ 嫌疑收敛到 TB t_add/t_rscl 在 xsim 的
  执行（大数组任务循环），非 DUT 读路径、非 RTL（与 bisect1/2 及
  ModelSim run03 通过自洽）。机制细节待 M11 线恢复后追（暂停中）。

## 终判（2026-09-16 晚，Plan B ModelSim 全网跑完）
- **TB_FULLNET_PASS convs=63 psops=65 compared=3553900 dut_wr=3553900
  head_bytes=149100 ldone=63 adone=1**（pb_m11_run.log，与本 README
  同目录；V4 前 RTL = pe_pack V1.1 + gemm_array V1.2b + xbuf V2.0）
- **M11_HEADCHK_PASS** sha256=9ce70525fc1732cde640bfa654919dd28504422aa9791a2875225ae6ad6aa6ad
  == run04 frame0 权威值，6 张量拆分（cv2/cv3 ×3 尺度）对 npz 逐字节全对
- 结论坐实：该批 RTL 在 ModelSim 全网 63 conv 逐位 + head 逐字节干净，
  **xsim 的 X 为仿真器/TB 级问题**（t_add/t_rscl 大数组任务循环）。
  B0 批（DSP 修复批）M11 门就此关闭；后续批 M11 以 ModelSim 为准。

## 文件
m11_{xvlog,xelab,xsim}.log = 原失败 run 全程
bisect1_xbuf_v10_xsim.log / bisect2_pepack_v10_xsim.log / xdbg_xsim.log
