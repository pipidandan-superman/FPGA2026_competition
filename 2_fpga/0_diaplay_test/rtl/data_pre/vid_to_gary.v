//图像预处理
/*
处理流程：
1.计数+ROI提取
2.灰度转换 Y=(R*77 + G*150 + B*29)>>8
3.二值化
4.下采样 112*112 -> 28*28
*/
//模块1,2
module vio_to_gray
#(
	parameter H_SIZE     = 640 ,
    parameter V_SIZE     = 480 ,
    parameter ROI_SIZE   = 112
)
(
	input  wire 		 pclk		,
	input  wire 		 rst_n		,
	input  wire [23:0]   vid_data	,
	input  wire 		 vid_active	,
	input  wire 		 vid_vsync	,

	output reg  [7:0]    gary_data	,
	output reg  		 gray_valid

);

//采集框位置参数（屏幕正中央，与边框位置对应）
localparam ROI_LEFT   = (H_SIZE - ROI_SIZE) / 2;   // 264
localparam ROI_RIGHT  = ROI_LEFT + ROI_SIZE - 1;   // 375
localparam ROI_TOP    = (V_SIZE - ROI_SIZE) / 2;   // 184
localparam ROI_BOTTOM = ROI_TOP + ROI_SIZE - 1;    // 295

reg [9:0] h_cnt,v_cnt;
wire roi_valid;
wire [23:0] roi_data;

//计数器
always@(posedge pclk or negedge rst_n)
	if(!rst_n)
		h_cnt <= 0;
	else if(vid_active)begin
		if(h_cnt >= H_SIZE-1)
			h_cnt <= 0;
		else
			h_cnt <= h_cnt+1;
	end
	else
		h_cnt <= 0;

always@(posedge pclk or negedge rst_n)
	if(!rst_n)
		v_cnt <= 0;
	else if(vid_vsync)
		v_cnt <= 0;
	else if(h_cnt == H_SIZE-1)begin
		if(v_cnt >= V_SIZE-1)
			v_cnt <= 0;
		else
			v_cnt <= v_cnt+1;
	end

//识别区域ROI提取（屏幕正中央）
assign roi_valid = (h_cnt >= ROI_LEFT && h_cnt <= ROI_RIGHT &&
                    v_cnt >= ROI_TOP  && v_cnt <= ROI_BOTTOM) ? 1 : 0;
assign roi_data = (roi_valid) ? vid_data : 0;


//灰度化转换 (流水线)
// Y = (R*77 + G*150 + B*29) >> 8
// RGB888 格式：R=[23:16], G=[15:8], B=[7:0]

//1.乘法
reg [15:0] mult_r,mult_g,mult_b;
reg mlut_valid;
always@(posedge pclk or negedge rst_n)
	if(!rst_n)begin
		mult_r <= 0;
		mult_g <= 0;
		mult_b <= 0;
		mlut_valid <= 0;
	end
	else begin
		mult_r <= vid_data[23:16]*77;
		mult_g <= vid_data[15:8]*150;
		mult_b <= vid_data[7:0]*29;
		mlut_valid <= roi_valid;
	end

//2.加法
reg [16:0] add_sum;
reg add_valid;
always@(posedge pclk or negedge rst_n)
	if(!rst_n)begin
		add_sum <= 0;
		add_valid <= 0;
    end
	else begin
		add_sum <= mult_r+mult_g+mult_b;
		add_valid <= mlut_valid;
	end

//移位输出
always@(posedge pclk or negedge rst_n)
	if(!rst_n)begin
		gary_data <= 0;
		gray_valid <= 0;
	end
	else begin
		gary_data <= add_sum>>8;
		gray_valid <= add_valid;
	end

endmodule
