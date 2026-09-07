//下采样 112*112 28*28
module image_downsample
#(
    parameter ROI_W   = 112 , // 感兴趣区域宽度
    parameter ROI_H   = 112 , // 感兴趣区域高度
    parameter POOL_TH = 4     // 4x4池化阈值 (16个像素中>=4个黑点，则认为该区域有笔画)
)
(
	input  wire pclk			,
	input  wire rst_n			,
	input  wire bin_data		,
	input  wire bin_valid		,
	output reg  pool_data		,
	output reg  pool_valid
);
//---------------------------------------------------
// 1. 内部 ROI 坐标系重建
// (降采样需要知道当前像素处于 4x4 矩阵的哪个位置)
//---------------------------------------------------
reg [6:0] roi_x_cnt; // 0 ~ 111
reg [6:0] roi_y_cnt; // 0 ~ 111

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        roi_x_cnt <= 0;
        roi_y_cnt <= 0;
    end
    else if(bin_valid) begin
        if(roi_x_cnt == ROI_W - 1) begin
            roi_x_cnt <= 0;
            if(roi_y_cnt == ROI_H - 1)
                roi_y_cnt <= 0; // 一帧结束
            else
                roi_y_cnt <= roi_y_cnt + 1;
        end
        else begin
            roi_x_cnt <= roi_x_cnt + 1;
        end
    end
end

//---------------------------------------------------
// 2. 超轻量级行缓存 (Line Buffers) 
// 112 bits * 3 行 = 336 bits (连半个 BRAM 都用不到)
//---------------------------------------------------
reg [ROI_W-1:0] line_buf_1;
reg [ROI_W-1:0] line_buf_2;
reg [ROI_W-1:0] line_buf_3;

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        line_buf_1 <= 0;
        line_buf_2 <= 0;
        line_buf_3 <= 0;
    end
    else if(bin_valid) begin
        // 数据像水流一样，逐个像素向左移位推入
        // 移位 112 次后，最高位吐出的正好是正上方一行的同一个 X 坐标的像素
        line_buf_1 <= {line_buf_1[ROI_W-2:0], bin_data};
        line_buf_2 <= {line_buf_2[ROI_W-2:0], line_buf_1[ROI_W-1]};
        line_buf_3 <= {line_buf_3[ROI_W-2:0], line_buf_2[ROI_W-1]};
    end
end

//---------------------------------------------------
// 3. 4x4 像素矩阵提取 (Window Generation)
//---------------------------------------------------
reg [3:0] row0_shift;
reg [3:0] row1_shift;
reg [3:0] row2_shift;
reg [3:0] row3_shift;

always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        row0_shift <= 0;
        row1_shift <= 0;
        row2_shift <= 0;
        row3_shift <= 0;
    end
    else if(bin_valid) begin
        // 提取当前行和上面三行的最新 4 个像素
        row0_shift <= {row0_shift[2:0], bin_data};
        row1_shift <= {row1_shift[2:0], line_buf_1[ROI_W-1]};
        row2_shift <= {row2_shift[2:0], line_buf_2[ROI_W-1]};
        row3_shift <= {row3_shift[2:0], line_buf_3[ROI_W-1]};
    end
end

//---------------------------------------------------
// 4. 步长为 4 的降采样与投票加法树
//---------------------------------------------------
// 只有当 X 和 Y 坐标都正好是 4 的倍数-1 (即 3, 7, 11...) 时
// 4x4 的移位窗口才正好填满了一个不重叠的 4x4 图像块 (Stride = 4)
wire pool_trigger = (roi_x_cnt[1:0] == 2'b11) && (roi_y_cnt[1:0] == 2'b11) && bin_valid;

// 组合逻辑计算 16 个像素中 '1' 的个数
reg [4:0] sum_16; 
always @(*) begin
    sum_16 = row0_shift[0] + row0_shift[1] + row0_shift[2] + row0_shift[3] +
             row1_shift[0] + row1_shift[1] + row1_shift[2] + row1_shift[3] +
             row2_shift[0] + row2_shift[1] + row2_shift[2] + row2_shift[3] +
             row3_shift[0] + row3_shift[1] + row3_shift[2] + row3_shift[3] ;
end

// 打一拍输出，保证时序收敛
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        pool_valid <= 0;
        pool_data  <= 0;
    end
    else if(pool_trigger) begin
        pool_valid <= 1'b1;
        // 投票判定：如果16个像素里至少有 POOL_TH 个笔画点，才保留为笔画
        if(sum_16 >= POOL_TH) 
            pool_data <= 1'b1;
        else
            pool_data <= 1'b0;
    end
    else begin
        pool_valid <= 1'b0; // 输出 28x28 脉冲
    end
end

endmodule