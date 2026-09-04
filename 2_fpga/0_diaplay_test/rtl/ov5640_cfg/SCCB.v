//SCCB 写数据时序
module sccb_protocol
#(
    parameter OV5640_W   = 8'h78  ,
    parameter OV5640_R   = 8'H79  ,
    parameter CLK_DIV    = 9'D500 , //SCCB时钟频率 100KHZ
    parameter PACK_DELAY = 75
)
(
    input  wire        sys_clk        ,
    input  wire        sys_rst_n      ,
    
    //写数据
    input  wire [15:0] reg_addr       ,
    input  wire [7:0]  w_data         ,
    input  wire        w_en           ,
    input  wire [7:0]  reg_num        ,//需要配置的寄存器数量 270 300
    output wire        w_done         ,
    output reg         sccb_cfg_done  ,
    
    //读数据
    input  wire        r_en           ,
    output reg   [7:0] r_data         ,
    output wire        r_done         ,
    
    //sccb interface
    output reg         sck            ,
    inout  wire        sda        
);
localparam IDLE      = 4'd0,
           STA_1     = 4'd1,
           DVI_W     = 4'd2,
           REG_ADDRH = 4'd3,
           REG_ADDRL = 4'd4,
           
           STA_2     = 4'd5,
           DVI_R     = 4'd6,
           R_DATA    = 4'd7,
           
           W_DATA    = 4'd8,
           END1      = 4'd9,  //读数据第一次的停止位
           END2      = 4'd10, //最后的停止位
           STOP      = 4'd11;
           
//计数器分段
localparam Q_DELAY = CLK_DIV>>2; //500/4
localparam M_DELAY = CLK_DIV>>1; //500/2
reg [3:0] state,next_state;
reg [9:0] cnt_clk;//clk_div 0-499
reg [3:0] cnt_bit;//0-8 9bits
//reg [10:0] wr_done_cnt;//配置完成的寄存器个数计数
wire [7:0] reg_addr_h;//寄存器地址高八位
wire [7:0] reg_addr_l;//寄存器地址低八位
reg [6:0] cnt_delay;
//读数据的寄存器
reg [7:0] data_reg;
reg [7:0] cnt_reg_wr;//计数对于寄存器完成的写操作次数

assign reg_addr_h = reg_addr[15:8];
assign reg_addr_l = reg_addr[7:0];
//3-state
reg sda_out;
wire sda_in;
wire sda_en;//1:in  0:out
assign sda = (sda_en == 0)?sda_out:'bz;
assign sda_en = ((state == DVI_W     && cnt_bit == 8)||
                 (state == DVI_R     && cnt_bit == 8)||
                 (state == REG_ADDRH && cnt_bit == 8)||
                 (state == REG_ADDRL && cnt_bit == 8)||
                 (state == W_DATA    && cnt_bit == 8)||
                 (state == R_DATA    && cnt_bit <  8)
                 )?1:0;
assign sda_in = sda;

always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_delay <= 0;
    else if(state == STOP)begin
        if(cnt_delay == PACK_DELAY-1)
            cnt_delay <= 0;
        else
            cnt_delay <= cnt_delay+1;
    end
    else
        cnt_delay <= 0;

//FSM                  
always@(posedge sys_clk)
    if(!sys_rst_n)
        state <= IDLE;
    else 
        state <= next_state;

always@(*)
    case(state)
    IDLE     :
            if(w_en || r_en)
                next_state = STA_1;
            else
                next_state = state;
    STA_1    :
            if(cnt_clk == CLK_DIV-1)
                next_state = DVI_W;
            else
                next_state = state;
    DVI_W    :
            if(cnt_clk == CLK_DIV-1 && cnt_bit == 8)
                next_state = REG_ADDRH;
            else
                next_state = state;
    REG_ADDRH:
            if(cnt_clk == CLK_DIV-1 && cnt_bit == 8)
                next_state = REG_ADDRL;
            else
                next_state = state;
    REG_ADDRL:
            if(cnt_clk == CLK_DIV-1 && cnt_bit == 8)begin
                if(w_en == 1)
                    next_state = W_DATA;
                else if(r_en == 1) 
                    next_state = END1;
                else
                    next_state = IDLE;
            end
            else
                next_state = state;
    STA_2    :
            if(cnt_clk == CLK_DIV-1)
                next_state = DVI_R; 
            else
                next_state = state;
    DVI_R    :
            if(cnt_clk == CLK_DIV-1 && cnt_bit == 8)
                next_state = R_DATA;
            else
                next_state = state;
    R_DATA   :
            if(cnt_clk == CLK_DIV-1 && cnt_bit == 8)
                next_state = END2;
            else
                next_state = state;
    
    W_DATA   :
            if(cnt_clk == CLK_DIV-1 && cnt_bit == 8)
                next_state = END2;
            else
                next_state = state;
    END1      :begin
            if(cnt_clk == CLK_DIV-1)
                next_state = STA_2;
            else
                next_state = state;
    end
    END2      :
            if(cnt_clk == CLK_DIV-1)begin
                next_state = STOP;
            end
            else
                next_state = state;
    STOP    :
            if(cnt_delay == PACK_DELAY-1)
                next_state = IDLE;
            else
                next_state = state;
    default:next_state = IDLE;
    endcase
//状态输出
always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_clk <= 0;
    else if(state != IDLE)begin
        if(cnt_clk == CLK_DIV-1)
            cnt_clk <= 0;
        else
            cnt_clk <= cnt_clk +1;
    end
    else
        cnt_clk <= 0;
always@(posedge sys_clk)
    if(!sys_rst_n)
        sck <= 1;
    else begin
    case(state)
    STA_1,STA_2    :  
        if(cnt_clk <= Q_DELAY+M_DELAY-1)
            sck <= 1;
        else
            sck <= 0;
    END1      :
        if(cnt_clk <= Q_DELAY-1)
            sck <= 0;
        else
            sck <= 1;
    END2      :
        if(cnt_clk <= Q_DELAY-1)
            sck <= 0;
        else
            sck <= 1;
    DVI_W,REG_ADDRH,REG_ADDRL,W_DATA,DVI_R,R_DATA:
        if(cnt_clk == Q_DELAY-1 || cnt_clk == Q_DELAY+M_DELAY-1)
            sck <= ~sck;
        else
            sck <= sck;
    default:sck <= 1;
    endcase
    end
always@(posedge sys_clk)
    if(!sys_rst_n)
        sda_out <= 1;
    else begin
        case(state)    
        STA_1    :if(cnt_clk <= Q_DELAY-1)
                    sda_out <= 1;
                  else
                    sda_out <= 0;
        END1,END2:if(cnt_clk <= M_DELAY+Q_DELAY-1)
                    sda_out <= 0;
                  else
                    sda_out <= 1;
        DVI_W    : //cnt_bit 0-8
                if(cnt_bit < 8)
                    sda_out <= OV5640_W[7-cnt_bit]; //OV5640_W = 8'h78
                else
                    sda_out <= 1;
        DVI_R    :
                if(cnt_bit < 8)
                    sda_out <= OV5640_R[7-cnt_bit]; //OV5640_R = 8'h79
                else
                    sda_out <= 1;
        REG_ADDRH:
                if(cnt_bit < 8)
                    sda_out <= reg_addr_h[7-cnt_bit];
                else
                    sda_out <= 1;
        REG_ADDRL:
                if(cnt_bit < 8)
                    sda_out <= reg_addr_l[7-cnt_bit];
                else
                    sda_out <= 1;
        W_DATA   :
                if(cnt_bit < 8)
                    sda_out <= w_data[7-cnt_bit];
                else
                    sda_out <= 1;
        
        default:sda_out <= 1;
        endcase
    end
always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_bit <= 0;
    else begin
    case(state)
    DVI_W    ,
    DVI_R    ,
    R_DATA   ,
    REG_ADDRH,
    REG_ADDRL,
    W_DATA   :begin
            if(cnt_clk == CLK_DIV-1)begin
                if(cnt_bit == 8)
                    cnt_bit <= 0;
                else
                    cnt_bit <= cnt_bit+1;
            end
    end
    default:cnt_bit <= 0;
    endcase    
    end
always@(posedge sys_clk)
    if(!sys_rst_n)
        data_reg <= 0;
    else if(state == R_DATA && cnt_bit < 8)
        data_reg[7-cnt_bit] <= sda_in;
    else
        data_reg <= data_reg;
always@(posedge sys_clk)
    if(!sys_rst_n)
        r_data <= 0;
    else if(state == R_DATA && cnt_bit == 8)
        r_data <= data_reg;
    else
        r_data <= r_data;
assign r_done = (state == R_DATA && cnt_bit == 8 && cnt_clk == CLK_DIV-1)?1:0;
assign w_done = (state == W_DATA && cnt_bit == 8 && cnt_clk == CLK_DIV-1)?1:0;//写完一个寄存器 拉高一次
always@(posedge sys_clk)
    if(!sys_rst_n)begin
        cnt_reg_wr <= 0;
        sccb_cfg_done <= 0;
    end
    else if(w_done)begin
        if(cnt_reg_wr == reg_num-1)begin
            cnt_reg_wr <= 0;
            sccb_cfg_done <= 1;
        end
        else begin
            cnt_reg_wr <= cnt_reg_wr+1;
            sccb_cfg_done <= 0;
        end
    end
    else
        sccb_cfg_done <= sccb_cfg_done;
        
endmodule