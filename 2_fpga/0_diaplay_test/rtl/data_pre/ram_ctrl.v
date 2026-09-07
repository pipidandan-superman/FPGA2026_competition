//PL预处理数据写入ram写完后产生中断，由PS测检测到中断后发起读操作
module ram_ctrl
#(
    parameter TOTAL_PIXELS = 784 // 28 * 28
)
(
    input  wire        pclk          , // 像素时钟 (或者预处理模块的工作时钟)
    input  wire        rst_n        ,
    
    // 来自步骤 4 (下采样池化) 的输入
    input  wire        pool_valid   ,
    input  wire        pool_data    ,
    
    //------------------------------------------
    // 输出给 BRAM (Port A) 的标准接口
    //------------------------------------------
    output wire        bram_clk     ,
    output wire        bram_en      ,
    output wire [3:0]  bram_we      , // 4 字节写使能 (32-bit)
    output reg  [31:0] bram_addr    , // 字节地址
    output wire [31:0] bram_wdata   ,
    
    //------------------------------------------
    // 输出给 Zynq PS 的硬件中断
    //------------------------------------------
    output reg         ps_intr      
);

assign bram_clk = pclk;
assign bram_en  = pool_valid;
assign bram_we  = 4'b1111; // 写入时 4 个字节全开

// 数据对齐：将 1-bit 硬件信号填充为 32-bit 软件整型
// 如果黑点(1)，给软件读到的是 0x00000001
assign bram_wdata = {31'd0, pool_data}; 

// BRAM 写地址控制 (AXI 字节寻址，步长为 4)
// 最大地址为 783 * 4 = 3132 (12'hc3c)
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        bram_addr <= 32'd0;
    end
    else if(pool_valid) begin
        if(bram_addr >= (TOTAL_PIXELS - 1) * 4) begin
            bram_addr <= 32'd0; // 一帧写完，地址复位归零，准备写下一帧
        end
        else begin
            bram_addr <= bram_addr + 4;
        end
    end
end

// PS 中断信号生成 (Frame Done)
// 当最后一个像素写入时，产生一个单时钟周期的中断脉冲
always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
        ps_intr <= 1'b0;
    end
    else if (pool_valid && (bram_addr == (TOTAL_PIXELS - 1) * 4)) begin
        ps_intr <= 1'b1;
    end
    else begin
        ps_intr <= 1'b0;
    end
end

endmodule