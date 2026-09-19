// G3 首层 conv 核：conv+bias(+z_sum)+每通道重量化(RNE 平局到偶)+SiLU LUT。
// 合同来源：3_yolo_zynq/pynq/intarith.py（rne_shift/sat_i8）+ yolo_runtime._conv(model.0)。
// 激励/期望：sim/stim/conv0_goldenNN/（golden npz 三方自检后冻结）。
//
// 形状：x int8 [3,320,320]（pad=-128, 3x3 stride2 -> [16,160,160]）
//   x 地址 = ic*102400 + ih*320 + iw        （ih/iw 出界 -> 常数 -128）
//   w 地址 = oc*27 + ic*9 + kh*3 + kw       （K=27，与 runtime im2col K 序一致）
//   y 地址 = oc*25600 + oy*160 + ox
// 数值链：acc int32 = Σ w*x（整数累加无舍入，次序无关）；
//   n int64 = (acc+bias_eff)*M；q = RNE(n, shift)；
//   y_pre = sat_i8(q)；y = LUT[(y_pre+128)&0xFF]。
// 首版 1 MAC/周期、组合读 RAM（数值门优先；BRAM/流水化在数值通过后做）。
module yolo_conv0_core (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    output logic        busy,
    output logic        done,
    // x / w / 参数 / LUT 读口（组合读）
    output logic [18:0] x_addr,              // 3*320*320 = 307200 > 2^18，需 19 位
    input  logic signed [7:0]  x_rdata,
    output logic [8:0]  w_addr,              // 16*27 = 432
    input  logic signed [7:0]  w_rdata,
    output logic [3:0]  bias_addr,           // 16
    input  logic signed [31:0] bias_rdata,
    output logic [3:0]  m_addr,              // 16
    input  logic signed [31:0] m_rdata,
    output logic [3:0]  shift_addr,          // 16
    input  logic [7:0]  shift_rdata,
    output logic [7:0]  lut_addr,            // 256
    input  logic signed [7:0] lut_rdata,
    // y 写口
    output logic        y_we,
    output logic [19:0] y_addr,              // 16*160*160 = 409600
    output logic signed [7:0] y_wdata
);

    localparam int OH = 160, OW = 160, IC = 3, OC = 16, KP = 27;

    typedef enum logic [2:0] {S_IDLE, S_MAC, S_REQUANT, S_LUTW, S_DONE} st_t;
    st_t st;

    logic [3:0]  oc;      // 0..15
    logic [7:0]  oy, ox;  // 0..159
    logic [4:0]  k;       // 0..26 = ic*9 + kh*3 + kw
    logic signed [31:0] acc;
    logic signed [7:0]  y_pre;

    // ---- RNE 右移（s ∈ [1,62]；变宽位域用掩码实现，避免非法 part-select） ----
    function automatic logic signed [63:0] rne_shift(
        input logic signed [63:0] n,
        input logic [7:0]         s);
        logic signed [63:0] q;
        logic [63:0] low_mask;
        logic half, low_any, round_up;
        q = n >>> s;                                   // floor
        if (s == 8'd0) begin
            round_up = 1'b0;
        end else begin
            half     = n[s-1];                         // 单比特变址合法
            low_mask = (64'd1 << (s - 8'd1)) - 64'd1;  // s=1 -> mask=0
            low_any  = |(n & low_mask);
            round_up = half & (low_any | q[0]);        // >半 或 平局且q奇
        end
        return q + (round_up ? 64'sd1 : 64'sd0);
    endfunction

    function automatic logic signed [7:0] sat_i8(input logic signed [63:0] v);
        if (v > 64'sd127)       return 8'sd127;
        else if (v < -64'sd128) return -8'sd128;
        else                    return v[7:0];
    endfunction

    // ---- 窗口坐标（pad=1, stride=2；有符号判定出界） ----
    function automatic int signed fk_ic(input int signed kk); return kk / 9;   endfunction
    function automatic int signed fk_ih(input int signed kk); return (kk % 9) / 3; endfunction
    function automatic int signed fk_iw(input int signed kk); return kk % 3;   endfunction

    int signed ih, iw;
    logic x_in;
    assign ih = oy*2 + fk_ih(k) - 1;
    assign iw = ox*2 + fk_iw(k) - 1;
    assign x_in = (ih >= 0) && (ih < 320) && (iw >= 0) && (iw < 320);

    assign x_addr    = fk_ic(k)*102400 + ih*320 + iw;   // 出界时地址无效值，不采样
    assign w_addr    = oc*KP + k;
    assign bias_addr = oc;
    assign m_addr    = oc;
    assign shift_addr = oc;
    assign lut_addr  = y_pre + 8'sd128;

    assign busy = (st != S_IDLE);

    logic signed [32:0] sum_b;
    logic signed [63:0] prod;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; oc <= 0; oy <= 0; ox <= 0; k <= 0;
            acc <= 0; y_pre <= 0; y_we <= 1'b0; done <= 1'b0;
        end else begin
            y_we <= 1'b0;
            done <= 1'b0;
            unique case (st)
                S_IDLE: if (start) begin
                    oc <= 0; oy <= 0; ox <= 0; k <= 0; acc <= 0;
                    st <= S_MAC;
                end
                S_MAC: begin
                    // 本拍地址=本拍数据（组合读）：tap k 直接累加。
                    // $signed 必须包住三目：否则 pad 常数 0x80 被无符号零扩展成 +128
                    if (k == 0) acc <= $signed(x_in ? x_rdata : -8'sd128) * w_rdata;
                    else        acc <= acc + $signed(x_in ? x_rdata : -8'sd128) * w_rdata;
                    if (k == KP-1) st <= S_REQUANT;
                    else           k <= k + 1;
                end
                S_REQUANT: begin
                    // 拼接是无符号的：不包 $signed 会把 acc 零扩展、并毒化下游乘法为无符号
                    sum_b = $signed({bias_rdata[31], bias_rdata}) + acc;
                    prod  = sum_b * m_rdata;
                    y_pre <= sat_i8(rne_shift(prod, shift_rdata));
                    st <= S_LUTW;
                end
                S_LUTW: begin
                    // lut_addr 由已寄存 y_pre 驱动，本拍组合读有效
                    y_we    <= 1'b1;
                    y_addr  <= oc*25600 + oy*160 + ox;
                    y_wdata <= lut_rdata;
                    // 步进 ox -> oy -> oc
                    k <= 0; acc <= 0;
                    if (ox == OW-1) begin
                        ox <= 0;
                        if (oy == OH-1) begin
                            oy <= 0;
                            if (oc == OC-1) st <= S_DONE;
                            else            oc <= oc + 1;
                        end else begin
                            oy <= oy + 1;
                        end
                    end else begin
                        ox <= ox + 1;
                    end
                    if (!(oc == OC-1 && oy == OH-1 && ox == OW-1)) st <= S_MAC;
                end
                S_DONE: begin
                    done <= 1'b1;
                    st   <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
