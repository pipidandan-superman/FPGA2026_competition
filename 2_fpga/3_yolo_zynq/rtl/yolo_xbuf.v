/************************************************************************
 * File Name       : yolo_xbuf.v
 * Developer       : LSL
 * Date            : 2026-09-15
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_xbuf
 * Description     : M4 X-tile double-buffered column store (architecture
 *                   baseline section 3.3): N_COLS (=N_EDGE) independent
 *                   K-deep byte memories per bank, column organization
 *                   mirroring yolo_wbuf's row organization. Read side
 *                   broadcasts one byte per column at a shared k address
 *                   every cycle (the array's X column broadcast) to pair
 *                   with the W row broadcast in the multiply wall.
 *
 *                   Double buffering: writes target wr_bank_i (the
 *                   inactive bank during a tile), reads follow rd_bank_i
 *                   (ctrl switches it at tile boundaries) -- concurrent
 *                   write/read on opposite banks must not interact.
 *
 *                   No parameters ride with the tile (requant params
 *                   belong to W rows only). Unwritten addresses read
 *                   as x; stimulus must not read them.
 *
 *                   Write:  we_i 1 cycle 1 byte -> mem[wr_bank][wcol][waddr]
 *                   Read:   ren_i/raddr_i 1-cycle synchronous broadcast;
 *                   dout_vld_o = ren_i delayed; en=0 holds outputs.
 *
 *                   V2.0 (M12 B0 fix, 2026-09-16): storage replaced by
 *                   two blk_mem_gen IP instances (native Xilinx IP per
 *                   project directive) -- the structural view of the
 *                   old per-column LUTRAM wall was 16 columns x 2 banks
 *                   x 2304-deep x 8-bit = a 2304 x 128 simple-dual-port
 *                   byte-write memory, which OOC mapped to 13824 LUTRAM
 *                   (RAM64M, ooc_dbg1 hierarchical util). Per bank now
 *                   one BMG (Write 128 x 2304, Read 128, SDP, 16 x 8-bit
 *                   byte-write enables, PortA Write_Mode=Read_First,
 *                   no PortB output registers -> read latency 1 cycle,
 *                   PortA always enabled, PortB ENB pin) -- IP:
 *                   ip/yolo_xbuf_bmg (gen_xbuf_bmg.tcl).
 *
 *                   V2.1 (B0 dbg7c timing, 2026-09-16): rd_bank_q and
 *                   rd_active_q each drive a 128-wide output mux (and
 *                   rd_active_q the whole 128-bit zero gate) -- the
 *                   bank-select broadcast was the -10.8ns xbuf owner
 *                   (ooc_v13: ox_r_reg -> xbuf BRAM DIADI, 10 levels).
 *                   Both regs now carry (* max_fanout = 8 *) so synthesis
 *                   replicates them; zero-function change (pure routing).
 *
 *                   V2.2 (2026-09-17, B0 dbg8g/授权合同): BMG
 *                   Register_PortB_Output_of_Memory_Primitives=true
 *                   (gen_xbuf_bmg_v22.tcl) -- read latency 1 -> 2. The
 *                   dedicated MB pipeline register absorbs the
 *                   BMG-primitive-output -> PE DSP route tier (dbg8f/g
 *                   PE -0.87/-0.69ns 2L route-bound owner). Hold
 *                   semantics preserved (ENB=0 holds the output reg);
 *                   dout_vld_o now a 2-stage delay; consumers (PE wall)
 *                   realign via gemm_array V1.6 W staging + ctrl V1.8
 *                   S_DRAIN 4. M4 golden regenerated (delay shift only,
 *                   numeric bytes unchanged).
 *
 * Byte-column write over a 128-bit word: DINA is the
 *                   one-byte broadcast {16{wdata}} and WEA is the
 *                   one-hot column decode -- identical single-byte
 *                   write semantics at the same addresses.
 *
 *                   Equivalence points proven against the frozen M4
 *                   stimulus audit (sim/xbuf_stim_audit.py, 97464 ops):
 *                     - 433 write ops precede the first read, all
 *                       expecting dout=0: rd_active_q gates the output
 *                       mux to constant 0 until the first read (BMG's
 *                       DOUTB power-up value is model-internal and is
 *                       deliberately not relied on).
 *                     - rd_bank changes on 85859 hold (ren=0) cycles:
 *                       the read-side bank select is a REGISTERED
 *                       rd_bank_q that only updates on a read, so the
 *                       output holds the last-read bank's held DOUTB --
 *                       same hold semantics as the V1.0 per-column
 *                       register (which never resampled on en=0).
 *                     - 0 same-bank same-address write+read collisions
 *                       in the stimulus; PortA=Read_First still keeps
 *                       the V1.0 nonblocking-read-old-data semantics
 *                       for real traffic collisions.
 *                   External contract (ports, timing, reset behaviour)
 *                   unchanged; 数值路径不变.
 * Dependencies    : ip/yolo_xbuf_bmg (blk_mem_gen v8.4;
 *                   xsim: precompiled -L blk_mem_gen_v8_4_12)
 * Revision History:
 *   - V1.0 (2026-09-15) by LSL : Initial release (M4).
 *   - V2.0 (2026-09-16) by LSL : per-column LUTRAM -> 2x blk_mem_gen
 *     IP (M12 B0; frees 13824 LUTRAM, xbuf now in BRAM). Wrapper
 *     equivalence pinned by stim audit + M4 gate rerun.
 *   - V2.1 (2026-09-16) by LSL : (* max_fanout = 8 *) on rd_bank_q /
 *     rd_active_q (B0 dbg7c -10.8ns output-mux broadcast fix; pure
 *     replication, no function change). Gate: M4/M10/M11 chain.
 *   - V2.2 (2026-09-17) by LSL : BMG 端口 B 源语输出寄存打开（读延迟
 *     1→2；dout_vld_o 两级延迟），2026-09-17 用户授权的合同变更。消
 *     dbg8f/g PE −0.87/−0.69ns 2L 布线 owner（BMG 源语输出→DSP A）。
 *     保持语义：ENB=0 输出寄存器保持；首读前 rd_active_q 门 0 不变。
 *     门重跑：M4 黄金再生成 + M10 + B0 v18（M11 收敛后单跑）。
 ************************************************************************/

module yolo_xbuf #(
    parameter N_COLS = 16,                  // N_EDGE columns
    parameter K_MAX  = 2304,                // deepest K tier
    parameter AW     = 12,                  // ceil(log2 2304)
    parameter COL_AW = 5                    // ceil(log2 N_COLS)
) (
    input  wire              clk_i,
    input  wire              rst_n,
    // DMA write side (targets the inactive bank)
    input  wire              we_i,
    input  wire              wr_bank_i,
    input  wire [COL_AW-1:0] wcol_i,
    input  wire [AW-1:0]     waddr_i,       // k index
    input  wire [7:0]        wdata_i,
    // array read side (active bank)
    input  wire              rd_bank_i,
    input  wire              ren_i,
    input  wire [AW-1:0]     raddr_i,       // k index
    output wire [N_COLS*8-1:0] dout_o,      // one byte per column
    output reg               dout_vld_o
);

    // ---- write side: one-byte-column write over the 128-bit BMG word.
    //      DINA broadcasts the byte to all 16 lanes; WEA enables only
    //      the addressed column lane, and only on the selected bank. ----
    wire [N_COLS*8-1:0] dina_bc = {N_COLS{wdata_i}};
    wire [N_COLS-1:0]   we_col  = {{(N_COLS-1){1'b0}}, 1'b1} << wcol_i;
    wire [N_COLS-1:0]   wea0    = (wr_bank_i == 1'b0) ? ({N_COLS{we_i}} & we_col) : {N_COLS{1'b0}};
    wire [N_COLS-1:0]   wea1    = (wr_bank_i == 1'b1) ? ({N_COLS{we_i}} & we_col) : {N_COLS{1'b0}};

    wire [N_COLS*8-1:0] doutb0, doutb1;

    // ---- bank 0 / bank 1: BMG SDP, read latency 1, ENB hold ----
    yolo_xbuf_bmg u_bank0 (
        .clka   (clk_i),
        .wea    (wea0),
        .addra  (waddr_i),
        .dina   (dina_bc),
        .clkb   (clk_i),
        .enb    (ren_i),
        .addrb  (raddr_i),
        .doutb  (doutb0)
    );

    yolo_xbuf_bmg u_bank1 (
        .clka   (clk_i),
        .wea    (wea1),
        .addra  (waddr_i),
        .dina   (dina_bc),
        .clkb   (clk_i),
        .enb    (ren_i),
        .addrb  (raddr_i),
        .doutb  (doutb1)
    );

    // ---- read-side bank select: registered, updates only on a read so
    //      hold cycles (ren=0) keep showing the last-read bank's held
    //      data regardless of rd_bank_i wander (audit: 85859 such ops).
    //      V2.1: max_fanout lets synthesis replicate the select reg
    //      across the 128-bit output mux (was a -10.8ns broadcast). ----
    (* max_fanout = 8 *) reg rd_bank_q;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rd_bank_q <= 1'b0;
        end else if (ren_i) begin
            rd_bank_q <= rd_bank_i;
        end
    end

    // ---- output gating before the first read: the frozen gate expects
    //      dout=0 on the 433 leading write cycles; do not rely on the
    //      BMG model's power-up DOUTB. Sticky once the first read lands
    //      (data and flag update on the same edge). V2.1: replicated
    //      like rd_bank_q (zero-gate fanout over the full 128 bits). ----
    (* max_fanout = 8 *) reg rd_active_q;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rd_active_q <= 1'b0;
        end else if (ren_i) begin
            rd_active_q <= 1'b1;
        end
    end

    assign dout_o = rd_active_q ? (rd_bank_q ? doutb1 : doutb0)
                                : {N_COLS*8{1'b0}};

    // read valid: ren_i delayed 2 cycles (V2.2: BMG primitives output
    // register ON -> data path latency 2; hold semantics via BMG's own
    // ENB-gated output register)
    reg ren_d1_r;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            ren_d1_r    <= 1'b0;
            dout_vld_o  <= 1'b0;
        end else begin
            ren_d1_r   <= ren_i;
            dout_vld_o <= ren_d1_r;
        end
    end

endmodule
