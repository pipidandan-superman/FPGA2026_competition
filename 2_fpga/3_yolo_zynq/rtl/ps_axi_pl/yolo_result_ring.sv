/************************************************************************
 * File Name       : yolo_result_ring.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_result_ring
 * Description     : Result metadata ring: 32 entries x 16 words stored
 *                   in a Block Memory Generator IP (yolo_ring_table).
 *                   The walker publishes one entry per frame (frame
 *                   id, seq, head base/bytes, quant profile); PS reads
 *                   entries through the 0x6000 window and acknowledges
 *                   via RESULT_ACK (consume/drop) which advances the
 *                   tail pointer owned by the register file.  Publish
 *                   on a full ring raises the overflow event and drops
 *                   the entry (seq still advances so PS can detect the
 *                   gap).  Acknowledge on an empty ring raises a
 *                   protocol error event.
 * Dependencies    : yolo_csr_pkg.sv, yolo_ring_table.sv (BMG IP)
 * Revision History:
 *   - V2.0 (2026-09-18) by LSL : Three-block FSM refactor; table write
 *                                port internalised; write-enable driven
 *                                one cycle early via next_state.
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_result_ring (
    input  wire        clk_i             ,
    input  wire        rst_n             ,
    input  wire        soft_reset_i      ,
    // publish port (from descriptor walker / register file payload)
    input  wire        pub_valid_i       ,
    output wire        pub_ready_o       ,
    input  wire [31:0] pub_frame_id_i    ,
    input  wire [63:0] pub_head_base_i   ,
    input  wire [31:0] pub_head_bytes_i  ,
    input  wire [7:0]  pub_quant_profile_i,
    input  wire [7:0]  pub_stride_mask_i ,
    output reg         pub_done_evt_o    ,  // pulse: entry fully written
    output reg         pub_overflow_evt_o,  // pulse: ring full, entry dropped
    // PS acknowledge (pulses from register file)
    input  wire [7:0]  tail_ptr_i        ,
    input  wire        ack_consume_i     ,
    input  wire        ack_drop_i        ,
    output reg         ack_err_evt_o     ,  // ack on empty ring
    // CSR visible status
    output reg  [7:0]  head_ptr_o        ,
    output wire        not_empty_o       ,
    output reg  [31:0] seq_o             ,
    output reg  [31:0] last_frame_id_o   ,
    output reg  [31:0] last_head_bytes_o ,
    // AXI aperture window (PS read only)
    input  wire [8:0]  win_addr_i        ,
    output wire [31:0] win_data_o
);

    import yolo_csr_pkg::*;

    // ------------------------------------------------------------ --
    // states
    // ------------------------------------------------------------ --
    localparam [1:0] R_IDLE  = 2'd0,
                     R_WRITE = 2'd1,
                     R_DONE  = 2'd2;

    reg [1:0]  state;
    reg [1:0]  next_state;
    reg [3:0]  cnt;
    reg [31:0] fid_q;
    reg [31:0] seq_q;      // seq value written into this entry
    reg [63:0] base_q;
    reg [31:0] bytes_q;
    reg [7:0]  prof_q;
    reg [7:0]  smask_q;

    wire ring_full = ((head_ptr_o[4:0] + 5'd1) == tail_ptr_i[4:0]);
    assign not_empty_o = (head_ptr_o[4:0] != tail_ptr_i[4:0]);
    assign pub_ready_o = (state == R_IDLE);

    // ------------------------------------------------------------ --
    // FSM block 1 : state register
    // ------------------------------------------------------------ --
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            state <= R_IDLE;
        end else if (soft_reset_i) begin
            state <= R_IDLE;
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
            R_IDLE: begin
                if (pub_valid_i && !ring_full)
                    next_state = R_WRITE;
                // full ring: drop the entry, stay idle (overflow event
                // is raised by the output block)
            end
            R_WRITE: begin
                if (cnt == 4'd15)
                    next_state = R_DONE;
            end
            R_DONE: begin
                next_state = R_IDLE;
            end
            default: begin
                next_state = R_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------ --
    // FSM block 3 : registered outputs
    //   table write enable/address are driven one cycle ahead through
    //   next_state so the first BRAM write lands on the first R_WRITE
    //   beat; data is selected combinationally by the write counter.
    // ------------------------------------------------------------ --
    reg        tbl_we;
    reg [3:0]  tbl_wstrb;
    reg [8:0]  tbl_waddr;
    reg [31:0] wdata_mux;

    always @(*) begin
        case (cnt)
            4'd0   : wdata_mux = fid_q;                          // w0 frame id
            4'd1   : wdata_mux = seq_q;                          // w1 seq
            4'd2   : wdata_mux = base_q[31:0];                   // w2 base lo
            4'd3   : wdata_mux = base_q[63:32];                  // w3 base hi
            4'd4   : wdata_mux = bytes_q;                        // w4 bytes
            4'd5   : wdata_mux = 32'h0;                          // w5 shape 0
            4'd6   : wdata_mux = 32'h0;                          // w6 shape 1
            4'd7   : wdata_mux = 32'h0;                          // w7 shape 2
            4'd8   : wdata_mux = {8'h0, smask_q, 8'h0, prof_q};  // w8 profile
            4'd9   : wdata_mux = 32'h0;                          // w9 crc
            4'd10  : wdata_mux = 32'h0000_0011;                  // w10 valid+ps
            default: wdata_mux = 32'h0;                          // w11..w15
        endcase
    end

    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            pub_done_evt_o    <= 1'b0;
            pub_overflow_evt_o<= 1'b0;
            ack_err_evt_o     <= 1'b0;
            tbl_we            <= 1'b0;
            tbl_wstrb         <= 4'h0;
            tbl_waddr         <= 9'h0;
            head_ptr_o        <= 8'h0;
            seq_o             <= 32'h0;
            last_frame_id_o   <= 32'h0;
            last_head_bytes_o <= 32'h0;
            fid_q             <= 32'h0;
            seq_q             <= 32'h0;
            base_q            <= 64'h0;
            bytes_q           <= 32'h0;
            prof_q            <= 8'h0;
            smask_q           <= 8'h0;
            cnt               <= 4'h0;
        end else begin
            // defaults: single-beat events and write strobe self-clear
            pub_done_evt_o     <= 1'b0;
            pub_overflow_evt_o <= 1'b0;
            ack_err_evt_o      <= 1'b0;
            tbl_we             <= 1'b0;

            // ack on empty ring is a protocol error (any state)
            if ((ack_consume_i || ack_drop_i) && !not_empty_o)
                ack_err_evt_o <= 1'b1;

            // publish accepted: latch payload, start the write burst
            if (state == R_IDLE && next_state == R_WRITE) begin
                fid_q             <= pub_frame_id_i;
                seq_q             <= seq_o + 32'd1;
                base_q            <= pub_head_base_i;
                bytes_q           <= pub_head_bytes_i;
                prof_q            <= pub_quant_profile_i;
                smask_q           <= pub_stride_mask_i;
                cnt               <= 4'h0;
                seq_o             <= seq_o + 32'd1;
                last_frame_id_o   <= pub_frame_id_i;
                last_head_bytes_o <= pub_head_bytes_i;
                tbl_we            <= 1'b1;
                tbl_wstrb         <= 4'hF;
                tbl_waddr         <= {head_ptr_o[4:0], 4'h0};
            end

            // publish on a full ring: drop, but report
            if (state == R_IDLE && pub_valid_i && ring_full) begin
                pub_overflow_evt_o <= 1'b1;
                seq_o              <= seq_o + 32'd1;  // gap is visible to PS
                last_frame_id_o    <= pub_frame_id_i;
                last_head_bytes_o  <= pub_head_bytes_i;
            end

            // burst write beats: address leads the counter by one
            if (state == R_WRITE) begin
                tbl_we    <= 1'b1;
                tbl_wstrb <= 4'hF;
                tbl_waddr <= {head_ptr_o[4:0], cnt + 4'd1};
                cnt       <= cnt + 4'd1;
            end

            // entry complete: advance head, notify
            if (state == R_DONE) begin
                head_ptr_o     <= head_ptr_o + 8'd1;
                pub_done_evt_o <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------ --
    // ring storage: BMG IP, port A = PS read window, port B = publisher
    // ------------------------------------------------------------ --
    wire [31:0] tbl_wdata = wdata_mux;

    yolo_ring_table u_ring_tbl (
        .clk_i     (clk_i),
        .a_raddr_i (win_addr_i),
        .a_rdata_o (win_data_o),
        .b_we_i    (tbl_we),
        .b_wstrb_i (tbl_wstrb),
        .b_waddr_i (tbl_waddr),
        .b_wdata_i (tbl_wdata)
    );

endmodule
