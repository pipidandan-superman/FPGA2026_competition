`timescale 1ns/1ps
module probe2;
    reg [1023:0] p;
    reg [1279:0] fp;
    reg [7:0] mem [0:1];
    integer fh;
    initial begin
        if (!$value$plusargs("P=%s", p)) $display("PROBE_NOARG");
        fp = {p, "/x.hex"};
        fh = $fopen(fp, "r");
        $display("PROBE_FOPEN=%0d", fh);
        $readmemh(fp, mem);
        $display("PROBE_MEM0=%h PROBE_MEM1=%h", mem[0], mem[1]);
        $finish;
    end
endmodule
