/************************************************************************
 * File Name       : yolo_axi_lite_slave.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_axi_lite_slave
 * Description     : AXI4-Lite slave front-end for the YOLO CSR
 *                   subsystem.
 *                   - independent AW and W holding registers (AW and W
 *                     may arrive on different beats; the write commits
 *                     only when both have been captured) [design doc
 *                     section 2]
 *                   - at most one outstanding read and one outstanding
 *                     write
 *                   - 4-byte alignment enforced, misaligned -> SLVERR
 *                   - internal request/response channels tolerate any
 *                     response latency (table read = 1 cycle)
 *                   This module has no FSM: the holding-register
 *                   handshake is dataflow logic, so the three-block
 *                   FSM template does not apply.
 * Dependencies    : None
 * Revision History:
 *   - V1.1 (2026-09-18) by LSL : Coding-standards refactor: EES-331
 *                                header, _i/_o port suffixes (AXI
 *                                interface names preserved for Block
 *                                Design interface inference).
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

module yolo_axi_lite_slave (
    input  wire        clk_i           ,
    input  wire        rst_n           ,
    // AXI4-Lite slave interface (names fixed by AXI/BD convention)
    input  wire [31:0] s_axi_awaddr    ,
    input  wire [2:0]  s_axi_awprot    ,
    input  wire        s_axi_awvalid   ,
    output reg         s_axi_awready   ,
    input  wire [31:0] s_axi_wdata     ,
    input  wire [3:0]  s_axi_wstrb     ,
    input  wire        s_axi_wvalid    ,
    output reg         s_axi_wready    ,
    output reg  [1:0]  s_axi_bresp     ,
    output reg         s_axi_bvalid    ,
    input  wire        s_axi_bready    ,
    input  wire [31:0] s_axi_araddr    ,
    input  wire [2:0]  s_axi_arprot    ,
    input  wire        s_axi_arvalid   ,
    output reg         s_axi_arready   ,
    output reg  [31:0] s_axi_rdata     ,
    output reg  [1:0]  s_axi_rresp     ,
    output reg         s_axi_rvalid    ,
    input  wire        s_axi_rready    ,
    // internal write request (registered outputs, wr_ready assumed 1)
    output reg         wr_valid_o      ,
    output wire [15:0] wr_addr_o       ,
    output wire [31:0] wr_data_o       ,
    output wire [3:0]  wr_strb_o       ,
    input  wire [1:0]  wr_rsp_i        ,
    // internal read request
    output reg         rd_valid_o      ,
    output wire [15:0] rd_addr_o       ,
    input  wire        rd_ack_i        ,
    input  wire [31:0] rd_data_i       ,
    input  wire [1:0]  rd_rsp_i        ,
    // sticky error event: AXI-Lite protocol violation (misaligned /
    // unmapped address), routed to ERROR_STATUS bit0
    output reg         err_axi_event_o
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // unused AXI protection inputs
    wire unused_prot = &{s_axi_awprot, s_axi_arprot};

    // ---------------- write channel holding registers -------------- --
    reg        aw_full    ;
    reg [15:0] aw_addr_q  ;
    reg        w_full     ;
    reg [31:0] w_data_q   ;
    reg [3:0]  w_strb_q   ;
    reg        b_busy     ;

    wire wr_fire = wr_valid_o;          // wr_ready is always 1
    wire addr_misaligned_w = (aw_addr_q[1:0] != 2'b00);
    wire addr_misaligned_r = (rd_addr_o[1:0] != 2'b00);

    always @(posedge clk_i) begin
        if (!rst_n) begin
            aw_full        <= 1'b0;
            aw_addr_q      <= 16'h0;
            w_full         <= 1'b0;
            w_data_q       <= 32'h0;
            w_strb_q       <= 4'h0;
            b_busy         <= 1'b0;
            s_axi_awready  <= 1'b1;
            s_axi_wready   <= 1'b1;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= RESP_OKAY;
            wr_valid_o     <= 1'b0;
            err_axi_event_o<= 1'b0;
        end else begin
            err_axi_event_o <= 1'b0;
            // -------- independent AW / W capture -------------------- --
            if (s_axi_awvalid && s_axi_awready) begin
                aw_addr_q      <= s_axi_awaddr[15:0];
                aw_full        <= 1'b1;
                s_axi_awready  <= 1'b0;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_data_q       <= s_axi_wdata;
                w_strb_q       <= s_axi_wstrb;
                w_full         <= 1'b1;
                s_axi_wready   <= 1'b0;
            end
            // -------- issue internal write when both captured ------- --
            if (!wr_valid_o && !b_busy && aw_full && w_full) begin
                wr_valid_o <= 1'b1;
            end else if (wr_fire) begin
                // commit accepted this beat: capture response, raise B
                wr_valid_o     <= 1'b0;
                aw_full        <= 1'b0;
                w_full         <= 1'b0;
                b_busy         <= 1'b1;
                s_axi_bresp    <= addr_misaligned_w ? RESP_SLVERR : wr_rsp_i;
                s_axi_bvalid   <= 1'b1;
                if (addr_misaligned_w) err_axi_event_o <= 1'b1;
            end
            // -------- B channel handshake ---------------------------- --
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                b_busy        <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    assign wr_addr_o = aw_addr_q;
    assign wr_data_o = w_data_q ;
    assign wr_strb_o = w_strb_q ;

    // ---------------- read channel ---------------------------------- --
    reg        ar_full;
    reg [15:0] ar_addr_q;

    always @(posedge clk_i) begin
        if (!rst_n) begin
            ar_full       <= 1'b0;
            ar_addr_q     <= 16'h0;
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= RESP_OKAY;
            rd_valid_o    <= 1'b0;
        end else begin
            // -------- AR capture ------------------------------------- --
            if (s_axi_arvalid && s_axi_arready) begin
                ar_addr_q     <= s_axi_araddr[15:0];
                ar_full       <= 1'b1;
                s_axi_arready <= 1'b0;
            end
            // -------- issue internal read ---------------------------- --
            if (!rd_valid_o && !s_axi_rvalid && ar_full) begin
                rd_valid_o <= 1'b1;
            end else if (rd_valid_o && rd_ack_i) begin
                rd_valid_o    <= 1'b0;
                ar_full       <= 1'b0;
                s_axi_rdata   <= rd_data_i;
                s_axi_rresp   <= addr_misaligned_r ? RESP_SLVERR : rd_rsp_i;
                s_axi_rvalid  <= 1'b1;
            end
            // -------- R channel handshake ---------------------------- --
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

    assign rd_addr_o = ar_addr_q;

endmodule
