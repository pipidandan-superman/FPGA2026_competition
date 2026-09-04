//����ͷ���ݲɼ�
module cam_captrue_data
(
    input         i_xclk             ,//pll/mmcm
    input         rst_n              ,//locked 
    //cam       
    input         cam_pclk           ,//�ڲ�alwaysʱ��
    input         cam_href           ,
    input         cam_vsync          ,
    input  [7:0]  cam_data           ,
    output        cam_xclk           ,
    //video �Ľӿ�     
    output        vid_clk            ,//pclk
    output        vid_ce             ,//����vid_clk
    output        vid_vsync          ,
    output        vid_active_video   ,
    output [23:0] vid_data
    
);
assign cam_xclk = i_xclk;
assign vid_clk = cam_pclk; //���ĳ�һ������ �յ� vid_ce�Ŀ���
localparam WAIT_FRAME = 10;//ǰ10֡��Ҫ
//�ڲ�����
reg rst_n_sync;
reg rst_n_d0;

reg cam_vsync_d0,cam_vsync_d1;
reg cam_href_d0,cam_href_d1;
wire pos_vsync;
reg [7:0] cam_data_d0;
reg data_flag;
reg data_flag_d0;

reg [3:0] frame_cnt;//�Գ�ͬ�������ؼ���
reg       wait_done;//��־��Ƶ�����ȶ�

reg  [15:0] rgb565_data;
wire [23:0] rgb888_data;
//1.�첽��λ ͬ���ͷ� 
always@(posedge cam_pclk or negedge rst_n)begin
    if(!rst_n)begin
        rst_n_d0    <= 0;
        rst_n_sync  <= 0;
    end
    else begin
        rst_n_d0    <= 1;
        rst_n_sync  <= rst_n_d0;
    end
end
//2.�źŴ���
always@(posedge cam_pclk or negedge rst_n_sync)
    if(!rst_n_sync)begin
        cam_vsync_d0 <= 0;
        cam_vsync_d1 <= 0;
        cam_href_d0  <= 0;
        cam_href_d1  <= 0;
        data_flag_d0 <= 0;
    end
    else begin
        cam_vsync_d0 <= cam_vsync;
        cam_vsync_d1 <= cam_vsync_d0;
        cam_href_d0  <= cam_href;
        cam_href_d1  <= cam_href_d0;
        data_flag_d0 <= data_flag;
    end
assign pos_vsync = (cam_vsync_d0 == 0 && cam_vsync_d1 == 1)?1:0;
//3.֡����������������ͷ�����vsync������ �жϵ�ǰ��ȡ���ǵڼ�֡
always@(posedge cam_pclk or negedge rst_n_sync)
    if(!rst_n_sync)
        frame_cnt <= 0;
    else if(pos_vsync)begin
        if(frame_cnt == WAIT_FRAME-1)
            frame_cnt <= frame_cnt;
        else 
            frame_cnt <= frame_cnt+1;
    end

always@(posedge cam_pclk or negedge rst_n_sync)
    if(!rst_n_sync)
        wait_done <= 0;
    else if(pos_vsync && frame_cnt == WAIT_FRAME-1)
        wait_done <= 1;
    else
        wait_done <= wait_done;
//4.����ƴ��
always@(posedge cam_pclk or negedge rst_n_sync)
    if(!rst_n_sync)begin
        cam_data_d0 <= 0;
        rgb565_data <= 0;
        data_flag   <= 0;
    end
    else if(cam_href)begin
        data_flag <= ~data_flag;
        cam_data_d0 <= cam_data;
        if(data_flag)
            rgb565_data <= {cam_data_d0,cam_data};
        else
            rgb565_data <= rgb565_data;
    end
    else begin
        data_flag <= 0;
        cam_data_d0 <= 0;
    end

//assign rgb888_data = {rgb565_data[15:11],3'b000,rgb565_data[10:5],2'b00,rgb565_data[4:0],3'b000};
assign rgb888_data = {rgb565_data[15:11], rgb565_data[15:13], rgb565_data[10:5], rgb565_data[10:9], rgb565_data[4:0], rgb565_data[4:2]};
//vid 
assign vid_vsync        = (wait_done)?cam_vsync_d1:'d0;
assign vid_active_video = (wait_done)?cam_href_d1 :'d0;
assign vid_data         = (wait_done)?rgb888_data :'d0;
//vid_ce
/*
1.ͼ����Ч����
2.ͼ����������
*/
assign vid_ce = (wait_done)? ((vid_active_video & data_flag_d0)||(~vid_active_video)):0;
endmodule