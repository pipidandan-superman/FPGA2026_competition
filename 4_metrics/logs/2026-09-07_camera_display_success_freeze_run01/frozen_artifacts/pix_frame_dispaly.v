//显示识别区域边框
//识别区域数据大小为 28*28
//显示框 识别区域（下采样后） 显示为 112*112（28*4）
//显示器分辨率为 640*480
//采集框位置：屏幕正中央

module pix_frame_display
#(
	parameter H_SIZE  = 640 ,
	parameter V_SIZE  = 480 ,
	parameter FR_SIZE = 112  //28*4
)
(
	input  wire 			vio_clk		,
	input  wire 			sys_rst_n	,
	input  wire 			vio_active	,
	input  wire 			vio_hsync	,
	input  wire 			vio_vsync	,
	input  wire  [23:0]     vio_data	,
	//rom_data
	input  wire             rom_data    ,
	output wire  [13:0]     rom_addr    ,
	output wire             rom_valid   ,

	output reg   [23:0]     hdmi_data	,
	output reg 				hdmi_de		,
	output reg 				hdmi_hsync	,
	output reg 				hdmi_vsync
);

//采集框位置参数（屏幕正中央）
localparam FR_LEFT   = (H_SIZE - FR_SIZE) / 2;   // 264
localparam FR_RIGHT  = FR_LEFT + FR_SIZE - 1;    // 375
localparam FR_TOP    = (V_SIZE - FR_SIZE) / 2;   // 184
localparam FR_BOTTOM = FR_TOP + FR_SIZE - 1;     // 295

//信号定义
reg [9:0] h_cnt;
reg [9:0] v_cnt;
reg rst_n0,rst_sync;

//HDMI同步
always@(posedge vio_clk or negedge rst_sync)
	if(!rst_sync)begin
		hdmi_de	   <= 0;
	    hdmi_hsync <= 0;
	    hdmi_vsync <= 0;
	end
	else begin
		hdmi_de	   <= vio_active;
		hdmi_hsync <= ~vio_hsync	;
		hdmi_vsync <= ~vio_vsync	;
	end

//异步复位 同步释放
always@(posedge vio_clk or negedge sys_rst_n)
	if(!sys_rst_n)begin
		rst_n0 <= 0;
		rst_sync <= 0;
	end
	else begin
		rst_n0 <= 1;
		rst_sync <= rst_n0;
	end


//行计数器 0-639
always@(posedge vio_clk or negedge rst_sync)
	if(!rst_sync)
		h_cnt <= 0;
	else if(vio_hsync)
		h_cnt <= 0;
	else if(vio_active)begin
		if(h_cnt >= H_SIZE-1)
			h_cnt <= 0;
		else
			h_cnt <= h_cnt+1;
	end
	else
		h_cnt <= 0;

//场计数器 0-479
always@(posedge vio_clk or negedge rst_sync)
	if(!rst_sync)
		v_cnt <= 0;
	else if(vio_vsync)
		v_cnt <= 0;
	else if(h_cnt == H_SIZE-1 && vio_active == 1)begin
		if(v_cnt >= V_SIZE-1)
			v_cnt <= 0;
		else
			v_cnt <= v_cnt+1;
	end

//绘制采集框边框（四条线）
//边框宽度为1像素，白色显示
wire frame_valid;
assign frame_valid = (
		// 左边框
		(h_cnt == FR_LEFT && v_cnt >= FR_TOP && v_cnt <= FR_BOTTOM) ||
		// 右边框
		(h_cnt == FR_RIGHT && v_cnt >= FR_TOP && v_cnt <= FR_BOTTOM) ||
		// 上边框
		(v_cnt == FR_TOP && h_cnt >= FR_LEFT && h_cnt <= FR_RIGHT) ||
		// 下边框
		(v_cnt == FR_BOTTOM && h_cnt >= FR_LEFT && h_cnt <= FR_RIGHT)
	) ? 1 : 0;

//右侧边框-显示识别数字
//ROM地址和数据会映射一个周期
assign rom_valid = ((h_cnt >= 10'd540 && h_cnt <= 10'd639) &&
                   (v_cnt >= 10'd0    && v_cnt <= 10'd99));
assign rom_addr = (h_cnt-540)+(v_cnt*100);

always@(posedge vio_clk or negedge rst_sync)
	if(!rst_sync)
		hdmi_data <= 0;
	else if(frame_valid)
		hdmi_data <= 24'hffffff;  // 白色边框
	else if(rom_valid)
	    hdmi_data <= (rom_data)?24'hffffff:0;
	else if(vio_active)
		hdmi_data <= vio_data;
	else
		hdmi_data <= 0;


endmodule
