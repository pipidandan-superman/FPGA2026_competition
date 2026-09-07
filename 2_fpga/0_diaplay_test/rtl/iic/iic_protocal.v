//iic Э��ʵ��
module iic_protocal
#(
    parameter DEVICE_WR_ADDR = 7'b0111001,
    parameter IIC_SPEED   = 150         //50Mhz ��Ƶϵ�� 333.333Khz < 400khz
)
(
    input  wire       sys_clk           ,
    input  wire       sys_rst_n         ,
                    
    input  wire       iic_start         ,
    input  wire [1:0] iic_we            ,//iic ��=1/д=0
    input  wire [7:0] iic_addr          ,
    input  wire [7:0] iic_wr_data       ,
    output reg  [7:0] iic_rd_data       ,
    output reg        iic_rd_data_valid ,
    output wire       iic_done          ,
            
    output reg        scl               ,
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
                               
            //д����
            WR_DATA     = 4'd6 ,
            ACK3        = 4'd7 ,
            //������
            START2      = 4'd8 ,
            DEVICE_RD   = 4'd9 ,
            ACK4        = 4'd10,
            RD_DATA     = 4'd11,
            NO_ACK      = 4'd12,
            
            STOP        = 4'd13,
            END         = 4'd14,
            ERROR       = 4'd15;
reg [3:0] state;
reg [3:0] next_state;
reg [15:0] cnt_scl;
reg [2:0] cnt_bit;
reg [27:0] cnt_error;
reg ack_reg;//�Ĵ�ɼ�����ack�źţ��ӻ�������źţ�

//��̬�ŵĿ���
//sda sda_out sda_in=sda 
//sda_en == 1 ���  sda_en == 0 ����
wire sda_in;
reg sda_out;
wire sda_en;
assign sda_en = (state == ACK1 || state == ACK2 || state == ACK3 ||
                 state == ACK4 || state == RD_DATA)?0:1;
assign sda_in = sda;
assign sda = sda_en ? sda_out : 1'bz;

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
                        next_state = WR_DATA; //д����
                    else if(iic_we == 2'b01)
                        next_state = START2;  //������
                    else
                        next_state = ERROR;
                end
                else 
                    next_state = ERROR;
            end
            else
                next_state = state;
    WR_DATA:if(cnt_scl == IIC_SPEED-1 && cnt_bit == 7)
                next_state = ACK3;
            else
                next_state = state;
    ACK3   :if(cnt_scl == IIC_SPEED-1)begin
                if(ack_reg == 0)
                    next_state = STOP;
                else 
                    next_state = ERROR;
            end
            else
                next_state = state;
                
    //�����Ķ�����״̬
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
    RD_DATA  :if(cnt_scl == IIC_SPEED-1 && cnt_bit == 7)
                next_state = NO_ACK;
            else
                next_state = state;
    NO_ACK   :if(cnt_scl == IIC_SPEED-1) 
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
    else if(state == ACK1 || state == ACK2 || state == ACK3 || state == ACK4)begin
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
        START,DEVICE_WR ,ACK1,ADDR,ACK2,WR_DATA,ACK3,STOP,START2,DEVICE_RD,ACK4,RD_DATA,NO_ACK
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
        DEVICE_WR,ADDR,WR_DATA,DEVICE_RD,RD_DATA:begin
            if(cnt_scl == IIC_SPEED-1)
                cnt_bit <= cnt_bit+1;
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
        ACK3        , 
        DEVICE_RD   , 
        ACK4        , 
        RD_DATA     , 
        NO_ACK  
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
        WR_DATA   :sda_out <= iic_wr_data[7-cnt_bit];
        STOP      :if(cnt_scl <= IIC_SPPED_DIV2+IIC_SPPED_DIV4-1)
                    sda_out <= 0;
                else
                    sda_out <= 1;
        default: sda_out <= 1;
        endcase
    end
assign iic_done = (state == END)?1:0;

//���ݲɼ�
always@(posedge sys_clk)
    if(!sys_rst_n)
        iic_rd_data_reg <= 0;
    else if(state == RD_DATA)begin
        if(cnt_scl == IIC_SPPED_DIV2-1)
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
//ila_0 your_instance_name (
//	.clk(sys_clk), // input wire clk


//	.probe0(iic_start        ), // input wire [0:0]  probe0  
//	.probe1(iic_we           ), // input wire [1:0]  probe1 
//	.probe2(iic_addr         ), // input wire [7:0]  probe2 
//	.probe3(iic_wr_data      ), // input wire [7:0]  probe3 
//	.probe4(iic_rd_data      ), // input wire [7:0]  probe4 
//	.probe5(iic_rd_data_valid), // input wire [0:0]  probe5 
//	.probe6(iic_done         ), // input wire [0:0]  probe6 
//	.probe7(scl              ), // input wire [0:0]  probe7 
//	.probe8(sda_in            ), // input wire [0:0]  probe8
//	.probe9(sda_out             )  // input wire [0:0]  probe9
//);
//ila_0 your_instance_name (
//	.clk(sys_clk), // input wire clk


//	.probe0(iic_start        ), // input wire [0:0]  probe0  
//	.probe1(iic_we           ), // input wire [1:0]  probe1 
//	.probe2(iic_addr         ), // input wire [7:0]  probe2 
//	.probe3(iic_wr_data      ), // input wire [7:0]  probe3 
//	.probe4(iic_rd_data      ), // input wire [7:0]  probe4 
//	.probe5(sda_en), // input wire [0:0]  probe5 
//	.probe6(iic_done         ), // input wire [0:0]  probe6 
//	.probe7(scl              ), // input wire [0:0]  probe7 
//	.probe8(sda_in           ), // input wire [0:0]  probe8 
//	.probe9(sda_out          ), // input wire [0:0]  probe9 
//	.probe10(state           ) // input wire [3:0]  probe10
//);
endmodule
