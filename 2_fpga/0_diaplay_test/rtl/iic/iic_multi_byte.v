//适配多字节的底层协议
//iic 协议实现多字节读写
module iic_multi_byte
#(
    parameter DEVICE_WR_ADDR = 7'b1010000,
    parameter IIC_SPEED      = 150         //50Mhz 分频系数 333.333Khz < 400khz
)
(
    input  wire       sys_clk               ,
    input  wire       sys_rst_n             ,
                        
    input  wire       iic_start             ,
    input  wire [1:0] iic_we                ,//iic 读=1/写=0
    input  wire [4:0] data_num              ,//1-16
    input  wire [7:0] iic_addr              ,
    input  wire [7:0] iic_wr_data           ,
    output reg        iic_wr_data_request   ,//new 适配多字节写数据更新
    output reg  [7:0] iic_rd_data           ,
    output reg        iic_rd_data_valid     ,
    output wire       iic_done              ,
                
    output reg        scl                   ,
    inout  wire       sda                       
);
wire [10:0] IIC_SPPED_DIV4,IIC_SPPED_DIV2;
assign IIC_SPPED_DIV4 = IIC_SPEED>>2;
assign IIC_SPPED_DIV2 = IIC_SPEED>>1;
localparam  IIC_WR_CMD = {DEVICE_WR_ADDR,1'b0};
localparam  IIC_RD_CMD = {DEVICE_WR_ADDR,1'b1};
localparam  DELAY_ERROR = 50_000_000;//1s

reg [7:0] iic_rd_data_reg;
localparam  IDLE        = 4'd0 ,
            START       = 4'd1 ,
            DEVICE_WR   = 4'd2 ,
            ACK1        = 4'd3 ,
            ADDR        = 4'd4 ,
            ACK2        = 4'd5 ,
                               
            //写数据           
            WR_DATA     = 4'd6 ,
            //ACK3        = 4'd7 ,
            //读数据
            START2      = 4'd8 ,
            DEVICE_RD   = 4'd9 ,
            ACK4        = 4'd10,
            RD_DATA     = 4'd11,
            //NO_ACK      = 4'd12,
            
            STOP        = 4'd13,
            END         = 4'd14,
            ERROR       = 4'd15;
reg [3:0] state,next_state;
reg [15:0] cnt_scl;//单比特
reg [3:0] cnt_bit;//0-8
reg [27:0] cnt_error;
reg [3:0] cnt_num;//0-15
reg ack_reg;//寄存采集到的ack信号（从机输入的信号）

//三态门的控制
//sda sda_out sda_in=sda 
//sda_en == 1 输出  sda_en == 0 输入
wire sda_in;
reg sda_out;
wire sda_en;
assign sda_en = (state == ACK1 || 
                 state == ACK2 || 
                 state == ACK4 || 
                 (state == WR_DATA && cnt_bit == 8)||
                 (state == RD_DATA && cnt_bit <= 7))?0:1;
assign sda_in = sda;
assign sda = (sda_en == 1)?sda_out:1'bz;

always@(posedge sys_clk)
    if(!sys_rst_n)
        state <= IDLE;
    else
        state <= next_state;
always@(*)
    case(state)
    IDLE   :if(iic_start)
                next_state = START;
            else
                next_state = state;
    START  :if(cnt_scl == IIC_SPEED-1)
                next_state = DEVICE_WR;
            else
                next_state = state;
    DEVICE_WR :if(cnt_scl == IIC_SPEED-1 && cnt_bit == 7)
                next_state = ACK1;
            else
                next_state = state;
    ACK1   :if(cnt_scl == IIC_SPEED-1)begin
                if(ack_reg == 0)
                    next_state = ADDR;
                else 
                    next_state = ERROR;
            end
            else
                next_state = state;
    ADDR   :if(cnt_scl == IIC_SPEED-1 && cnt_bit == 7)
                next_state = ACK2;
            else
                next_state = state;
    ACK2   :if(cnt_scl == IIC_SPEED-1)begin
                if(ack_reg == 0)begin
                    if(iic_we == 2'b00)
                        next_state = WR_DATA; //写数据
                    else if(iic_we == 2'b01)
                        next_state = START2;  //读数据 
                    else
                        next_state = ERROR;
                end
                else 
                    next_state = ERROR;
            end
            else
                next_state = state;
    WR_DATA:if(cnt_scl == IIC_SPEED-1 && cnt_bit == 8 && cnt_num == data_num-1)begin
                if(ack_reg == 0)
                    next_state = STOP;
                else
                    next_state = ERROR;
            end
            else
                next_state = state;
                
    //新增的读数据状态
    START2   :if(cnt_scl == IIC_SPEED-1)
                next_state = DEVICE_RD;
            else
                next_state = state;
    DEVICE_RD:if(cnt_scl == IIC_SPEED-1 && cnt_bit == 7)
                next_state = ACK4;
            else
                next_state = state;
    ACK4     :if(cnt_scl == IIC_SPEED-1)begin
                if(ack_reg == 0)
                    next_state = RD_DATA;
                else 
                    next_state = ERROR;
            end
            else
                next_state = state;
    RD_DATA  :if(cnt_scl == IIC_SPEED-1 && cnt_bit == 8 && cnt_num == data_num-1)
                next_state = STOP;
            else
                next_state = state;

    STOP   :if(cnt_scl == IIC_SPEED-1)
                next_state = END;
            else
                next_state = state;
    END    :next_state = IDLE;
    ERROR  :if(cnt_error == DELAY_ERROR-1)
                next_state = IDLE;
            else
                next_state = state;
    default:next_state = IDLE;
    endcase
always@(posedge sys_clk)
    if(!sys_rst_n)
        ack_reg <= 1;
    else if(state == ACK1 || state == ACK2 || (state == WR_DATA && cnt_bit == 8) || state == ACK4)begin
        if(cnt_scl == IIC_SPPED_DIV2-1)
            ack_reg <= sda_in;
        else
            ack_reg <= ack_reg;
    end
    else
        ack_reg <= ack_reg;
             
        
always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_scl <= 0;
    else begin
        case(state)  
        START,DEVICE_WR ,ACK1,ADDR,ACK2,WR_DATA,STOP,START2,DEVICE_RD,ACK4,RD_DATA
        :begin
            if(cnt_scl == IIC_SPEED-1)
                cnt_scl <= 0;
            else
                cnt_scl <= cnt_scl+1;
        end
        default:cnt_scl <= 0;
        endcase
    end

always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_bit <= 0;
    else begin
        case(state)
        DEVICE_WR,ADDR,DEVICE_RD:begin
            if(cnt_scl == IIC_SPEED-1)begin
                if(cnt_bit == 7)    
                    cnt_bit <= 0;
                else 
                    cnt_bit <= cnt_bit+1;
            end
            else
                cnt_bit <= cnt_bit;
        end
        WR_DATA,RD_DATA:begin
            if(cnt_scl == IIC_SPEED-1)begin
                if(cnt_bit == 8)    
                    cnt_bit <= 0;
                else 
                    cnt_bit <= cnt_bit+1;
            end
            else
                cnt_bit <= cnt_bit;
        end
        default:cnt_bit <= 0;
        endcase
    end

always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_error <= 0;
    else if(state == ERROR)begin
        if(cnt_error == DELAY_ERROR-1)
            cnt_error <= 0;
        else
            cnt_error <= cnt_error+1;
    end
    else
        cnt_error <= 0;

always@(posedge sys_clk)
    if(!sys_rst_n)
        scl <= 1;
    else begin
        case(state) 
        DEVICE_WR   ,
        ACK1        ,
        ADDR        ,
        ACK2        ,
        WR_DATA     ,
        DEVICE_RD   , 
        ACK4        , 
        RD_DATA     
        :begin
            if(cnt_scl >= IIC_SPPED_DIV4-1 && cnt_scl <= (IIC_SPPED_DIV2+IIC_SPPED_DIV4-1))
                scl <= 1;
            else
                scl <= 0;
        end
        START,START2:if(cnt_scl <= IIC_SPPED_DIV2+IIC_SPPED_DIV4-1)
                    scl <= 1;
                else
                    scl <= 0;
        STOP    :if(cnt_scl <= IIC_SPPED_DIV4-1)
                    scl <= 0;
                else
                    scl <= 1;
        default:scl <= 1;
        endcase
    end
always@(posedge sys_clk)
    if(!sys_rst_n)
        sda_out <= 1;
    else begin
        case(state)  
        START,START2
                :if(cnt_scl <= IIC_SPPED_DIV4-1)
                    sda_out <= 1;
                else
                    sda_out <= 0;
        DEVICE_WR :sda_out <= IIC_WR_CMD[7-cnt_bit]; 
        DEVICE_RD :sda_out <= IIC_RD_CMD[7-cnt_bit];
        ADDR      :sda_out <= iic_addr[7-cnt_bit];
        WR_DATA   :begin
            if(cnt_bit <= 7)
                sda_out <= iic_wr_data[7-cnt_bit];
            else
                sda_out <= sda_out;
        end
        RD_DATA:begin
            if(cnt_bit == 8)begin
                if(cnt_num == data_num-1)
                    sda_out <= 1;//noack 
                else
                    sda_out <= 0;//ack 
            end
        else
            sda_out <= 1;//cnt_bit 0-7 是在读数据 sda_out是无效的-sda_en  
    end
        STOP      :if(cnt_scl <= IIC_SPPED_DIV2+IIC_SPPED_DIV4-1)
                    sda_out <= 0;
                else
                    sda_out <= 1;
        default: sda_out <= 1;
        endcase
    end
assign iic_done = (state == END)?1:0;

//数据采集
always@(posedge sys_clk)
    if(!sys_rst_n)
        iic_rd_data_reg <= 0;
    else if(state == RD_DATA)begin
        if(cnt_scl == IIC_SPPED_DIV2-1 && cnt_bit <= 7)
            iic_rd_data_reg[7-cnt_bit] <= sda_in;
        else
            iic_rd_data_reg <= iic_rd_data_reg;
    end
    else
        iic_rd_data_reg <= iic_rd_data_reg;
always@(posedge sys_clk)
    if(!sys_rst_n)begin
        iic_rd_data <= 0;
        iic_rd_data_valid <= 0;
    end
    else if(state == RD_DATA && cnt_scl == IIC_SPEED-1 && cnt_bit == 7)begin
        iic_rd_data <= iic_rd_data_reg;
        iic_rd_data_valid <= 1;
    end
    else begin
        iic_rd_data <= iic_rd_data;
        iic_rd_data_valid <= 0;
    end
    
//new 
always@(posedge sys_clk)
    if(!sys_rst_n)
        cnt_num <= 0;
    else if(state == WR_DATA || state == RD_DATA)begin
        if(cnt_scl == IIC_SPEED-1 && cnt_bit == 8 && ack_reg == 0)begin
            if(cnt_num == data_num-1)
                cnt_num <= 0;
            else
                cnt_num <= cnt_num+1;
        end
    end
    else
        cnt_num <= 0;
always@(posedge sys_clk)
    if(!sys_rst_n)
        iic_wr_data_request <= 0;
    else if(state == WR_DATA && data_num>=2)begin
        if(cnt_bit == 8 && cnt_num <= data_num-2 && cnt_scl == IIC_SPPED_DIV2-1)
            iic_wr_data_request <= 1;
        else
            iic_wr_data_request <= 0;
    end
    else
        iic_wr_data_request <= 0;
endmodule