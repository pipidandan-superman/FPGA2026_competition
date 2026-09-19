/************************************************************************
 * File Name       : yolo_csr_pkg.sv
 * Developer       : LSL
 * Date            : 2026-09-18
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : yolo_csr_pkg
 * Description     : YOLO control subsystem register contract package.
 *                   Single source of truth for address map, field
 *                   layout and table geometry. See
 *                   1_docs/yolo_axi_lite_csr_design_20260918.md.
 * Dependencies    : None
 * Revision History:
 *   - V1.0 (2026-09-18) by LSL : Initial release
 ************************************************************************/
`timescale 1ns / 1ps

package yolo_csr_pkg;

    // ------------------------------------------------------------ --
    // Module identity
    // ------------------------------------------------------------ --
    localparam [31:0] YOLO_ID_VALUE = 32'h594F4C32; // "YOL2"
    localparam [31:0] YOLO_VERSION  = 32'h0300;     // major 0, minor 0x300

    // ------------------------------------------------------------ --
    // Capability constants (reported by CAP0 / CAP1)
    // ------------------------------------------------------------ --
    localparam [7:0]  CAP_OC_TILES   = 8'd4;
    localparam [7:0]  CAP_N_TILES    = 8'd4;
    localparam [7:0]  CAP_PE_LANES   = 8'd16;
    localparam        CAP_GRAPH_OP   = 1'b1;
    localparam        CAP_HEAD_DMA   = 1'b1;
    localparam        CAP_IRQ        = 1'b1;

    // ------------------------------------------------------------ --
    // Table geometry
    //   descriptor : 128 items x 32 words (128 B)  = 16 KB BRAM
    //   buffer     : 128 items x  8 words ( 32 B)  =  4 KB BRAM
    //   quant      : 256 profiles x 4 words (16 B) =  4 KB BRAM
    //   SiLU LUT   : 16 banks x 256 x 8 bit        =  4 KB BRAM
    //                (BRAM everywhere per user directive: resource
    //                 is plentiful on 7020 and latency is uniform)
    //   result ring: 32 items x 16 words (64 B)    =  2 KB BRAM
    // ------------------------------------------------------------ --
    localparam int DESC_ITEMS = 128;
    localparam int DESC_WORDS = 32;
    localparam int DESC_DEPTH = DESC_ITEMS * DESC_WORDS; // 4096 words

    localparam int BUF_ITEMS  = 128;
    localparam int BUF_WORDS  = 8;
    localparam int BUF_DEPTH  = BUF_ITEMS * BUF_WORDS;   // 1024 words

    localparam int QUANT_DEPTH = 1024;                   // 256 profiles x 4

    localparam int LUT_BANKS   = 16;
    localparam int LUT_ENTRIES = 256;                    // x 8 bit, 4 bytes/word
    localparam int LUT_DEPTH   = LUT_BANKS * (LUT_ENTRIES / 4); // 1024 words

    localparam int RING_ITEMS = 32;
    localparam int RING_WORDS = 16;                      // 64 B per entry
    localparam int RING_DEPTH = RING_ITEMS * RING_WORDS; // 512 words

    // ------------------------------------------------------------ --
    // Table read latency (in cycles) from registered read address to
    // valid read data.  Behavioural inference = 1 (equivalent to BMG
    // with primitives output register DISABLED).  If a table is later
    // migrated to a Block Memory Generator IP with output register
    // enabled, change to 2 and the surrounding ack logic adapts via
    // this parameter.
    // ------------------------------------------------------------ --
    localparam int TABLE_RD_LATENCY = 1;

    // ------------------------------------------------------------ --
    // Fixed register offsets (byte offset from 0x43C1_0000)
    // ------------------------------------------------------------ --
    // identity / capability / global control
    localparam [15:0] A_ID              = 16'h000; // R
    localparam [15:0] A_VERSION         = 16'h004; // R
    localparam [15:0] A_CAP0            = 16'h008; // R
    localparam [15:0] A_CAP1            = 16'h00C; // R
    localparam [15:0] A_CTRL            = 16'h010; // W  pulse/latch
    localparam [15:0] A_STATUS          = 16'h014; // R
    localparam [15:0] A_ERROR_STATUS    = 16'h018; // R/W1C
    localparam [15:0] A_ERROR_INFO      = 16'h01C; // R
    localparam [15:0] A_MODEL_ID        = 16'h020; // RW
    localparam [15:0] A_GRAPH_CRC       = 16'h024; // RW
    localparam [15:0] A_FRAME_ID        = 16'h028; // RW
    localparam [15:0] A_FRAME_CFG       = 16'h02C; // RW
    localparam [15:0] A_INPUT_BASE_LO   = 16'h030; // RW
    localparam [15:0] A_INPUT_BASE_HI   = 16'h034; // RW
    localparam [15:0] A_INPUT_STRIDE    = 16'h038; // RW
    // output / PS result interface
    localparam [15:0] A_HEAD_BASE_LO    = 16'h040; // RW
    localparam [15:0] A_HEAD_BASE_HI    = 16'h044; // RW
    localparam [15:0] A_HEAD_STRIDE     = 16'h048; // RW
    localparam [15:0] A_HEAD_BYTES      = 16'h04C; // R
    localparam [15:0] A_HEAD_FORMAT     = 16'h050; // RW
    localparam [15:0] A_RESULT_SEQ      = 16'h054; // R
    localparam [15:0] A_RESULT_FRAME_ID = 16'h058; // R
    localparam [15:0] A_RESULT_STATUS   = 16'h05C; // R/W1C
    localparam [15:0] A_RESULT_ACK      = 16'h060; // W
    localparam [15:0] A_RESULT_RING_HEAD= 16'h064; // R
    localparam [15:0] A_RESULT_RING_TAIL= 16'h068; // RW
    localparam [15:0] A_RESULT_MAX_DET  = 16'h06C; // RW
    localparam [15:0] A_RESULT_CONF_Q   = 16'h070; // RW
    // scheduler / descriptor queue
    localparam [15:0] A_DESC_CFG        = 16'h100; // RW
    localparam [15:0] A_DESC_BASE       = 16'h104; // RW aperture window base (word)
    localparam [15:0] A_DESC_COUNT      = 16'h108; // RW
    localparam [15:0] A_DESC_HEAD       = 16'h10C; // R
    localparam [15:0] A_DESC_TAIL       = 16'h110; // RW
    localparam [15:0] A_DESC_DOORBELL   = 16'h114; // W
    localparam [15:0] A_DESC_CURRENT    = 16'h118; // R
    localparam [15:0] A_DESC_DONE_COUNT = 16'h11C; // R
    localparam [15:0] A_DESC_ERROR_ID   = 16'h120; // R
    localparam [15:0] A_SCHED_CFG       = 16'h124; // RW
    localparam [15:0] A_SCHED_STATUS    = 16'h128; // R
    // dma / cache / performance
    localparam [15:0] A_DMA_CFG         = 16'h200; // RW
    localparam [15:0] A_DMA_STATUS      = 16'h204; // R
    localparam [15:0] A_DMA_RD_BYTES    = 16'h208; // R
    localparam [15:0] A_DMA_WR_BYTES    = 16'h20C; // R
    localparam [15:0] A_CACHE_STATUS    = 16'h210; // R
    localparam [15:0] A_PERF_CYCLES     = 16'h214; // R
    localparam [15:0] A_PERF_MACS_LO    = 16'h218; // R
    localparam [15:0] A_PERF_MACS_HI    = 16'h21C; // R
    localparam [15:0] A_PERF_STALL      = 16'h220; // R
    localparam [15:0] A_PERF_CLEAR      = 16'h224; // W

    // ------------------------------------------------------------ --
    // Aperture window offsets (byte)
    // ------------------------------------------------------------ --
    localparam [15:0] A_DESC_WIN  = 16'h1000; // ..0x2FFF 8 KB window into 16 KB table
    localparam [15:0] A_BUF_WIN   = 16'h3000; // ..0x3FFF 4 KB
    localparam [15:0] A_QUANT_WIN = 16'h4000; // ..0x4FFF 4 KB
    localparam [15:0] A_LUT_WIN   = 16'h5000; // ..0x5FFF 4 KB
    localparam [15:0] A_RING_WIN  = 16'h6000; // ..0x67FF 2 KB (upper half unmapped)
    localparam [15:0] A_DEBUG_WIN = 16'h7000; // ..0x7FFF optional, reads 0

    // ------------------------------------------------------------ --
    // ERROR_STATUS bits (W1C)
    // ------------------------------------------------------------ --
    localparam int E_BIT_AXI_LITE = 0;
    localparam int E_BIT_DMA_RD   = 1;
    localparam int E_BIT_DMA_WR   = 2;
    localparam int E_BIT_DESC     = 3;
    localparam int E_BIT_BUFFER   = 4;
    localparam int E_BIT_QUANT    = 5;
    localparam int E_BIT_LUT      = 6;
    localparam int E_BIT_TIMEOUT  = 7;
    localparam int E_BIT_OVERFLOW = 8;
    localparam int E_BIT_PROTOCOL = 9;

    // error codes (ERROR_INFO[7:0])
    localparam [7:0] E_CODE_DESC_INVALID = 8'h01;
    localparam [7:0] E_CODE_RING_OVF     = 8'h10;
    localparam [7:0] E_CODE_RING_RO      = 8'h11; // write to read-only ring window
    localparam [7:0] E_CODE_TABLE_RUN    = 8'h12; // table write while running
    localparam [7:0] E_CODE_ADDR_ALIGN   = 8'h13;
    localparam [7:0] E_CODE_ADDR_REGION  = 8'h14;
    localparam [7:0] E_CODE_ACK_EMPTY    = 8'h15; // ack on empty result ring

    // ------------------------------------------------------------ --
    // Descriptor word0 field layout (defined by this contract)
    //   [7:0]  opcode
    //   [8]    valid
    //   [9]    last (force frame end after this item)
    //   [10]   first
    //   [11]   activation enable
    //   [12]   walk mode
    //   [15:13] ownership
    // word1 [7:0] descriptor id, [15:8] dependency id, [31:16] next id
    // word2 input0/input1/output buffer id  [9:0]/[19:10]/[29:20]
    // word14 expected output bytes
    // ------------------------------------------------------------ --

    // ------------------------------------------------------------ --
    // Result ring entry layout (16 words)
    //   w0  frame_id
    //   w1  result_seq
    //   w2  head_base lo   w3 head_base hi
    //   w4  head_bytes
    //   w5  scale0 shape   w6 scale1 shape   w7 scale2 shape
    //   w8  [7:0] quant profile, [23:16] stride mask
    //   w9  crc
    //   w10 [0] valid, [1] overflow, [2] dropped, [3] crc_ok, [4] ps_owned
    //   w11..w15 reserved
    // ------------------------------------------------------------ --

endpackage
