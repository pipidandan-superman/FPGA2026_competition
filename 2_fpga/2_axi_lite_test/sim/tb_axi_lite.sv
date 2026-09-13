//====================================================================
// File name   : tb_axi_lite.sv
// Author      : Codex
// Create date : 2026-09-12
// Description : Independent PS-PL AXI-Lite register test
// Target      : FPGA
// Revision    : V1.0
//====================================================================
`timescale 1ns/1ps
module tb_axi_lite;
    wire delayed_done;
    tb_slave_delay u_delayed (.done (delayed_done));
    reg          clk = 0;
    reg          resetn = 0;
    reg  [11:0]  s_axi_awaddr = 0;
    reg  [2:0]   s_axi_awprot = 0;
    reg          s_axi_awvalid = 0;
    wire         s_axi_awready;
    reg  [31:0]  s_axi_wdata = 0;
    reg  [3:0]   s_axi_wstrb = 0;
    reg          s_axi_wvalid = 0;
    wire         s_axi_wready;
    wire [1:0]   s_axi_bresp;
    wire         s_axi_bvalid;
    reg          s_axi_bready = 0;
    reg  [11:0]  s_axi_araddr = 0;
    reg  [2:0]   s_axi_arprot = 0;
    reg          s_axi_arvalid = 0;
    wire         s_axi_arready;
    wire [31:0]  s_axi_rdata;
    wire [1:0]   s_axi_rresp;
    wire         s_axi_rvalid;
    reg          s_axi_rready = 0;
    always #5 clk = ~clk;
    axi_lite_test_top dut (
        .clk            (clk           ),
        .resetn         (resetn        ),
        .s_axi_awaddr   (s_axi_awaddr  ),
        .s_axi_awprot   (s_axi_awprot  ),
        .s_axi_awvalid  (s_axi_awvalid ),
        .s_axi_awready  (s_axi_awready ),
        .s_axi_wdata    (s_axi_wdata   ),
        .s_axi_wstrb    (s_axi_wstrb   ),
        .s_axi_wvalid   (s_axi_wvalid  ),
        .s_axi_wready   (s_axi_wready  ),
        .s_axi_bresp    (s_axi_bresp   ),
        .s_axi_bvalid   (s_axi_bvalid  ),
        .s_axi_bready   (s_axi_bready  ),
        .s_axi_araddr   (s_axi_araddr  ),
        .s_axi_arprot   (s_axi_arprot  ),
        .s_axi_arvalid  (s_axi_arvalid ),
        .s_axi_arready  (s_axi_arready ),
        .s_axi_rdata    (s_axi_rdata   ),
        .s_axi_rresp    (s_axi_rresp   ),
        .s_axi_rvalid   (s_axi_rvalid  ),
        .s_axi_rready   (s_axi_rready  )
    );

    integer checks = 0;
    integer aw_count = 0, w_count = 0, b_count = 0, ar_count = 0, r_count = 0;
    reg prev_bstall = 0, prev_rstall = 0;
    reg [1:0] prev_bresp, prev_rresp;
    reg [31:0] prev_rdata;

    task automatic fail(input string reason);
        $display("AXILT_FAIL %s time=%0t", reason, $time);
        $display("VITA_VIVADO_RESULT FAIL");
        $fatal(1, "%s", reason);
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            aw_count = 0; w_count = 0; b_count = 0; ar_count = 0; r_count = 0;
            prev_bstall = 0; prev_rstall = 0;
        end else begin
            if ($isunknown({s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_bresp,
                            s_axi_arready,s_axi_rvalid,s_axi_rresp,s_axi_rdata}))
                fail("X/Z at AXI outputs");
            if (prev_bstall && (!s_axi_bvalid || s_axi_bresp !== prev_bresp))
                fail("B response changed under backpressure");
            if (prev_rstall && (!s_axi_rvalid || s_axi_rresp !== prev_rresp ||
                               s_axi_rdata !== prev_rdata))
                fail("R response changed under backpressure");
            if (s_axi_awvalid && s_axi_awready) aw_count = aw_count + 1;
            if (s_axi_wvalid && s_axi_wready) w_count = w_count + 1;
            if (s_axi_bvalid && s_axi_bready) b_count = b_count + 1;
            if (s_axi_arvalid && s_axi_arready) ar_count = ar_count + 1;
            if (s_axi_rvalid && s_axi_rready) r_count = r_count + 1;
            if (b_count > aw_count || b_count > w_count || r_count > ar_count)
                fail("Unsolicited or duplicate response");
            if ((aw_count-b_count)>1 || (w_count-b_count)>1 || (ar_count-r_count)>1)
                fail("More than one outstanding transaction");
            prev_bstall = s_axi_bvalid && !s_axi_bready;
            prev_rstall = s_axi_rvalid && !s_axi_rready;
            prev_bresp = s_axi_bresp; prev_rresp = s_axi_rresp; prev_rdata = s_axi_rdata;
        end
    end

    task automatic reset_dut;
        @(negedge clk);
        resetn = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_arvalid = 0;
        s_axi_bready = 0; s_axi_rready = 0;
        repeat (5) @(negedge clk);
        resetn = 1;
        repeat (3) @(negedge clk);
    endtask

    task automatic send_aw(input [11:0] addr, input integer delay_cycles);
        repeat (delay_cycles) @(negedge clk);
        @(negedge clk); s_axi_awaddr = addr; s_axi_awvalid = 1;
        do @(posedge clk); while (s_axi_awready !== 1);
        @(negedge clk); s_axi_awvalid = 0;
    endtask

    task automatic send_w(input [31:0] data, input [3:0] strb, input integer delay_cycles);
        repeat (delay_cycles) @(negedge clk);
        @(negedge clk); s_axi_wdata = data; s_axi_wstrb = strb; s_axi_wvalid = 1;
        do @(posedge clk); while (s_axi_wready !== 1);
        @(negedge clk); s_axi_wvalid = 0;
    endtask

    task automatic write_reg(input [11:0] addr, input [31:0] data,
                             input [3:0] strb, input integer aw_delay,
                             input integer w_delay, input integer stall,
                             input [1:0] expected_response);
        fork
            send_aw(addr, aw_delay);
            send_w(data, strb, w_delay);
        join
        wait (s_axi_bvalid === 1);
        repeat (stall) @(negedge clk);
        if (s_axi_bresp !== expected_response) fail($sformatf("Write response @%h", addr));
        @(negedge clk); s_axi_bready = 1;
        @(posedge clk);
        @(negedge clk); s_axi_bready = 0;
        checks = checks + 1;
    endtask

    task automatic read_reg(input [11:0] addr, input integer stall,
                            input [1:0] expected_response, output [31:0] data);
        @(negedge clk); s_axi_araddr = addr; s_axi_arvalid = 1;
        do @(posedge clk); while (s_axi_arready !== 1);
        @(negedge clk); s_axi_arvalid = 0;
        wait (s_axi_rvalid === 1);
        repeat (stall) @(negedge clk);
        if (s_axi_rresp !== expected_response) fail($sformatf("Read response @%h", addr));
        data = s_axi_rdata;
        @(negedge clk); s_axi_rready = 1;
        @(posedge clk);
        @(negedge clk); s_axi_rready = 0;
        checks = checks + 1;
    endtask

    task automatic expect_read(input [11:0] addr, input [31:0] expected);
        reg [31:0] data;
        read_reg(addr, 2, 0, data);
        if (data !== expected)
            fail($sformatf("Read @%h got=%h expected=%h", addr, data, expected));
    endtask

    task automatic wait_done;
        reg [31:0] status;
        integer polls;
        status = 0; polls = 0;
        while (!status[2] && polls < 100) begin
            read_reg(12'h01c, 0, 0, status);
            polls = polls + 1;
        end
        if (!status[2] || status[1]) fail("Command did not complete");
    endtask

    integer i, j, k, seed, rng_seed, order;
    reg [31:0] model, data, value, parallel_data;
    reg [3:0] strobe;
    initial begin
        $display("VITA_VIVADO_STAGE AXILT_REGISTERS");
        reset_dut();
        expect_read(0, 32'h41584c54);
        expect_read(4, 32'h00010000);
        expect_read(8, 1);
        expect_read(12'h01c, 1);
        expect_read(12'h030, 0);
        write_reg(12'h018, 1, 15, 0, 0, 0, 2); // seq=0 rejected
        write_reg(12'h018, 2, 15, 0, 0, 0, 2); // no result to ACK
        write_reg(12'h018, 3, 15, 0, 0, 0, 2);
        write_reg(12'h014, 1, 1, 0, 0, 0, 2);
        // All 16 byte-enable patterns, all channel arrival orders, three seeds.
        for (k = 0; k < 3; k = k + 1) begin
            seed = (k == 0) ? 1 : ((k == 1) ? 7 : 12345);
            rng_seed = seed;
            value = $urandom(rng_seed);
            write_reg(12'h00c, 0, 15, 0, 0, 0, 0);
            model = 0;
            for (i = 0; i < 512; i = i + 1) begin
                strobe = i % 16;
                order = i % 3;
                value = $urandom;
                write_reg(12'h00c, value, strobe,
                          (order == 1) ? 7 : 0, (order == 2) ? 9 : 0,
                          $urandom_range(0, 9), 0);
                for (j = 0; j < 4; j = j + 1)
                    if (strobe[j]) model[j*8 +: 8] = value[j*8 +: 8];
                expect_read(12'h00c, model);
            end
            $display("AXILT_RANDOM_SEED_PASS seed=%0d transactions=512", seed);
        end
        // Every unmapped/alignment address, both directions.
        for (i = 0; i < 4096; i = i + 1) begin
            if ((i % 4) != 0 || i > 12'h030) begin
                write_reg(i[11:0], 32'hffffffff, 15, 0, 0, 0, 2);
                read_reg(i[11:0], 0, 2, data);
                if (data !== 0) fail("Invalid read data not zero");
            end
        end
        for (i = 0; i <= 12'h030; i = i + 4) begin
            if (i != 12'h00c && i != 12'h010 && i != 12'h014 && i != 12'h018)
                write_reg(i[11:0], 32'hffffffff, 15, 0, 0, 0, 2);
        end
        // Independent read must complete while write response is backpressured.
        fork
            write_reg(12'h00c, 32'hcafe0123, 15, 0, 0, 30, 0);
            begin
                wait (s_axi_bvalid);
                expect_read(0, 32'h41584c54);
            end
        join
        // Exact same internal handshake cycle: old value is returned.
        write_reg(12'h00c, 32'h12345678, 15, 0, 0, 0, 0);
        fork
            write_reg(12'h00c, 32'h87654321, 15, 0, 0, 5, 0);
            begin
                wait (dut.u_slave.aw_full && dut.u_slave.w_full);
                read_reg(12'h00c, 5, 0, parallel_data);
            end
        join
        // The direct bank timing test below proves exact old-data semantics.
        expect_read(12'h00c, 32'h87654321);
        for (i = 1; i <= 1000; i = i + 1) begin
            value = $urandom;
            write_reg(12'h010, value, 15, 0, 0, 0, 0);
            write_reg(12'h014, i, 15, 0, 0, 0, 0);
            write_reg(12'h018, 1, 15, 0, 0, 0, 0);
            // Snapshot must survive a later TEST_INPUT change.
            write_reg(12'h010, ~value, 15, 0, 0, 0, 0);
            write_reg(12'h018, 1, 15, 0, 0, 0, 2);
            wait_done();
            expect_read(12'h020, i);
            expect_read(12'h024, i);
            expect_read(12'h028, ~value);
            expect_read(12'h030, i);
            write_reg(12'h014, i+1, 15, 0, 0, 0, 2);
            expect_read(12'h028, ~value);
            write_reg(12'h018, 2, 15, 0, 0, 0, 0);
            write_reg(12'h018, 1, 15, 0, 0, 0, 2);
        end
        // Max sequence accepts once; wrapped sequence must not execute.
        write_reg(12'h014, 32'hffffffff, 15, 0, 0, 0, 0);
        write_reg(12'h018, 1, 15, 0, 0, 0, 0);
        wait_done();
        write_reg(12'h018, 2, 15, 0, 0, 0, 0);
        write_reg(12'h014, 1, 15, 0, 0, 0, 0);
        write_reg(12'h018, 1, 15, 0, 0, 0, 2);
        // Reset with address only, data only, B pending, R pending, engine busy.
        send_aw(12'h00c, 0); reset_dut(); expect_read(12'h00c, 0);
        send_w(32'hbadc0ffe, 15, 0); reset_dut(); expect_read(12'h00c, 0);
        fork send_aw(12'h00c, 0); send_w(32'hbeef, 15, 0); join
        wait (s_axi_bvalid); reset_dut(); expect_read(12'h00c, 0);
        @(negedge clk); s_axi_araddr = 0; s_axi_arvalid = 1;
        do @(posedge clk); while (!s_axi_arready);
        @(negedge clk); s_axi_arvalid = 0;
        wait (s_axi_rvalid); reset_dut(); expect_read(12'h030, 0);
        write_reg(12'h014, 1, 15, 0, 0, 0, 0);
        write_reg(12'h018, 1, 15, 0, 0, 0, 0);
        reset_dut(); repeat (40) @(negedge clk);
        expect_read(12'h030, 0); expect_read(12'h01c, 1);
        wait (bank_done && delayed_done);
        $display("AXILT_REG_SIM_PASS checks=%0d commands=1001 seeds=1,7,12345", checks);
        $display("VITA_VIVADO_RESULT PASS");
        $display("EES_VIVADO_RESULT PASS");
        $finish;
    end

    // Direct register bank: same-cycle read/write and delayed consumers.
    reg bank_wv = 0, bank_rr = 0, bank_rv = 0, bank_wr = 0;
    wire bank_wready, bank_rready, bank_wvalid, bank_rvalid;
    wire [1:0] bank_bresp, bank_resp;
    wire [31:0] bank_data, bank_exec_input;
    wire bank_start;
    reg [31:0] bank_wdata = 0;
    reg bank_done = 0;
    axi_lite_reg_bank bank (
        .clk          (clk            ),
        .resetn       (resetn         ),
        .wr_valid     (bank_wv        ),
        .wr_ready     (bank_wready    ),
        .wr_addr      (12'h00c        ),
        .wr_data      (bank_wdata     ),
        .wr_strb      (4'hf           ),
        .wr_rsp_valid (bank_wvalid    ),
        .wr_rsp_ready (bank_wr        ),
        .wr_rsp       (bank_bresp     ),
        .rd_valid     (bank_rv        ),
        .rd_ready     (bank_rready    ),
        .rd_addr      (12'h00c        ),
        .rd_rsp_valid (bank_rvalid    ),
        .rd_rsp_ready (bank_rr        ),
        .rd_data      (bank_data      ),
        .rd_rsp       (bank_resp      ),
        .exec_start   (bank_start     ),
        .exec_input   (bank_exec_input),
        .exec_done    (1'b0           ),
        .exec_result  (32'b0          )
    );
    initial begin
        wait (resetn);
        wait (bank_wready && bank_rready);
        @(negedge clk);
        bank_wv = 1; bank_rv = 1; bank_wdata = 32'h1234abcd;
        @(negedge clk); bank_wv = 0; bank_rv = 0;
        repeat (10) begin
            @(negedge clk);
            if (bank_rvalid !== 1 || bank_wvalid !== 1 ||
                bank_data !== 0 || bank_resp !== 0 || bank_bresp !== 0)
                fail("Direct bank old-data/response-hold semantics");
        end
        bank_wr = 1; bank_rr = 1;
        @(negedge clk); bank_wr = 0; bank_rr = 0;
        wait (bank_rready);
        @(negedge clk); bank_rv = 1;
        @(negedge clk); bank_rv = 0;
        wait (bank_rvalid);
        if (bank_data !== 32'h1234abcd) fail("Direct bank write missing");
        bank_done = 1;
    end
    initial begin
        #50000000;
        fail("Simulation watchdog");
    end
endmodule
