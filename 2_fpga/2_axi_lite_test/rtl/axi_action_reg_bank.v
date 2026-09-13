//====================================================================
// File name   : axi_action_reg_bank.v
// Author      : Codex
// Create date : 2026-09-13
// Description : AXI-Lite action command registers and completion state
// Target      : Xilinx Zynq-7020 FPGA
// Revision    : V1.0
//====================================================================

`timescale 1ns / 1ps

module axi_action_reg_bank (
    input  wire        clk           ,
    input  wire        resetn        ,
    input  wire        wr_valid      ,
    output reg         wr_ready      ,
    input  wire [11:0] wr_addr       ,
    input  wire [31:0] wr_data       ,
    input  wire [3:0]  wr_strb       ,
    output reg         wr_rsp_valid  ,
    input  wire        wr_rsp_ready  ,
    output reg  [1:0]  wr_rsp        ,
    input  wire        rd_valid      ,
    output reg         rd_ready      ,
    input  wire [11:0] rd_addr       ,
    output reg         rd_rsp_valid  ,
    input  wire        rd_rsp_ready  ,
    output reg  [31:0] rd_data       ,
    output reg  [1:0]  rd_rsp        ,
    output reg         exec_start    ,
    output reg  [31:0] exec_seq      ,
    output reg  [7:0]  exec_action   ,
    input  wire        exec_done     ,
    input  wire [31:0] exec_result   ,
    input  wire [31:0] exec_error_code,
    input  wire [31:0] exec_frame     ,
    input  wire        uart_busy
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    reg [31:0] scratch;
    reg [7:0]  action_code;
    reg [31:0] cmd_seq;
    reg [31:0] accept_seq;
    reg [31:0] done_seq;
    reg [31:0] last_action;
    reg [31:0] error_code;
    reg [31:0] exec_count;
    reg [31:0] last_frame;
    reg        busy;
    reg        result_valid;
    integer    lane;

    // Write requests and responses are independently buffered. All command
    // fields are snapshotted only on an accepted CONTROL.START write.
    always @(posedge clk) begin
        if (!resetn) begin
            scratch      <= 32'b0;
            action_code  <= 8'b0;
            cmd_seq      <= 32'b0;
            accept_seq   <= 32'b0;
            done_seq     <= 32'b0;
            last_action  <= 32'b0;
            error_code   <= 32'b0;
            exec_count   <= 32'b0;
            last_frame   <= 32'b0;
            busy         <= 1'b0;
            result_valid <= 1'b0;
            exec_start   <= 1'b0;
            exec_seq     <= 32'b0;
            exec_action  <= 8'b0;
            wr_ready     <= 1'b0;
            wr_rsp_valid <= 1'b0;
            wr_rsp       <= RESP_OKAY;
        end else begin
            exec_start <= 1'b0;
            if (!wr_rsp_valid) begin
                wr_ready <= 1'b1;
            end
            if (wr_rsp_valid && wr_rsp_ready) begin
                wr_rsp_valid <= 1'b0;
                wr_ready     <= 1'b1;
            end
            if (exec_done && busy) begin
                last_action  <= exec_result;
                last_frame   <= exec_frame;
                error_code   <= exec_error_code;
                done_seq     <= accept_seq;
                exec_count   <= exec_count + 1'b1;
                busy         <= 1'b0;
                result_valid <= 1'b1;
            end
            if (wr_valid && wr_ready) begin
                wr_ready     <= 1'b0;
                wr_rsp_valid <= 1'b1;
                wr_rsp       <= RESP_OKAY;
                case (wr_addr)
                    12'h00c: begin
                        for (lane = 0; lane < 4; lane = lane + 1) begin
                            if (wr_strb[lane]) begin
                                scratch[lane*8 +: 8] <= wr_data[lane*8 +: 8];
                            end
                        end
                    end
                    12'h010: begin
                        if ((wr_strb != 4'hf) || busy || result_valid ||
                            (wr_data[31:8] != 24'b0) || (wr_data[7:0] > 8'h07)) begin
                            wr_rsp <= RESP_SLVERR;
                        end else begin
                            action_code <= wr_data[7:0];
                        end
                    end
                    12'h014: begin
                        if ((wr_strb != 4'hf) || busy || result_valid) begin
                            wr_rsp <= RESP_SLVERR;
                        end else begin
                            cmd_seq <= wr_data;
                        end
                    end
                    12'h018: begin
                        if (wr_strb != 4'hf) begin
                            wr_rsp <= RESP_SLVERR;
                        end else if (wr_data == 32'h00000001) begin
                            if (busy || result_valid || (cmd_seq == 32'b0) ||
                                (cmd_seq <= accept_seq)) begin
                                wr_rsp <= RESP_SLVERR;
                            end else begin
                                exec_seq    <= cmd_seq;
                                exec_action <= action_code;
                                accept_seq  <= cmd_seq;
                                error_code  <= 32'b0;
                                busy        <= 1'b1;
                                exec_start  <= 1'b1;
                            end
                        end else if (wr_data == 32'h00000002) begin
                            if (!result_valid || busy) begin
                                wr_rsp <= RESP_SLVERR;
                            end else begin
                                result_valid <= 1'b0;
                            end
                        end else begin
                            wr_rsp <= RESP_SLVERR;
                        end
                    end
                    default: begin
                        wr_rsp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

    // A simultaneous read and write of SCRATCH returns the pre-write value,
    // matching the independently validated register-stage contract.
    always @(posedge clk) begin
        if (!resetn) begin
            rd_ready     <= 1'b0;
            rd_rsp_valid <= 1'b0;
            rd_data      <= 32'b0;
            rd_rsp       <= RESP_OKAY;
        end else begin
            if (!rd_rsp_valid) begin
                rd_ready <= 1'b1;
            end
            if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 1'b0;
                rd_ready     <= 1'b1;
            end
            if (rd_valid && rd_ready) begin
                rd_ready     <= 1'b0;
                rd_rsp_valid <= 1'b1;
                rd_rsp       <= RESP_OKAY;
                case (rd_addr)
                    12'h000: rd_data <= 32'h4143544c;
                    12'h004: rd_data <= 32'h00010000;
                    12'h008: rd_data <= 32'h00000007;
                    12'h00c: rd_data <= scratch;
                    12'h010: rd_data <= {24'b0, action_code};
                    12'h014: rd_data <= cmd_seq;
                    12'h018: rd_data <= 32'b0;
                    12'h01c: rd_data <= {
                        27'b0, uart_busy, 1'b0, result_valid, busy, (!busy && !result_valid)};
                    12'h020: rd_data <= accept_seq;
                    12'h024: rd_data <= done_seq;
                    12'h028: rd_data <= last_action;
                    12'h02c: rd_data <= error_code;
                    12'h030: rd_data <= exec_count;
                    12'h034: rd_data <= last_frame;
                    // bit0=COM4 present; bit4=TX busy; BLE absent in v1.
                    12'h038: rd_data <= {27'b0, uart_busy, 3'b0, 1'b1};
                    12'h03c: rd_data <= exec_count;
                    default: begin
                        rd_data <= 32'b0;
                        rd_rsp  <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

endmodule
