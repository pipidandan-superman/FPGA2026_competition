//二值化处理
module gray_yo_bin
#(
    // 二值化阈值，0~255。
    // 典型室内光照下白纸约为 200+，黑字约为 50~100，这里取中间值 128。
    parameter THRESHOLD = 8'd128 
)
(
	input  wire  		 pclk		,
	input  wire  		 rst_n		,
	input  wire  [7:0] 	 gray_data	,
	input  wire  		 gray_valid	,
	output reg  		 bin_data	,
	output reg  		 bin_valid	
);
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        bin_valid <= 1'b0;
        bin_data  <= 1'b0;
    end 
    else begin
        // 有效信号同步打拍
        bin_valid <= gray_valid;
        
        if (gray_valid) begin
            // 【核心反相逻辑】
            // 现实摄像头：白纸背景（亮，灰度值大），黑色笔画（暗，灰度值小）
            // 神经网络(MNIST)：黑色背景为 0，白色笔画为 1
            // 因此：当实际灰度值小于阈值（偏黑）时，判断为笔画，输出 1
            if (gray_data < THRESHOLD)
                bin_data <= 1'b1;
            else
                bin_data <= 1'b0; // 白纸背景输出 0
        end 
        else begin
            // 非有效数据期间清零，降低后续电路翻转功耗
            bin_data <= 1'b0;
        end
    end
end
endmodule