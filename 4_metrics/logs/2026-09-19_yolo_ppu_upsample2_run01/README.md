# P2b — PPU upsample2 核 RTL 门 run01

- 日期：2026-09-19（深夜并行线）。DUT：`rtl_ppu/yolo_ppu_upsample2.sv`
  V1.0（最近邻 ×2 字节流核：每输入字节发射 4 拍 (dy,dx)=00/01/10/11，
  ph0 同拍接收同拍发射；**增量加法寻址** base/±1/±rowlen——与金文件
  乘法公式不同构；in_ready 反压（仅 ph0 收数），out_last 随末拍，
  D+1..D+4 寄存输出，ST_IDLE/ST_RUN）。
- 命令：`ppu_upsample2_vecgen.py <本目录>` → `vlog -novopt` →
  `vsim -c -novopt tb_yolo_ppu_upsample2 +GOLDEN=…/golden_upsample2.hex`。
- 结果：**EES_MODELSIM_RESULT PASS** — checks=643001 errors=0。
- 向量（11 形状，输入 79461 / 输出 317844 字节，生成期结构断言：
  每形状 addr 恰为 [0,4CHW) 精确置换 + 每拍数据==源字节）：
  包内真实 (256,10,10)→20×20（model.30）与 (128,20,20)→40×40
  （model.40）+ 合成边角 1×1×1 / C=1 / H=1 / W=1 / 奇宽 / 奇高 /
  16×16；发射序=每输入字节 dy,dx 00→01→10→11，地址=c·4HW+
  (2y+dy)·2W+2x+dx（输出缓冲字节偏移，零拷贝视图案在 P3 落表）。
- 期望值三源独立：金文件=`ppu_oracle.upsample2_q`+直接地址公式（P1
  已对软件 golden 闭环）‖ TB **按地址收集**交叉（由 addr 反解
  y=(addr/2W%2H)/2、x=(addr%2W)/2 断言 data==in[c][y][x]，与发射序
  不同构）‖ TB **乘法公式**自生成 2 随机形状 (7,13,9)/(31,5,6)
  （DUT 为增量加法，不同构）。
- 用例：T1 全 13 形状（常供/25% 随机间隔/每 50 字节停 7 拍三模式轮转）
  + T2 rst 在飞击杀（case (3,5,4) 喂 20 字节后杀）+ 重启全量复检 +
  收尾静默/busy 归零 + 80ms 看门狗。检查项：每拍 addr+data、
  out_last 恰在末拍、无多余输出。
- 首跑教训（见 TB/vecgen V1.0 头注与 P2a README 教训②同族）：金文件
  表头误用十六进制而 TB 按 %d 解析 → 用例边界错乱（125212 错）；
  修正=表头十进制（数据列保持十六进制）。DUT 结构本身首跑即对。
- 产物：golden_upsample2.hex、vecgen_result.json、vecgen_console.log、
  vlib.log、vlog.log、vsim_console.log、msim/transcript、
  脚本副本 ×3（yolo_ppu_upsample2.sv / tb_yolo_ppu_upsample2.sv /
  ppu_upsample2_vecgen.py）。
