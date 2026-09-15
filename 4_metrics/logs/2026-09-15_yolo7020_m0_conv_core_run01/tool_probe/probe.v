`timescale 1ns/1ps
module probe;
    reg [1023:0] p;
    reg [1279:0] fp;
    reg [7:0] mem [0:1];
    reg [7:0] cl;
    initial begin
        cl = $clog2(27);
        if (!$value$plusargs("P=%s", p)) $display("PROBE_NOARG");
        fp = {p, "/x.hex"};
        $readmemh(fp, mem);
        $display("PROBE_CLOG2=%0d PROBE_MEM0=%h PROBE_MEM1=%h", cl, mem[0], mem[1]);
        $finish;
    end
endmodule
