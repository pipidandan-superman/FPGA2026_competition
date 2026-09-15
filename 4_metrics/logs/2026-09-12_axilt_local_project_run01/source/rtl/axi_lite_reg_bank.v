//====================================================================
// File name   : axi_lite_reg_bank.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
module axi_lite_reg_bank (
    input  wire        clk         ,
    input  wire        resetn      ,
    input  wire        wr_valid    ,
    output reg         wr_ready    ,
    input  wire [11:0] wr_addr     ,
    input  wire [31:0] wr_data     ,
    input  wire [3:0]  wr_strb     ,
    output reg         wr_rsp_valid,
    input  wire        wr_rsp_ready,
    output reg  [1:0]  wr_rsp      ,
    input  wire        rd_valid    ,
    output reg         rd_ready    ,
    input  wire [11:0] rd_addr     ,
    output reg         rd_rsp_valid,
    input  wire        rd_rsp_ready,
    output reg  [31:0] rd_data     ,
    output reg  [1:0]  rd_rsp      ,
    output reg         exec_start  ,
    output reg  [31:0] exec_input  ,
    input  wire        exec_done   ,
    input  wire [31:0] exec_result
);
    localparam [1:0] RESP_OKAY = 2'b00, RESP_SLVERR = 2'b10;
    reg [31:0] scratch, test_input, cmd_seq, accept_seq, done_seq;
    reg [31:0] test_result, exec_count;
    reg busy, result_valid;
    integer lane;

    // Independent buffered read and write responses. Nonblocking assignments
    // make a simultaneous read of a written register return its previous value.
    always @(posedge clk) begin
        if (!resetn) begin
            scratch <= 0;
            test_input <= 0;
            cmd_seq <= 0;
            accept_seq <= 0;
            done_seq <= 0;
            test_result <= 0;
            exec_count <= 0;
            busy <= 0;
            result_valid <= 0;
            exec_start <= 0;
            exec_input <= 0;
            wr_ready <= 0;
            wr_rsp_valid <= 0;
            wr_rsp <= RESP_OKAY;
        end else begin
            exec_start <= 0;
            if (!wr_rsp_valid) wr_ready <= 1;
            if (wr_rsp_valid && wr_rsp_ready) begin
                wr_rsp_valid <= 0;
                wr_ready <= 1;
            end
            if (exec_done && busy) begin
                test_result <= exec_result;
                done_seq <= accept_seq;
                exec_count <= exec_count + 1'b1;
                busy <= 0;
                result_valid <= 1;
            end
            if (wr_valid && wr_ready) begin
                wr_ready <= 0;
                wr_rsp_valid <= 1;
                wr_rsp <= RESP_OKAY;
                case (wr_addr)
                    12'h00c, 12'h010: begin
                        for (lane = 0; lane < 4; lane = lane + 1) begin
                            if (wr_strb[lane]) begin
                                if (wr_addr == 12'h00c)
                                    scratch[lane*8 +: 8] <= wr_data[lane*8 +: 8];
                                else
                                    test_input[lane*8 +: 8] <= wr_data[lane*8 +: 8];
                            end
                        end
                    end
                    12'h014: begin
                        if (wr_strb != 4'hf || busy || result_valid) wr_rsp <= RESP_SLVERR;
                        else cmd_seq <= wr_data;
                    end
                    12'h018: begin
                        if (wr_strb != 4'hf) wr_rsp <= RESP_SLVERR;
                        else if (wr_data == 32'h1) begin
                            if (busy || result_valid || cmd_seq == 0 || cmd_seq <= accept_seq)
                                wr_rsp <= RESP_SLVERR;
                            else begin
                                exec_input <= test_input;
                                accept_seq <= cmd_seq;
                                busy <= 1;
                                exec_start <= 1;
                            end
                        end else if (wr_data == 32'h2) begin
                            if (!result_valid || busy) wr_rsp <= RESP_SLVERR;
                            else result_valid <= 0;
                        end else wr_rsp <= RESP_SLVERR;
                    end
                    default: wr_rsp <= RESP_SLVERR;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            rd_ready <= 0;
            rd_rsp_valid <= 0;
            rd_data <= 0;
            rd_rsp <= RESP_OKAY;
        end else begin
            if (!rd_rsp_valid) rd_ready <= 1;
            if (rd_rsp_valid && rd_rsp_ready) begin
                rd_rsp_valid <= 0;
                rd_ready <= 1;
            end
            if (rd_valid && rd_ready) begin
                rd_ready <= 0;
                rd_rsp_valid <= 1;
                rd_rsp <= RESP_OKAY;
                case (rd_addr)
                    12'h000: rd_data <= 32'h41584c54; // AXLT, not the BLE ABI.
                    12'h004: rd_data <= 32'h00010000;
                    12'h008: rd_data <= 32'h00000001; // Register executor only.
                    12'h00c: rd_data <= scratch;
                    12'h010: rd_data <= test_input;
                    12'h014: rd_data <= cmd_seq;
                    12'h018: rd_data <= 0;
                    12'h01c: rd_data <= {29'b0, result_valid, busy, (!busy && !result_valid)};
                    12'h020: rd_data <= accept_seq;
                    12'h024: rd_data <= done_seq;
                    12'h028: rd_data <= test_result;
                    12'h02c: rd_data <= 0; // No executor errors in register-only stage.
                    12'h030: rd_data <= exec_count;
                    default: begin
                        rd_data <= 0;
                        rd_rsp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end
endmodule

