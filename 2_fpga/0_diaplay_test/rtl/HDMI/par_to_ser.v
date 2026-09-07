//并串转换 
module pra_to_ser
(
    input       clk         ,
    input       clk_x5      ,
    input       rst_n       ,
    input [9:0] par_data    ,
    output      ser_data
);
wire expand_1;
wire expand_2;
//源语调用
// Xilinx HDL Language Template, version 2020.1

   OSERDESE2 #(
      .DATA_RATE_OQ("DDR"),   // DDR, SDR
      .DATA_RATE_TQ("DDR"),   // DDR, BUF, SDR
      .DATA_WIDTH(10),         // Parallel data width (2-8,10,14)
      .INIT_OQ(1'b0),         // Initial value of OQ output (1'b0,1'b1)
      .INIT_TQ(1'b0),         // Initial value of TQ output (1'b0,1'b1)
      .SERDES_MODE("MASTER"), // MASTER, SLAVE
      .SRVAL_OQ(1'b0),        // OQ output value when SR is used (1'b0,1'b1)
      .SRVAL_TQ(1'b0),        // TQ output value when SR is used (1'b0,1'b1)
      .TBYTE_CTL("FALSE"),    // Enable tristate byte operation (FALSE, TRUE)
      .TBYTE_SRC("FALSE"),    // Tristate byte source (FALSE, TRUE)
      .TRISTATE_WIDTH(1)      // 3-state converter width (1,4)
   )
   OSERDESE2_master (
      .OFB( ),             // 1-bit output: Feedback path for data
      .OQ(ser_data),               // 1-bit output: Data path output
      // SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
      .SHIFTOUT1( ),
      .SHIFTOUT2( ),
      .TBYTEOUT( ),   // 1-bit output: Byte group tristate
      .TFB( ),             // 1-bit output: 3-state control
      .TQ( ),               // 1-bit output: 3-state control
      .CLK(clk_x5),             // 1-bit input: High speed clock
      .CLKDIV(clk),       // 1-bit input: Divided clock
      // D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
      .D1(par_data[0]),
      .D2(par_data[1]),
      .D3(par_data[2]),
      .D4(par_data[3]),
      .D5(par_data[4]),
      .D6(par_data[5]),
      .D7(par_data[6]),
      .D8(par_data[7]),
      .OCE(1),             // 1-bit input: Output data clock enable
      .RST(!rst_n),             // 1-bit input: Reset
      // SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
      .SHIFTIN1(expand_1),
      .SHIFTIN2(expand_2),
      // T1 - T4: 1-bit (each) input: Parallel 3-state inputs
      .T1(0),
      .T2(0),
      .T3(0),
      .T4(0),
      .TBYTEIN(0),     // 1-bit input: Byte group tristate
      .TCE(0)              // 1-bit input: 3-state clock enable
   );

   // End of OSERDESE2_inst instantiation
   
// Xilinx HDL Language Template, version 2020.1

   OSERDESE2 #(
      .DATA_RATE_OQ("DDR"),   // DDR, SDR
      .DATA_RATE_TQ("DDR"),   // DDR, BUF, SDR
      .DATA_WIDTH(10),         // Parallel data width (2-8,10,14)
      .INIT_OQ(1'b0),         // Initial value of OQ output (1'b0,1'b1)
      .INIT_TQ(1'b0),         // Initial value of TQ output (1'b0,1'b1)
      .SERDES_MODE("SLAVE"), // MASTER, SLAVE
      .SRVAL_OQ(1'b0),        // OQ output value when SR is used (1'b0,1'b1)
      .SRVAL_TQ(1'b0),        // TQ output value when SR is used (1'b0,1'b1)
      .TBYTE_CTL("FALSE"),    // Enable tristate byte operation (FALSE, TRUE)
      .TBYTE_SRC("FALSE"),    // Tristate byte source (FALSE, TRUE)
      .TRISTATE_WIDTH(1)      // 3-state converter width (1,4)
   )
   OSERDESE2_slave (
      .OFB( ),             // 1-bit output: Feedback path for data
      .OQ( ),               // 1-bit output: Data path output
      // SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
      .SHIFTOUT1(expand_1),
      .SHIFTOUT2(expand_2),
      .TBYTEOUT( ),   // 1-bit output: Byte group tristate
      .TFB( ),             // 1-bit output: 3-state control
      .TQ( ),               // 1-bit output: 3-state control
      .CLK(clk_x5),             // 1-bit input: High speed clock
      .CLKDIV(clk),       // 1-bit input: Divided clock
      // D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
      .D1(0),
      .D2(0),
      .D3(par_data[8]),
      .D4(par_data[9]),
      .D5(0),
      .D6(0),
      .D7(0),
      .D8(0),
      .OCE(1),             // 1-bit input: Output data clock enable
      .RST(!rst_n),             // 1-bit input: Reset
      // SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
      .SHIFTIN1( ),
      .SHIFTIN2( ),
      // T1 - T4: 1-bit (each) input: Parallel 3-state inputs
      .T1(0),
      .T2(0),
      .T3(0),
      .T4(0),
      .TBYTEIN(0),     // 1-bit input: Byte group tristate
      .TCE(0)              // 1-bit input: 3-state clock enable
   );

   // End of OSERDESE2_inst instantiation   
endmodule