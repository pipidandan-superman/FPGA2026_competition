# P2e xfer 门 run01a 首跑失败 console 摘录（存档）

- 说明：run01a（V1.0 引擎）失败运行的完整 console 被重跑同名覆盖，
  本文件为失败当时 grep 捕获的**错误摘录**（前 30 条 EES_ 行），
  非完整日志——工具纪律缺口已在 run01 README 教训②记录。
- 现象：装载交叉 0 错；T1 运行期 DUT 数据整体滞后期望一拍
  （beat0 y=00 恒等段字节、此后 y[N]=want[N-1]），且 y_valid 无
  lat_err —— 有效链对齐、数据链多一级。
- 根因：恒等旁路数据链 x1→x2→x3→y_o 四级，而有效链
  v1→v2→y_valid 三级（ADD 引擎数据在写拍组合入 y_o，无此问题）。
  修复=旁路 mux 改用 x2_r/id2_r（与 pa_r/s2_r 同级采样），删
  x3_r/id3_r → run01 PASS。

```
# EES_XFER_INFO loaded 101 tasks / 1382 bytes (cross done)
# EES_XFER_ERR [135000] beat0 y=00 want=d7 (x=d7)
# EES_XFER_ERR [145000] beat1 y=d7 want=3f (x=3f)
# EES_XFER_ERR [155000] beat2 y=3f want=4c (x=4c)
# EES_XFER_ERR [165000] beat3 y=4c want=39 (x=39)
# EES_XFER_ERR [175000] beat4 y=39 want=65 (x=65)
# EES_XFER_ERR [185000] beat5 y=65 want=59 (x=59)
# EES_XFER_ERR [195000] beat6 y=59 want=f4 (x=f4)
# EES_XFER_ERR [205000] beat7 y=f4 want=8b (x=8b)
# EES_XFER_ERR [215000] beat8 y=8b want=f5 (x=f5)
# EES_XFER_ERR [225000] beat9 y=f5 want=4f (x=4f)
# EES_XFER_ERR [235000] beat10 y=4f want=66 (x=66)
# EES_XFER_ERR [245000] beat11 y=66 want=cd (x=cd)
# EES_XFER_ERR [255000] beat12 y=cd want=84 (x=84)
# EES_XFER_ERR [265000] beat13 y=84 want=df (x=df)
# EES_XFER_ERR [275000] beat14 y=df want=20 (x=20)
# EES_XFER_ERR [285000] beat15 y=20 want=25 (x=25)
# EES_XFER_ERR [295000] beat16 y=25 want=d1 (x=d1)
# EES_XFER_ERR [305000] beat17 y=d1 want=11 (x=11)
# EES_XFER_ERR [315000] beat18 y=11 want=95 (x=8f)
# EES_XFER_ERR [615000] beat0 y=c2 want=56 (x=56)
# EES_XFER_ERR [625000] beat1 y=56 want=0c (x=0c)
# EES_XFER_ERR [635000] beat2 y=0c want=8d (x=8d)
# EES_XFER_ERR [655000] beat3 y=8d want=c0 (x=c0)
# EES_XFER_ERR [665000] beat4 y=c0 want=b3 (x=b3)
# EES_XFER_ERR [675000] beat5 y=b3 want=0f (x=0f)
# EES_XFER_ERR [685000] beat6 y=0f want=73 (x=73)
# EES_XFER_ERR [695000] beat7 y=73 want=35 (x=35)
# EES_XFER_ERR [705000] beat8 y=35 want=f5 (x=f5)
# EES_XFER_ERR [715000] beat9 y=f5 want=9d (x=9d)
```
