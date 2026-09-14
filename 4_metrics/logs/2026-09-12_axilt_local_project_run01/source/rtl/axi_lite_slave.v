//====================================================================
// File name   : axi_lite_slave.v
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
module axi_lite_slave (
    input  wire        clk          ,
    input  wire        resetn       ,
    input  wire [11:0] s_axi_awaddr ,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata  ,
    input  wire [3:0]  s_axi_wstrb  ,
    input  wire        s_axi_wvalid ,
    output reg         s_axi_wready ,
    output reg  [1:0]  s_axi_bresp  ,
    output reg         s_axi_bvalid ,
    input  wire        s_axi_bready ,
    input  wire [11:0] s_axi_araddr ,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata  ,
    output reg  [1:0]  s_axi_rresp  ,
    output reg         s_axi_rvalid ,
    input  wire        s_axi_rready ,
    output reg         wr_valid     ,
    input  wire        wr_ready     ,
    output reg  [11:0] wr_addr      ,
    output reg  [31:0] wr_data      ,
    output reg  [3:0]  wr_strb      ,
    input  wire        wr_rsp_valid ,
    output reg         wr_rsp_ready ,
    input  wire [1:0]  wr_rsp       ,
    output reg         rd_valid     ,
    input  wire        rd_ready     ,
    output reg  [11:0] rd_addr      ,
    input  wire        rd_rsp_valid ,
    output reg         rd_rsp_ready ,
    input  wire [31:0] rd_data      ,
    input  wire [1:0]  rd_rsp
);
    localparam [2:0] STATE_IDLE = 0, STATE_COLLECT = 1, STATE_REQUEST = 2,
                     STATE_RESPONSE = 3, STATE_SEND = 4;
    reg [2:0] write_state, write_next;
    reg [2:0] read_state, read_next;
    reg aw_full, w_full;

    always @(posedge clk) begin
        if (!resetn) begin
            write_state <= STATE_IDLE;
            read_state <= STATE_IDLE;
        end else begin
            write_state <= write_next;
            read_state <= read_next;
        end
    end

    always @(*) begin
        write_next = write_state;
        case (write_state)
            STATE_IDLE: write_next = STATE_COLLECT;
            STATE_COLLECT: if (aw_full && w_full) write_next = STATE_REQUEST;
            STATE_REQUEST: if (wr_valid && wr_ready) write_next = STATE_RESPONSE;
            STATE_RESPONSE: if (wr_rsp_valid && wr_rsp_ready) write_next = STATE_SEND;
            STATE_SEND: if (s_axi_bvalid && s_axi_bready) write_next = STATE_IDLE;
            default: write_next = STATE_IDLE;
        endcase
        read_next = read_state;
        case (read_state)
            STATE_IDLE: read_next = STATE_COLLECT;
            STATE_COLLECT: if (s_axi_arvalid && s_axi_arready) read_next = STATE_REQUEST;
            STATE_REQUEST: if (rd_valid && rd_ready) read_next = STATE_RESPONSE;
            STATE_RESPONSE: if (rd_rsp_valid && rd_rsp_ready) read_next = STATE_SEND;
            STATE_SEND: if (s_axi_rvalid && s_axi_rready) read_next = STATE_IDLE;
            default: read_next = STATE_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            aw_full <= 0;
            w_full <= 0;
            s_axi_awready <= 0;
            s_axi_wready <= 0;
            s_axi_bvalid <= 0;
            s_axi_bresp <= 0;
            wr_valid <= 0;
            wr_rsp_ready <= 0;
            wr_addr <= 0;
            wr_data <= 0;
            wr_strb <= 0;
        end else begin
            case (write_state)
                STATE_IDLE: begin
                    aw_full <= 0;
                    w_full <= 0;
                    s_axi_awready <= 1;
                    s_axi_wready <= 1;
                    wr_valid <= 0;
                    wr_rsp_ready <= 0;
                    s_axi_bvalid <= 0;
                end
                STATE_COLLECT: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr <= s_axi_awaddr;
                        aw_full <= 1;
                        s_axi_awready <= 0;
                    end
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data <= s_axi_wdata;
                        wr_strb <= s_axi_wstrb;
                        w_full <= 1;
                        s_axi_wready <= 0;
                    end
                    if (aw_full && w_full) wr_valid <= 1;
                end
                STATE_REQUEST: if (wr_valid && wr_ready) begin
                    wr_valid <= 0;
                    wr_rsp_ready <= 1;
                end
                STATE_RESPONSE: if (wr_rsp_valid && wr_rsp_ready) begin
                    wr_rsp_ready <= 0;
                    s_axi_bresp <= wr_rsp;
                    s_axi_bvalid <= 1;
                end
                STATE_SEND: if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
                default: begin
                    s_axi_awready <= 0;
                    s_axi_wready <= 0;
                    s_axi_bvalid <= 0;
                    wr_valid <= 0;
                    wr_rsp_ready <= 0;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            s_axi_arready <= 0;
            s_axi_rvalid <= 0;
            s_axi_rdata <= 0;
            s_axi_rresp <= 0;
            rd_valid <= 0;
            rd_rsp_ready <= 0;
            rd_addr <= 0;
        end else begin
            case (read_state)
                STATE_IDLE: begin
                    s_axi_arready <= 1;
                    s_axi_rvalid <= 0;
                    rd_valid <= 0;
                    rd_rsp_ready <= 0;
                end
                STATE_COLLECT: if (s_axi_arvalid && s_axi_arready) begin
                    rd_addr <= s_axi_araddr;
                    s_axi_arready <= 0;
                    rd_valid <= 1;
                end
                STATE_REQUEST: if (rd_valid && rd_ready) begin
                    rd_valid <= 0;
                    rd_rsp_ready <= 1;
                end
                STATE_RESPONSE: if (rd_rsp_valid && rd_rsp_ready) begin
                    rd_rsp_ready <= 0;
                    s_axi_rdata <= rd_data;
                    s_axi_rresp <= rd_rsp;
                    s_axi_rvalid <= 1;
                end
                STATE_SEND: if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
                default: begin
                    s_axi_arready <= 0;
                    s_axi_rvalid <= 0;
                    rd_valid <= 0;
                    rd_rsp_ready <= 0;
                end
            endcase
        end
    end
endmodule

