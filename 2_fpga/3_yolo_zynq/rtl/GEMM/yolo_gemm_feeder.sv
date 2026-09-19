/************************************************************************
 * File Name       : yolo_gemm_feeder.sv
 * Developer       : LSL
 * Date            : 2026-09-19
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_gemm_feeder
 * Description     : G2/V2 (run09) bank -> GEMM exit stage: the ONE k
 *                   sequencer between the dual-group operand bank and
 *                   the (V2.0 pure-consumer) array.
 *
 *   Job interface (scheduler = TB now, CSR desc table in G4): one block
 *   descriptor {len, first, last, w_grp, x_grp}. Every load block starts
 *   at group address 0, so the sequencer counts k WITHIN the block from
 *   0 -- the absolute-k / block-base responsibility that run08 moved to
 *   the supplier is hereby retired: block base lives in the LOAD order,
 *   not in the read side.
 *
 *   Pipeline (address leads TWO beats: BRAM sync-read 1 + hold reg 1):
 *     kcnt -> [bank raddr] -> (1 beat) dout stage v1 -> (1 beat) hold
 *     stage v2 -> {w_word, x_word} + word_valid/first/last.
 *     Stall-safe: kcnt only advances when the pipe advances, so under
 *     word_ready backpressure the address freezes and both BRAM douts
 *     stay stable -- indefinite stall is legal.
 *
 *   Group handling (independent w_sel/x_sel, reuse-resident ready):
 *     the job's group bits latch into the ACTIVE group regs on the
 *     observed "array entered ISSUE" beat (= one beat after the array
 *     accepted the block header -- the array exposes no accept pulse,
 *     ISSUE entry is observable as word_ready rising; the header was
 *     necessarily accepted to get there). The flip lands one cycle
 *     before the first read address issues, so address routing and the
 *     exit-stage dout MUX (HERE, per board plan section 2 -- the bank
 *     exposes both groups' douts) always agree. Previous-block margin:
 *     the old group's last address left the port >= 2 beats before
 *     (array DRAIN >= 4), satisfying the structural no-conflict rule.
 *
 *   Header gating: blk_valid is presented only once BOTH selected
 *     groups report loaded -- a late load (job handed before the data)
 *     simply holds the header; the consumer sees nothing early.
 *
 *   FSM: S_IDLE (job_ready) -> S_HDR (present header, wait ISSUE entry)
 *     -> S_STREAM (pipeline until last word accepted + pipe drained)
 *     -> S_IDLE. One job register, no queue (V2 scope).
 ************************************************************************/
module yolo_gemm_feeder #(
    parameter integer P_TO = 8,     //与 bank/阵列一致
    parameter integer P_TN = 16
) (
    input  wire               clk_i,
    input  wire               rst_i,
    // ---- 作业口（调度方：TB / G4 CSR）----
    input  wire               job_valid_i,
    output wire               job_ready_o,   //S_IDLE 即空
    input  wire        [12:0] job_len_i,     //块字数 >=1
    input  wire               job_first_i,   //tile 首块（透传阵列）
    input  wire               job_last_i,    //tile 末块（透传阵列）
    input  wire               job_w_grp_i,   //W 读组
    input  wire               job_x_grp_i,   //X 读组（独立于 W）
    // ---- bank 读侧驱动 ----
    output wire               w_rgrp_o,
    output wire        [12:0] w_raddr_o,
    output wire               w_ren_o,
    input  wire [8*P_TO-1:0]  w_dout_g0_i,
    input  wire [8*P_TO-1:0]  w_dout_g1_i,
    output wire               x_rgrp_o,
    output wire        [12:0] x_raddr_o,
    output wire               x_ren_o,
    input  wire [8*P_TN-1:0]  x_dout_g0_i,
    input  wire [8*P_TN-1:0]  x_dout_g1_i,
    // ---- bank 组已装载状态（header 门控）----
    input  wire        [1:0]  w_grp_ld_i,
    input  wire        [1:0]  x_grp_ld_i,
    // ---- 读侧在飞导出（bank 写口组安全门控用）----
    output wire               rd_busy_o,     //字流未完全排空：S_STREAM 或流水有字
    // ---- 阵列侧（V2.0 冻结契约的供方侧）----
    output wire               blk_valid_o,
    output wire        [12:0] blk_len_o,
    output wire               blk_first_o,
    output wire               blk_last_o,
    output wire [8*P_TO-1:0]  w_word_o,
    output wire [8*P_TN-1:0]  x_word_o,
    output wire               word_valid_o,
    output wire               word_first_o,
    output wire               word_last_o,
    input  wire               word_ready_i   //阵列 ISSUE 态=1
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_HDR  = 2'd1,
                     S_STREAM = 2'd2;

    reg [1:0]  state;
    // 作业寄存（S_HDR 呈现给阵列的字段来源）
    reg [12:0] j_len;
    reg        j_first, j_last, j_wgrp, j_xgrp;
    // 活动块寄存（观测到进 ISSUE 拍锁存，随后一拍起发地址）
    reg        a_wgrp, a_xgrp;
    reg [12:0] a_len;
    reg [12:0] kcnt;
    reg        blk_active;
    // 两级流水（v1=dout 级，v2=保持寄存级）
    reg        v1, v2;
    reg [1:0]  sb1, sb2;                 //{first,last} 旁带随字流水
    reg [8*P_TO-1:0] w_hold;
    reg [8*P_TN-1:0] x_hold;

    wire out_accept = v2 && word_ready_i;              //v2 即 word_valid_o
    wire adv2 = !v2 || out_accept;
    wire adv1 = !v1 || adv2;
    wire issue = blk_active && adv1 && (kcnt < a_len);
    wire [1:0] sb_new = {(kcnt == 13'd0), (kcnt == a_len - 13'd1)};

    // header 呈现门控：两组都已装载才亮
    wire hdr_on = (state == S_HDR) &&
                  w_grp_ld_i[j_wgrp] && x_grp_ld_i[j_xgrp];
    assign blk_valid_o = hdr_on;
    assign blk_len_o   = j_len;
    assign blk_first_o = j_first;
    assign blk_last_o  = j_last;

    // 观测到阵列进 ISSUE（word_ready 升起）= header 已被接受
    wire issue_entered = hdr_on && word_ready_i;

    assign job_ready_o = (state == S_IDLE);

    always @(posedge clk_i) begin
        if (rst_i) begin
            state      <= S_IDLE;
            v1         <= 1'b0;
            v2         <= 1'b0;
            sb1        <= 2'b00;
            sb2        <= 2'b00;
            blk_active <= 1'b0;
            kcnt       <= 13'd0;
            a_len      <= 13'd0;
            a_wgrp     <= 1'b0;
            a_xgrp     <= 1'b0;
            j_len      <= 13'd0;
            j_first    <= 1'b0;
            j_last     <= 1'b0;
            j_wgrp     <= 1'b0;
            j_xgrp     <= 1'b0;
        end else begin
            // ---- 作业接收 ----
            if ((state == S_IDLE) && job_valid_i) begin
                j_len   <= job_len_i;
                j_first <= job_first_i;
                j_last  <= job_last_i;
                j_wgrp  <= job_w_grp_i;
                j_xgrp  <= job_x_grp_i;
                state   <= S_HDR;
            end
            // ---- 换组拍=观测进 ISSUE 拍：活动组/长度锁存，次拍起发地址 ----
            if (issue_entered) begin
                a_wgrp     <= j_wgrp;
                a_xgrp     <= j_xgrp;
                a_len      <= j_len;
                kcnt       <= 13'd0;
                blk_active <= 1'b1;
                state      <= S_STREAM;
            end
            // ---- 两级流水推进（可无限期停：地址冻结则 dout 稳定）----
            v2 <= adv2 ? v1 : 1'b1;
            v1 <= adv1 ? issue : 1'b1;
            if (adv2) begin
                w_hold <= a_wgrp ? w_dout_g1_i : w_dout_g0_i;  //出口级组 MUX
                x_hold <= a_xgrp ? x_dout_g1_i : x_dout_g0_i;
                sb2    <= sb1;
            end
            sb1 <= adv1 ? (issue ? sb_new : 2'b00) : sb1;
            if (issue) begin
                kcnt <= kcnt + 13'd1;
                if (kcnt == a_len - 13'd1)
                    blk_active <= 1'b0;     //末地址已发：停发，流水自然排空
            end
            // ---- 块收尾：末字已接受且流水排空 -> 回 IDLE ----
            if ((state == S_STREAM) && !blk_active && !v1 && !v2)
                state <= S_IDLE;
        end
    end

    // 块末地址发完即停发（blk_active 清零），流水排空中不再有 ren
    assign w_ren_o   = issue;
    assign x_ren_o   = issue;
    assign w_raddr_o = kcnt;
    assign x_raddr_o = kcnt;
    assign w_rgrp_o  = a_wgrp;
    assign x_rgrp_o  = a_xgrp;

    assign word_valid_o = v2;
    assign word_first_o = sb2[1];
    assign word_last_o  = sb2[0];
    assign w_word_o     = w_hold;
    assign x_word_o     = x_hold;
    // 字流窗口全程为 1（含停拍冻结与末字排空），完全排空后释放组给写侧
    assign rd_busy_o    = (state == S_STREAM) || v1 || v2;

endmodule
