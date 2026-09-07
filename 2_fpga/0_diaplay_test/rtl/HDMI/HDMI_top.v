module HDMI_top(
    input        pix_clk     ,
    input        pix_clk_x5  ,
    input        rst_n       ,
    
    input        h_sync      ,
    input        v_sync      ,
    input [7:0]  red_data    ,
    input [7:0]  green_data  ,
    input [7:0]  blue_data   ,
    input        de          ,//data_valid
                 
    output       TMDS_clk_p  ,
    output       TMDS_clk_n  ,
    output [2:0] TMDS_data_p ,
    output [2:0] TMDS_data_n ,
    output       hdmi_en

    );
wire [9:0] TMDS_r_data;
wire [9:0] TMDS_g_data;
wire [9:0] TMDS_b_data;
localparam TMDS_clk_data = 10'b11111_00000;

wire ser_data_r;
wire ser_data_g;
wire ser_data_b;
wire ser_data_clk;

assign hdmi_en = 1;
//TMDS编码
encode  u_encode_1(
  . clkin   (pix_clk),    // pixel clock input
  . rstin   (~rst_n),    // async. reset input (active high)
  . din     (red_data),         // data inputs: expect registered
  . c0      (0),          // c0 input
  . c1      (0),          // c1 input
  . de      (de),          // de input
  . dout    (TMDS_r_data)     // data outputs
);
encode  u_encode_2(
  . clkin   (pix_clk),    // pixel clock input
  . rstin   (~rst_n),    // async. reset input (active high)
  . din     (green_data),         // data inputs: expect registered
  . c0      (0),          // c0 input
  . c1      (0),          // c1 input
  . de      (de),          // de input
  . dout    (TMDS_g_data)     // data outputs
);
encode  u_encode_3(
  . clkin   (pix_clk),    // pixel clock input
  . rstin   (~rst_n),    // async. reset input (active high)
  . din     (blue_data),         // data inputs: expect registered
  . c0      (h_sync),          // c0 input
  . c1      (v_sync),          // c1 input
  . de      (de),          // de input
  . dout    (TMDS_b_data)     // data outputs
);


//并行数据转差分
pra_to_ser u_pra_to_ser_r
(
    .clk         (pix_clk),
    .clk_x5      (pix_clk_x5),
    .rst_n       (rst_n),
    .par_data    (TMDS_r_data),
    .ser_data    (ser_data_r)
);
pra_to_ser u_pra_to_ser_g
(
    .clk         (pix_clk),
    .clk_x5      (pix_clk_x5),
    .rst_n       (rst_n),
    .par_data    (TMDS_g_data),
    .ser_data    (ser_data_g)
);
pra_to_ser u_pra_to_ser_b
(
    .clk         (pix_clk),
    .clk_x5      (pix_clk_x5),
    .rst_n       (rst_n),
    .par_data    (TMDS_b_data),
    .ser_data    (ser_data_b)
);
pra_to_ser u_pra_to_ser_clk
(
    .clk         (pix_clk),
    .clk_x5      (pix_clk_x5),
    .rst_n       (rst_n),
    .par_data    (TMDS_clk_data),
    .ser_data    (ser_data_clk)
);

//串行数据转差分
ser_to_diff u_ser_to_diff_r
(
    .ser_data     (ser_data_r),
    .ser_data_p   (TMDS_data_p[0]),
    .ser_data_n   (TMDS_data_n[0])
);
ser_to_diff u_ser_to_diff_g
(
    .ser_data     (ser_data_g),
    .ser_data_p   (TMDS_data_p[1]),
    .ser_data_n   (TMDS_data_n[1])
);
ser_to_diff u_ser_to_diff_b
(
    .ser_data     (ser_data_b),
    .ser_data_p   (TMDS_data_p[2]),
    .ser_data_n   (TMDS_data_n[2])
);
ser_to_diff u_ser_to_diff_clk
(
    .ser_data     (ser_data_clk),
    .ser_data_p   (TMDS_clk_p),
    .ser_data_n   (TMDS_clk_n)
);
endmodule