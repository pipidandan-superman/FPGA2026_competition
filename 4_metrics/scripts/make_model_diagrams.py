# -*- coding: utf-8 -*-
"""Render EES-331 YOLOv8n structure and end-to-end data flow diagrams to PNG.

Verified sources: best.onnx graph (233 nodes, shape inference), best.pt summary
(129 layers, 3,012,213 params, 8.2 GFLOPs), display_test.bd nets, camera.py.
Run with the model_env venv python. Output: 1_docs/*.png
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "sans-serif"]
plt.rcParams["axes.unicode_minus"] = False

C_BACK = "#dbeafe"; C_BACK_E = "#1d4ed8"   # backbone
C_NECK = "#dcfce7"; C_NECK_E = "#15803d"   # neck
C_HEAD = "#ffedd5"; C_HEAD_E = "#c2410c"   # detect head
C_OUT  = "#f3e8ff"; C_OUT_E  = "#7e22ce"   # output/DFL
C_POST = "#e5e7eb"; C_POST_E = "#374151"   # PC postprocess


def box(ax, x, y, w, h, lines, fc, ec, fs=8.5, sp=1.8):
    """y axis is inverted: smaller yy renders higher. Line 0 is the bold title."""
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                                boxstyle="round,pad=0.15,rounding_size=0.6",
                                fc=fc, ec=ec, lw=1.2, zorder=2))
    n = len(lines)
    for i, t in enumerate(lines):
        yy = y - (n - 1) * sp / 2 + i * sp
        ax.text(x, yy, t, ha="center", va="center",
                fontsize=fs, fontweight="bold" if i == 0 else "normal", zorder=3)


def arrow(ax, p1, p2, color="#334155"):
    ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle="-|>", mutation_scale=12,
                                 color=color, lw=1.2, zorder=1))


def band(ax, y0, y1, label, color):
    ax.axhspan(y0, y1, color=color, alpha=0.25, zorder=0)
    ax.text(1.0, (y0 + y1) / 2, label, rotation=90, ha="center", va="center",
            fontsize=11, fontweight="bold", color="#1f2937")


def render_structure(path):
    TOP = 187
    fig, ax = plt.subplots(figsize=(11.5, 28.5), dpi=110)
    ax.set_xlim(0, 100); ax.set_ylim(0, TOP)
    ax.invert_yaxis(); ax.axis("off")

    ax.text(52, 1.9, "YOLOv8n（本工程 gesture_v1，nc=7）输入 [1,3,640,640] float32 0~1（下框均标注该层输出）\n"
                     "best.pt 官方统计：129 层 / 3,012,213 参数 / 8.2 GFLOPs；ONNX 图 233 节点，其中 Conv 64 个",
            ha="center", va="center", fontsize=11, fontweight="bold")

    backbone = [
        ("model.0  Conv 3×3 s2  (3→16, BN+SiLU)", "[1,16,320,320]"),
        ("model.1  Conv 3×3 s2  (16→32)", "[1,32,160,160]"),
        ("model.2  C2f×1  (Split+Bottleneck+Concat→32)", "[1,32,160,160]"),
        ("model.3  Conv 3×3 s2  (32→64)", "[1,64,80,80]"),
        ("model.4  C2f×2", "[1,64,80,80]"),
        ("model.5  Conv 3×3 s2  (64→128)", "[1,128,40,40]"),
        ("model.6  C2f×2   ←P4 横向连接点", "[1,128,40,40]"),
        ("model.7  Conv 3×3 s2  (128→256)", "[1,256,20,20]"),
        ("model.8  C2f×1", "[1,256,20,20]"),
        ("model.9  SPPF (cv1→3×MaxPool5→concat→cv2)   ←P5 横向连接点", "[1,256,20,20]"),
    ]
    neck = [
        ("model.10  Upsample ×2 (最近邻)", "[1,256,40,40]"),
        ("model.11  Concat ⊕ model.6", "[1,384,40,40]"),
        ("model.12  C2f 384→128   ←供17、20拼接", "[1,128,40,40]"),
        ("model.13  Upsample ×2", "[1,128,80,80]"),
        ("model.14  Concat ⊕ model.4", "[1,192,80,80]"),
        ("model.15  C2f 192→64   ←P3 输出", "[1,64,80,80]"),
        ("model.16  Conv 3×3 s2 (64→64)", "[1,64,40,40]"),
        ("model.17  Concat ⊕ model.12", "[1,192,40,40]"),
        ("model.18  C2f 192→128   ←P4 输出", "[1,128,40,40]"),
        ("model.19  Conv 3×3 s2 (128→128)", "[1,128,20,20]"),
        ("model.20  Concat ⊕ model.9", "[1,384,20,20]"),
        ("model.21  C2f 384→256   ←P5 输出", "[1,256,20,20]"),
    ]

    W, H, STEP = 54, 4.2, 4.6
    y = 12.0
    box(ax, 52, y - STEP, W, H,
        ["网络输入 images（letterbox 后）", "[1,3,640,640] = 640×640 RGB，÷255"],
        "#ffffff", "#111827", sp=1.6)
    arrow(ax, (52, y - STEP + H / 2 + 0.15), (52, y - H / 2 - 0.15))
    prev = None
    prev = None
    for i, (t, s) in enumerate(backbone):
        cy = y + i * STEP
        box(ax, 52, cy, W, H, [t, s], C_BACK, C_BACK_E, sp=1.6)
        if prev is not None:
            arrow(ax, (52, prev + H / 2 + 0.15), (52, cy - H / 2 - 0.15))
        prev = cy
    y0_back = y - 0.5
    y += len(backbone) * STEP + 1.0
    y0_neck = y
    for i, (t, s) in enumerate(neck):
        cy = y + i * STEP
        box(ax, 52, cy, W, H, [t, s], C_NECK, C_NECK_E, sp=1.6)
        arrow(ax, (52, prev + H / 2 + 0.15), (52, cy - H / 2 - 0.15))
        prev = cy
    y1_neck = y + len(neck) * STEP - 0.7
    band(ax, y0_back, y1_neck, "Backbone 主干", "#bfdbfe")
    band(ax, y0_neck, y1_neck, "Neck  PAN-FPN", "#bbf7d0")

    # detect head: 3 columns
    hy0 = y1_neck + 0.6
    ax.text(52, hy0 + 1.1, "Head  Detect（model.22 解耦头，逐层维度来自 best.onnx 实测）",
            ha="center", fontsize=10, fontweight="bold", color="#9a3412")
    cols = [
        (22, "P3 大目标 80×80",
         [("cv2.0 回归支路 64→64→64→64", "[1,64,80,80]"), ("Reshape", "[1,64,6400]"),
          ("cv3.0 分类支路 64→64→64→7", "[1,7,80,80]"), ("Reshape", "[1,7,6400]")]),
        (52, "P4 中目标 40×40",
         [("cv2.1 回归支路 128→64→64→64", "[1,64,40,40]"), ("Reshape", "[1,64,1600]"),
          ("cv3.1 分类支路 128→64→64→7", "[1,7,40,40]"), ("Reshape", "[1,7,1600]")]),
        (82, "P5 小目标 20×20",
         [("cv2.2 回归支路 256→64→64→64", "[1,64,20,20]"), ("Reshape", "[1,64,400]"),
          ("cv3.2 分类支路 256→64→64→7", "[1,7,20,20]"), ("Reshape", "[1,7,400]")]),
    ]
    HH, HW, CSTEP = 5.6, 25, 9.0
    cy_start = hy0 + 8.6
    col_last = {}
    for cx, title, items in cols:
        ax.text(cx, hy0 + 3.6, title, ha="center", fontsize=9.5, fontweight="bold")
        if cx == 52:
            arrow(ax, (52, hy0 + 5.2), (52, cy_start - HH / 2 - 0.3))
        else:
            arrow(ax, (52, hy0 + 2.2), (cx, cy_start - HH / 2 - 0.3))
        cy = cy_start
        for j, (t, s) in enumerate(items):
            box(ax, cx, cy, HW, HH, [t, s], C_HEAD, C_HEAD_E, fs=8, sp=1.7)
            if j < len(items) - 1:
                arrow(ax, (cx, cy + HH / 2 + 0.15), (cx, cy + CSTEP - HH / 2 - 0.15))
            cy += CSTEP
        col_last[cx] = cy - CSTEP
    col_bottom = max(col_last.values()) + HH / 2
    my = col_bottom + 4.8
    for cx, lasty in col_last.items():
        arrow(ax, (cx, lasty + HH / 2 + 0.15), (cx, my - 1.7 - 0.15))
    box(ax, 52, my, 66, 3.6,
        ["Concat：box [1,64,8400] ⊕ cls(Sigmoid) [1,7,8400]", "8400 = 6400+1600+400"],
        C_OUT, C_OUT_E, fs=9, sp=1.6)
    seq = [
        "DFL：Reshape[1,4,16,8400] → Softmax(16 bins) → 固定权重Conv → [1,4,8400]",
        "anchor解码：网格anchor±边距、×stride(8/16/32) → xywh（640×640 像素系）",
        "output0：[1, 11, 8400]  = 4框 + 7类得分",
        "PC后处理：conf≥0.45过滤 → NMS(IoU 0.7) → xywh→xyxy → 减pad80 → 640×480坐标",
        "结果：{label∈7类手势, confidence, xyxy} → 3帧同类≥0.75 → 动作命令 UDP:5001",
    ]
    cy = my
    for t in seq:
        prev_c = cy
        cy += 5.0
        fc, ec = (C_POST, C_POST_E) if t.startswith(("PC后处理", "结果")) else (C_OUT, C_OUT_E)
        box(ax, 52, cy, 80, 3.6, [t], fc, ec, fs=9)
        arrow(ax, (52, prev_c + 1.8 + 0.15), (52, cy - 1.8 - 0.15))
    band(ax, hy0, cy + 2.2, "Head + 输出", "#fed7aa")
    fig.savefig(path, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def render_dataflow(path):
    fig, ax = plt.subplots(figsize=(15, 10), dpi=110)
    ax.set_xlim(0, 150); ax.set_ylim(0, 98)
    ax.invert_yaxis(); ax.axis("off")
    ax.text(75, 2.0, "EES-331 手势识别 端到端数据流（PL 无模型预处理；letterbox/归一化均在 PC 端）",
            ha="center", fontsize=13, fontweight="bold")

    C_PL = "#dbeafe"; C_PL_E = "#1d4ed8"
    C_PS = "#fef9c3"; C_PS_E = "#a16207"
    C_PC = "#dcfce7"; C_PC_E = "#15803d"
    C_CTRL = "#fee2e2"; C_CTRL_E = "#b91c1c"
    C_SHOW = "#e0e7ff"; C_SHOW_E = "#4338ca"

    W, H = 22, 9.0
    row1_y = 14
    row1 = [
        (14, "OV5640 传感器\nSCCB配置 640×480\nRGB565 DVP输出", C_PL, C_PL_E),
        (38, "PL采集 cam_cap_data\n2×8bit拼RGB565\n→高位复制成RGB888", C_PL, C_PL_E),
        (62, "v_vid_in_axi4s\n24bit视频时序\n→AXI4-Stream", C_PL, C_PL_E),
        (86, "VDMA S2MM 写DDR\n3槽循环 每槽0x100000\n帧=921600B(640×480×3)", C_PL, C_PL_E),
        (110, "PS camera.py\n5fps快照完成槽\n拆640包×1440B\nOV56头+CRC32", C_PS, C_PS_E),
        (134, "UDP:5000 →PC\n192.168.240.2\nw=640 h=480\nstride=1920", C_PS, C_PS_E),
    ]
    for x, t, fc, ec in row1:
        box(ax, x, row1_y, W, H, t.split("\n"), fc, ec, fs=8.2, sp=2.0)
    for i in range(len(row1) - 1):
        arrow(ax, (row1[i][0] + W / 2, row1_y), (row1[i + 1][0] - W / 2, row1_y))

    row2_y = 40
    row2 = [
        (110, "PC重组 validated_receiver\n校验后 reshape(480,640,3)\nBGR 帧", C_PC, C_PC_E),
        (86, "模型预处理(Ultralytics)\nletterbox→640×640\n上下补80行灰114\nBGR→RGB、÷255", C_PC, C_PC_E),
        (62, "YOLOv8n 推理 CPU\nbest.pt / best.onnx\n129层 3.01M参数\n8.2 GFLOPs", C_PC, C_PC_E),
        (38, "输出 [1,11,8400]\n4框+7类得分\n(8400=6400+1600+400)", C_PC, C_PC_E),
        (14, "后处理\nconf≥0.45→NMS(0.7)\n→640×480坐标\n7类手势结果", C_PC, C_PC_E),
    ]
    for x, t, fc, ec in row2:
        box(ax, x, row2_y, W, H, t.split("\n"), fc, ec, fs=8.2, sp=2.0)
    arrow(ax, (row1[5][0], row1_y + H / 2), (row2[0][0] + W / 2 - 2, row2_y - H / 2))
    for i in range(len(row2) - 1):
        arrow(ax, (row2[i][0] - W / 2, row2_y), (row2[i + 1][0] + W / 2, row2_y))

    row3_y = 67
    row3 = [
        (14, "stable_action.py\n3个新帧同类且\nconf≥0.75 → 命令\n1s无动作→CLEAR", C_CTRL, C_CTRL_E),
        (38, "UDP:5001 回程\n→板端ActionService", C_CTRL, C_CTRL_E),
        (62, "AXI-Lite写0x43C00000\n(GP0→SmartConnect)", C_PL, C_PL_E),
        (86, "PL动作执行器\nLED×7 one-hot\nUART TX 9600-8N1\nA5 5A SEQ ACT CRC 0D 0A", C_PL, C_PL_E),
        (110, "PC COM4 抓串口帧核对\n(只收不发)", C_CTRL, C_CTRL_E),
    ]
    for x, t, fc, ec in row3:
        box(ax, x, row3_y, W, H, t.split("\n"), fc, ec, fs=8.2, sp=2.0)
    arrow(ax, (row2[4][0], row2_y + H / 2), (row3[0][0], row3_y - H / 2))
    for i in range(len(row3) - 1):
        arrow(ax, (row3[i][0] + W / 2, row3_y), (row3[i + 1][0] - W / 2, row3_y))

    # HDMI display branch: corridor at x=74.2 (between row boxes at 62 and 86)
    show_y = 89
    box(ax, 74.2, show_y, 34, 6.5,
        ["VDMA MM2S 读同一组槽", "v_axi4s_vid_out+v_tc → ADV7511 → HDMI", "pix_frame_display 字符叠加；仅人眼监控"],
        C_SHOW, C_SHOW_E, fs=7.8, sp=1.7)
    bx = 74.2
    ax.plot([86, 86], [row1_y + H / 2, 26.0], color="#4338ca", lw=1.2, zorder=1)
    ax.plot([86, bx], [26.0, 26.0], color="#4338ca", lw=1.2, zorder=1)
    ax.plot([bx, bx], [26.0, show_y - 3.25 - 1.2], color="#4338ca", lw=1.2, zorder=1)
    arrow(ax, (bx, show_y - 3.25 - 1.0), (bx, show_y - 3.25 - 0.1), color="#4338ca")

    for y, t, c in [(row1_y - H / 2 - 1.8, "① 采集/传输（FPGA 板端）", "#1d4ed8"),
                    (row2_y - H / 2 - 1.8, "② PC 模型链路（右→左）", "#15803d"),
                    (row3_y - H / 2 - 1.8, "③ 动作回程控制（左→右）", "#b91c1c")]:
        ax.text(1, y, t, fontsize=9.5, fontweight="bold", color=c)
    ax.text(74.2, show_y - 5.6, "显示支路（不进模型）", fontsize=9, fontweight="bold",
            color="#4338ca", ha="center")
    fig.savefig(path, bbox_inches="tight", facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    render_structure(r"E:/competition/1_docs/YOLOv8n_网络结构_7类_640.png")
    render_dataflow(r"E:/competition/1_docs/端到端数据流_EES331手势_v1.png")
    print("OK")
