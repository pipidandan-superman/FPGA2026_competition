/************************************************************************
 * File Name       : yolo_desc_walker.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_desc_walker
 * Description     : Descriptor queue walker - the scheduler skeleton of
 *                   the YOLO CSR subsystem.  Consumes descriptors via
 *                   the head pointer (PS pushes through DESC_TAIL +
 *                   doorbell), accumulates expected output bytes
 *                   (word14) and publishes one result-ring entry per
 *                   frame (descriptor last-bit or PS-forced frame_end).
 *                   The compute engine (63 convs etc.) replaces the
 *                   walk-through later; the queue/result contract stays
 *                   frozen.  Descriptor BRAM port B has no output
 *                   register: registered address -> data is 2 cycles,
 *                   so each word uses one address state plus one data
 *                   state.
 * Dependencies    : yolo_csr_pkg.sv, yolo_desc_table.sv (BMG IP)
 * Revision History:
 *   - V2.0 (2026-09-18) by LSL : Three-block FSM refactor; fixed
 *                                one-cycle-early BRAM data sampling
 *                                (address/data wait states split).
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_desc_walker (
    input  wire        clk_i              ,
    input  wire        rst_n              ,
    input  wire        soft_reset_i       ,
    // control (from register file)
    input  wire        enable_i           ,
    input  wire        start_frame_i      ,  // pulse
    input  wire        stop_i             ,  // pulse: graceful stop
    input  wire        abort_i            ,  // pulse: discard frame
    input  wire        doorbell_commit_i  ,  // informational (tail polled)
    input  wire        frame_end_pending_i,  // sticky, set by doorbell
    output reg         frame_end_clear_o  ,  // pulse when consumed
    // queue state
    input  wire [15:0] desc_tail_i        ,
    input  wire [15:0] desc_count_i       ,  // informational
    input  wire [7:0]  desc_depth_i       ,
    input  wire        desc_circular_i    ,
    output reg  [15:0] walker_head_o      ,
    output reg  [15:0] walker_current_o   ,
    output reg  [15:0] walker_done_o      ,
    output reg  [15:0] walker_error_id_o  ,
    output reg  [7:0]  cur_opcode_o       ,
    output reg         walker_idle_o      ,
    output reg         walker_running_o   ,
    output reg         walker_frame_done_o,
    // descriptor BRAM port B (registered address, data 2 cycles later)
    output reg  [11:0] desc_rd_addr_o     ,
    input  wire [31:0] desc_rd_data_i     ,
    // publish handshake (to result ring)
    output reg         pub_valid_o        ,
    input  wire        pub_ready_i        ,
    output wire [31:0] pub_bytes_o        ,  // accumulated output bytes
    // error reporting
    output reg         err_evt_desc_o     ,  // pulse -> ERROR_STATUS bit3
    output reg  [7:0]  err_op_o           ,
    output reg  [7:0]  err_desc_id_o
);

    import yolo_csr_pkg::*;

    // ------------------------------------------------------------ --
    // states
    //   W_W0A / W_W0D : word0 address issued / word0 data on port B
    //   W_W14A / W_W14D: word14 address issued / word14 data + decide
    // ------------------------------------------------------------ --
    localparam [2:0] W_IDLE = 3'd0,
                     W_CHK  = 3'd1,
                     W_W0A  = 3'd2,
                     W_W0D  = 3'd3,
                     W_W14A = 3'd4,
                     W_W14D = 3'd5,
                     W_PUB  = 3'd6,
                     W_DONE = 3'd7;

    reg [2:0]  state;
    reg [2:0]  next_state;
    reg [31:0] w0_q;
    reg [31:0] bytes_acc;

    wire [7:0] w0_opcode = w0_q[7:0];
    wire       w0_valid  = w0_q[8];
    wire       w0_last   = w0_q[9];

    assign pub_bytes_o = bytes_acc;

    // effective descriptor depth (0 -> full 128-entry table)
    wire [7:0] eff_depth = (desc_depth_i == 8'd0) ? 8'd128 : desc_depth_i;

    wire [15:0] head_plus1 = walker_head_o + 16'd1;
    wire [15:0] head_next  = (desc_circular_i && (head_plus1[7:0] == eff_depth))
                             ? 16'h0 : head_plus1;

    wire queue_empty = (walker_head_o == desc_tail_i);

    // ------------------------------------------------------------ --
    // FSM block 1 : state register
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state <= W_IDLE;
        end else if (soft_reset_i) begin
            state <= W_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ------------------------------------------------------------ --
    // FSM block 2 : next-state logic
    // ------------------------------------------------------------ --
    always @(*) begin
        next_state = state;
        case (state)
            W_IDLE: begin
                if (start_frame_i && enable_i)
                    next_state = W_CHK;
            end
            W_CHK: begin
                if (stop_i || abort_i)
                    next_state = W_IDLE;
                else if (!queue_empty)
                    next_state = W_W0A;
                else if (frame_end_pending_i)
                    next_state = W_PUB;
            end
            W_W0A: begin
                next_state = W_W0D;
            end
            W_W0D: begin
                next_state = W_W14A;
            end
            W_W14A: begin
                next_state = W_W14D;
            end
            W_W14D: begin
                if (!w0_valid)
                    next_state = W_IDLE;    // invalid descriptor: error
                else if (w0_last)
                    next_state = W_PUB;     // last flag forces publish
                else
                    next_state = W_CHK;
            end
            W_PUB: begin
                if (pub_valid_o && pub_ready_i)
                    next_state = W_DONE;
            end
            W_DONE: begin
                next_state = W_IDLE;
            end
            default: begin
                next_state = W_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------ --
    // FSM block 3 : registered outputs (pulses and status)
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            pub_valid_o        <= 1'b0;
            frame_end_clear_o  <= 1'b0;
            walker_frame_done_o<= 1'b0;
            err_evt_desc_o     <= 1'b0;
            err_op_o           <= 8'h0;
            err_desc_id_o      <= 8'h0;
            walker_idle_o      <= 1'b1;
            walker_running_o   <= 1'b0;
        end else begin
            // defaults: single-beat pulses self-clear
            frame_end_clear_o   <= 1'b0;
            walker_frame_done_o <= 1'b0;
            err_evt_desc_o      <= 1'b0;

            // publish handshake: assert on entry, hold until accepted
            if (state == W_PUB && pub_ready_i)
                pub_valid_o <= 1'b0;
            else if (next_state == W_PUB)
                pub_valid_o <= 1'b1;

            // consume the sticky frame_end flag when it triggers publish
            if (state == W_CHK && next_state == W_PUB)
                frame_end_clear_o <= 1'b1;

            // frame complete
            if (state == W_PUB && next_state == W_DONE)
                walker_frame_done_o <= 1'b1;

            // invalid descriptor -> protocol error
            if (state == W_W14D && !w0_valid) begin
                err_evt_desc_o <= 1'b1;
                err_op_o       <= w0_opcode;
                err_desc_id_o  <= walker_head_o[7:0];
            end

            // status flags track the state register
            walker_idle_o    <= (next_state == W_IDLE);
            walker_running_o <= (next_state != W_IDLE);
        end
    end

    // ------------------------------------------------------------ --
    // datapath: BRAM addressing, accumulation, queue pointers
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            desc_rd_addr_o  <= 12'h0;
            w0_q            <= 32'h0;
            bytes_acc       <= 32'h0;
            walker_head_o   <= 16'h0;
            walker_current_o<= 16'h0;
            walker_done_o   <= 16'h0;
            walker_error_id_o <= 16'h0;
            cur_opcode_o    <= 8'h0;
        end else if (soft_reset_i) begin
            desc_rd_addr_o  <= 12'h0;
            w0_q            <= 32'h0;
            bytes_acc       <= 32'h0;
            walker_head_o   <= 16'h0;
            walker_current_o<= 16'h0;
            walker_done_o   <= 16'h0;
            walker_error_id_o <= 16'h0;
            cur_opcode_o    <= 8'h0;
        end else begin
            // new frame: reset queue pointers and accumulation
            if (state == W_IDLE && next_state == W_CHK) begin
                walker_head_o     <= 16'h0;
                walker_current_o  <= 16'h0;
                walker_done_o     <= 16'h0;
                walker_error_id_o <= 16'h0;
                cur_opcode_o      <= 8'h0;
                bytes_acc         <= 32'h0;
            end

            // issue word0 read when leaving W_CHK with work pending
            if (state == W_CHK && next_state == W_W0A)
                desc_rd_addr_o <= {walker_head_o[6:0], 5'd0};

            // word0 data on port B: capture it, issue word14 read
            if (state == W_W0D) begin
                w0_q           <= desc_rd_data_i;
                desc_rd_addr_o <= {walker_head_o[6:0], 5'd14};
            end

            // word14 data on port B: process the descriptor
            if (state == W_W14D && w0_valid) begin
                bytes_acc         <= bytes_acc + desc_rd_data_i;
                cur_opcode_o      <= w0_opcode;
                walker_current_o  <= walker_head_o;
                walker_done_o     <= walker_done_o + 16'd1;
                walker_head_o     <= head_next;
            end
            if (state == W_W14D && !w0_valid)
                walker_error_id_o <= walker_head_o;
        end
    end

    // doorbell_commit is informational only (tail pointer is polled);
    // keep the port for contract stability
    wire unused_doorbell = doorbell_commit_i;
    wire unused_count    = desc_count_i;

endmodule
