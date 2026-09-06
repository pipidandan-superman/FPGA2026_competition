`timescale 1ns/1ps
module no_ip_counter_tb;
  logic clk=0, rst_n=0, enable=0;
  logic [7:0] count;
  wire overflow;
  integer i;
  bit completed=0;
  always #5 clk=~clk;
  simple_counter #(.WIDTH(8),.MAX_COUNT(10)) dut(.clk(clk),.rst_n(rst_n),.enable(enable),.count(count),.overflow(overflow));
  initial begin
    repeat(2) @(posedge clk); #1;
    if (count !== 0) $fatal(1,"reset count=%0d",count);
    rst_n=1; enable=1;
    for(i=1;i<=10;i=i+1) begin @(posedge clk); #1; if(count !== i[7:0]) $fatal(1,"count=%0d expected=%0d",count,i); end
    if (!overflow) $fatal(1,"overflow not asserted at max");
    @(posedge clk); #1; if(count !== 0) $fatal(1,"wrap count=%0d",count);
    $display("VITA_VIVADO_RESULT PASS");
    completed=1;
    $finish;
  end
  initial begin #10000; if(!completed) $fatal(1,"watchdog timeout"); end
endmodule
