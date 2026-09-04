module ov5640_cfg_top
#(
    parameter OV5640_W   = 8'h78  ,
    parameter OV5640_R   = 8'H79  ,
    parameter CLK_DIV    = 9'D500 ,
    parameter PACK_DELAY = 75     ,
    parameter CAM_HSIZE  = 640    ,
    parameter CAM_VSIZE  = 480    ,
    parameter REG_NUM    = 8'D251
    
)
(
    input  sys_clk      ,
    input  sys_rst_n    ,
    output sccb_clk     ,
    inout  sccb_data    ,
    output sccb_cfg_done
);
//д����
wire [15:0] reg_addr      ;
wire [7:0]  w_data        ;
reg         w_en          ;

wire        w_done        ;
//wire        sccb_cfg_done ;

//������
wire            r_en          ;
wire    [7:0]   r_data        ;
wire            r_done        ;

reg [7:0] reg_index; //�Ĵ���ָ��
wire [23:0] REG_DATA;

//����ͷ�ϵ����? ����һ��ʱ��Ҫ�� 
reg [8:0] rst_cnt;
always@(posedge sys_clk)
    if(!sys_rst_n)
        rst_cnt <= 0;
    else if(rst_cnt[8] == 1'b0)
        rst_cnt <= rst_cnt+1;
    else
        rst_cnt <= rst_cnt;

//д����
always@(posedge sys_clk)
    if(!sys_rst_n)begin
        w_en <= 0;
        reg_index <= 0;
    end
    else if(rst_cnt[8] == 1'b0)begin
        w_en <= 0;
        reg_index <= 0;
    end
    else begin
        if(sccb_cfg_done)begin
            w_en <= 0;
            reg_index <= 0;
        end
        else begin
            w_en <= 1;
            if(w_done)begin
                if(reg_index == REG_NUM-1)
                    reg_index <= reg_index;
                else 
                    reg_index <= reg_index+1;
            end
            else 
                reg_index <= reg_index;
        end
    
    end



sccb_protocol
#(
    .OV5640_W   (OV5640_W  ),
    .OV5640_R   (OV5640_R  ),
    .CLK_DIV    (CLK_DIV   ), //SCCBʱ��Ƶ�� 100KHZ
    .PACK_DELAY (PACK_DELAY)
)
u_sccb_protocol
(
    .sys_clk        (sys_clk  ),//input  wire        sys_clk        
    .sys_rst_n      (sys_rst_n),//input  wire        sys_rst_n      
                                       //
    //д����                           ////д����
    .reg_addr       (REG_DATA[23:8] ),//input  wire [15:0] reg_addr       
    .w_data         (REG_DATA[7:0]  ),//input  wire [7:0]  w_data         
    .w_en           (w_en           ),//input  wire        w_en           
    .reg_num        (REG_NUM        ),//input  wire [10:0] reg_num        //��Ҫ���õļĴ������� 270 300
    .w_done         (w_done         ),//output wire        w_done         
    .sccb_cfg_done  (sccb_cfg_done  ),//output wire        sccb_cfg_done  
                                       //
    //������                           ////������
    .r_en           (r_en           ),//input  wire        r_en           
    .r_data         (r_data         ),//output reg   [7:0] r_data         
    .r_done         (r_done         ),//output wire        r_done         
                                       //
    //sccb interface                   ////sccb interface
    .sck            (sccb_clk ),//output reg         sck            
    .sda            (sccb_data) //inout  wire        sda        
);

ov5640_regs
#(
    .CAM_HSIZE(CAM_HSIZE),
    .CAM_VSIZE(CAM_VSIZE),
    .REG_NUM  (REG_NUM  )
)
ov5640_regs
(
    .REG_INDEX(reg_index), //input       [7:0] REG_INDEX
    .REG_DATA (REG_DATA)  //output reg [23:0] REG_DATA
);
endmodule