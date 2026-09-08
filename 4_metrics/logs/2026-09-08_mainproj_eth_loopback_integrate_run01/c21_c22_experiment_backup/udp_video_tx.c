/************************************************************************
 * File Name       : udp_video_tx.c
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : udp_video_tx
 * Description     : UDP video sender, C2.1 optimized. The caller copies a
 *                   completed camera frame into a private stable buffer and
 *                   submits it together with its whole-frame CRC32; the
 *                   sender emits 640 datagrams (32 B header + 1440 B data)
 *                   per frame as zero-copy pbuf chains (32 B header pbuf in
 *                   RAM + data pbuf referencing the submitted buffer), one
 *                   frame per UDP_TX_FRAME_INTERVAL_MS.
 * Dependencies    : lwip220 RAW API
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release, pattern source only.
 *   - V1.1 (2026-09-08) by LSL : C1 camera source + D-cache invalidate.
 *   - V2.0 (2026-09-08) by LSL : C2.1 — CRC supplied by caller (fused into
 *     the chunked snapshot copy), zero-copy data pbufs referencing the
 *     submitted buffer; removed the per-frame 921 KB pbuf byte copy and the
 *     internal CRC pass; removed dead pattern-source code (kept in git).
 ************************************************************************/

#include "xil_printf.h"
#include "lwip/udp.h"
#include "udp_video_tx.h"

/* Provided by main.c: keeps ARP/ICMP and RX alive mid-burst without
 * re-entering the sender poll (no recursion). */
extern void udp_video_tx_yield(void);

#define TX_MAGIC_0 0x4FU /* 'O' */
#define TX_MAGIC_1 0x56U /* 'V' */
#define TX_MAGIC_2 0x35U /* '5' */
#define TX_MAGIC_3 0x36U /* '6' */
#define TX_VERSION 0x01U
#define TX_TYPE_CAMERA 0x01U
#define TX_FLAG_SOF 0x0001U
#define TX_FLAG_EOF 0x0002U

#define TX_WIDTH 640U
#define TX_HEIGHT 480U
#define TX_STRIDE (TX_WIDTH * 3U)
#define TX_FRAME_BYTES (TX_HEIGHT * TX_STRIDE) /* 921600 */
#define TX_PAYLOAD 1440U
#define TX_PACKETS (TX_FRAME_BYTES / TX_PAYLOAD) /* 640 */
#define TX_BURST_CHUNK 32U              /* packets between stack service */
#define TX_BURST_PACING_US 600U         /* gap per chunk: spreads the ~971 KB
                                           frame over ~20 ms so the PC socket
                                           buffer is never overrun */

#define TX_PEER_IP0 192
#define TX_PEER_IP1 168
#define TX_PEER_IP2 240
#define TX_PEER_IP3 2

static struct udp_pcb *tx_pcb = NULL;
static ip_addr_t tx_peer;
static uint32_t tx_frame_id = 0;
static uint32_t tx_last_ms = 0;
static uint32_t tx_sent_frames = 0;
static uint32_t tx_sent_packets = 0;
static uint32_t tx_errors = 0;
static uint32_t tx_ready = 0;
static const unsigned char *tx_pending = NULL;
static uint32_t tx_pending_crc = 0;

static void fill_header(unsigned char *header, uint32_t frame_id, uint32_t frame_crc,
                        uint32_t pid, uint32_t plen, uint32_t flags, uint32_t ts_us)
{
    header[0] = TX_MAGIC_0;
    header[1] = TX_MAGIC_1;
    header[2] = TX_MAGIC_2;
    header[3] = TX_MAGIC_3;
    header[4] = TX_VERSION;
    header[5] = TX_TYPE_CAMERA;
    header[6] = (unsigned char)(flags >> 8);
    header[7] = (unsigned char)(flags & 0xFFU);
    header[8] = (unsigned char)(frame_id >> 24);
    header[9] = (unsigned char)(frame_id >> 16);
    header[10] = (unsigned char)(frame_id >> 8);
    header[11] = (unsigned char)frame_id;
    header[12] = (unsigned char)(pid >> 8);
    header[13] = (unsigned char)pid;
    header[14] = (unsigned char)(TX_PACKETS >> 8);
    header[15] = (unsigned char)TX_PACKETS;
    header[16] = (unsigned char)(plen >> 8);
    header[17] = (unsigned char)plen;
    header[18] = (unsigned char)(TX_WIDTH >> 8);
    header[19] = (unsigned char)TX_WIDTH;
    header[20] = (unsigned char)(TX_STRIDE >> 8);
    header[21] = (unsigned char)TX_STRIDE;
    header[22] = (unsigned char)(ts_us >> 24);
    header[23] = (unsigned char)(ts_us >> 16);
    header[24] = (unsigned char)(ts_us >> 8);
    header[25] = (unsigned char)ts_us;
    header[28] = 0;
    header[29] = 0;
    header[30] = 0;
    header[31] = 0;
    header[28] = (unsigned char)(frame_crc >> 24);
    header[29] = (unsigned char)(frame_crc >> 16);
    header[30] = (unsigned char)(frame_crc >> 8);
    header[31] = (unsigned char)frame_crc;
}

static void send_one_frame(const unsigned char *src, uint32_t frame_crc, uint32_t frame_id)
{
    uint32_t pid;
    uint32_t since_service = 0;

    for (pid = 0; pid < TX_PACKETS; ++pid) {
        struct pbuf *pb = pbuf_alloc(PBUF_TRANSPORT, 32U, PBUF_RAM);
        struct pbuf *db;
        unsigned char *payload;
        uint32_t flags = 0;
        err_t err;

        if (pb == NULL) {
            tx_errors++;
            return;
        }
        if (pid == 0) {
            flags |= TX_FLAG_SOF;
        }
        if (pid == TX_PACKETS - 1) {
            flags |= TX_FLAG_EOF;
        }
        fill_header((unsigned char *)pb->payload, frame_id, frame_crc,
                    pid, TX_PAYLOAD, flags, (uint32_t)(frame_id * 66666U));

        /* Zero-copy: the data pbuf references the snapshot buffer directly,
         * so the 1440 B payload is never copied by the CPU. */
        db = pbuf_alloc(PBUF_RAW, TX_PAYLOAD, PBUF_REF);
        if (db == NULL) {
            pbuf_free(pb);
            tx_errors++;
            return;
        }
        db->payload = (void *)(uintptr_t)(src + pid * TX_PAYLOAD);
        db->len = TX_PAYLOAD;
        db->tot_len = TX_PAYLOAD;
        pbuf_chain(pb, db);
        pbuf_free(db); /* the chain keeps the reference */

        err = udp_sendto(tx_pcb, pb, &tx_peer, 5000);
        pbuf_free(pb);
        if (err != ERR_OK) {
            tx_errors++;
        } else {
            tx_sent_packets++;
        }
        since_service++;
        if (since_service >= TX_BURST_CHUNK) {
            /* Yield so ARP/ICMP and RX keep living mid-burst. */
            udp_video_tx_yield();
            since_service = 0;
        }
    }
    tx_sent_frames++;
    xil_printf("UDP_TX frame=%u packets=%u errors=%u\r\n",
               frame_id, TX_PACKETS, tx_errors);
}

void udp_video_tx_init(void)
{
    IP4_ADDR(&tx_peer, TX_PEER_IP0, TX_PEER_IP1, TX_PEER_IP2, TX_PEER_IP3);
    tx_pcb = udp_new();
    if (tx_pcb == NULL) {
        xil_printf("UDP_TX pcb_alloc_fail\r\n");
        return;
    }
    udp_bind(tx_pcb, IP_ANY_TYPE, 5001);
    tx_ready = 1;
    tx_last_ms = 0;
    xil_printf("UDP_TX_INIT_OK peer=%u.%u.%u.%u:5000 frame=%uB/%upkt interval=%ums\r\n",
               TX_PEER_IP0, TX_PEER_IP1, TX_PEER_IP2, TX_PEER_IP3,
               TX_FRAME_BYTES, TX_PACKETS, UDP_TX_FRAME_INTERVAL_MS);
}

void udp_video_tx_submit(const unsigned char *frame, uint32_t frame_crc)
{
    /* Latest-wins: the sender emits the freshest submitted snapshot. */
    tx_pending = frame;
    tx_pending_crc = frame_crc;
}

uint32_t udp_video_tx_pending(void)
{
    return (tx_pending != NULL) ? 1U : 0U;
}

void udp_video_tx_poll(uint32_t now_ms)
{
    if (tx_ready == 0U) {
        return;
    }
    if ((now_ms - tx_last_ms) < UDP_TX_FRAME_INTERVAL_MS) {
        return;
    }
    tx_last_ms = now_ms;
    if (tx_pending != NULL) {
        send_one_frame(tx_pending, tx_pending_crc, tx_frame_id);
        tx_frame_id++;
        tx_pending = NULL;
    }
}
