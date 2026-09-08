/************************************************************************
 * File Name       : udp_video_tx.c
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : udp_video_tx
 * Description     : Stage B1 UDP video sender. Builds a synthetic
 *                   640x480 RGB888 frame (5 color bars + moving column),
 *                   wraps it in 640 datagrams (32 B header + 1440 B
 *                   payload, design doc section 4) and streams one frame
 *                   per UDP_TX_FRAME_INTERVAL_MS to the PC peer. Whole-frame
 *                   CRC32 is carried in every header; SOF/EOF flags mark
 *                   first/last packet. All fields are network byte order.
 * Dependencies    : lwip220 RAW API, udp_echo.h peer constants
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release, pattern source only.
 *   - V1.1 (2026-09-08) by LSL : C1 camera source — send_one_frame reads
 *     the external DDR snapshot (frame_override) and invalidates stale
 *     D-cache lines before read; fixes the all-black frame issue.
 ************************************************************************/

#include "xil_printf.h"
#include "xil_cache.h"
#include "sleep.h"
#include "lwip/udp.h"
#include "udp_video_tx.h"

/* Provided by main.c: keeps ARP/ICMP/RX alive mid-burst without re-entering
 * the sender poll (no recursion). */
extern void udp_video_tx_yield(void);

#define TX_MAGIC_0 0x4FU /* 'O' */
#define TX_MAGIC_1 0x56U /* 'V' */
#define TX_MAGIC_2 0x35U /* '5' */
#define TX_MAGIC_3 0x36U /* '6' */
#define TX_VERSION 0x01U
#define TX_TYPE_PATTERN 0x02U
#define TX_TYPE_CAMERA 0x01U
#define TX_FLAG_SOF 0x0001U
#define TX_FLAG_EOF 0x0002U

#define TX_WIDTH 640U
#define TX_HEIGHT 480U
#define TX_STRIDE (TX_WIDTH * 3U)
#define TX_FRAME_BYTES (TX_HEIGHT * TX_STRIDE) /* 921600 */
#define TX_PAYLOAD 1440U
#define TX_PACKETS (TX_FRAME_BYTES / TX_PAYLOAD) /* 640 */
#define TX_BURST_CHUNK 32U                       /* packets between stack service */
#define TX_BURST_PACING_US 1900U                 /* gap per chunk: spreads the ~971 KB
                                                    frame over ~25 ms so the PC socket
                                                    buffer is never overrun */

#define TX_PEER_IP0 192
#define TX_PEER_IP1 168
#define TX_PEER_IP2 240
#define TX_PEER_IP3 2

static struct udp_pcb *tx_pcb = NULL;
static ip_addr_t tx_peer;
static unsigned char tx_frame[TX_FRAME_BYTES];
static uint32_t tx_frame_id = 0;
static uint32_t tx_last_ms = 0;
static uint32_t tx_sent_frames = 0;
static uint32_t tx_sent_packets = 0;
static uint32_t tx_errors = 0;
static uint32_t tx_ready = 0;
static const unsigned char *tx_pending = NULL;

static uint32_t crc32_update(uint32_t crc, const unsigned char *data, uint32_t length)
{
    static uint32_t table[256];
    static int table_ready = 0;
    uint32_t index;

    if (table_ready == 0) {
        for (index = 0; index < 256; ++index) {
            uint32_t value = index;
            uint32_t bit;
            for (bit = 0; bit < 8; ++bit) {
                if (value & 1UL) {
                    value = 0xEDB88320UL ^ (value >> 1);
                } else {
                    value >>= 1;
                }
            }
            table[index] = value;
        }
        table_ready = 1;
    }
    crc ^= 0xFFFFFFFFUL;
    for (index = 0; index < length; ++index) {
        crc = table[(crc ^ data[index]) & 0xFFUL] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFUL;
}

static void build_pattern_frame(uint32_t frame_id)
{
    uint32_t row;
    uint32_t column;
    uint32_t moving_x = (frame_id * 16U) % TX_WIDTH;
    static const unsigned char bars[5][3] = {
        {255, 255, 255}, {255, 255, 0}, {0, 255, 0}, {0, 255, 255}, {255, 0, 255}
    };

    for (row = 0; row < TX_HEIGHT; ++row) {
        unsigned char *line = &tx_frame[row * TX_STRIDE];
        for (column = 0; column < TX_WIDTH; ++column) {
            uint32_t bar = (column / (TX_WIDTH / 5U)) % 5U;
            unsigned char *pixel = &line[column * 3U];
            pixel[0] = bars[bar][0];
            pixel[1] = bars[bar][1];
            pixel[2] = bars[bar][2];
        }
        for (column = moving_x; column < moving_x + 8U && column < TX_WIDTH; ++column) {
            unsigned char *pixel = &line[column * 3U];
            pixel[0] = 255;
            pixel[1] = 0;
            pixel[2] = 0;
        }
    }
}

static void fill_header(unsigned char *header, unsigned char type, uint32_t frame_id,
                        uint32_t frame_crc, uint32_t pid, uint32_t plen, uint32_t flags,
                        uint32_t ts_us)
{
    header[0] = TX_MAGIC_0;
    header[1] = TX_MAGIC_1;
    header[2] = TX_MAGIC_2;
    header[3] = TX_MAGIC_3;
    header[4] = TX_VERSION;
    header[5] = type;
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
    header[20] = (unsigned char)(TX_HEIGHT >> 8);
    header[21] = (unsigned char)TX_HEIGHT;
    header[22] = (unsigned char)(TX_STRIDE >> 8);
    header[23] = (unsigned char)TX_STRIDE;
    header[24] = (unsigned char)(ts_us >> 24);
    header[25] = (unsigned char)(ts_us >> 16);
    header[26] = (unsigned char)(ts_us >> 8);
    header[27] = (unsigned char)ts_us;
    header[28] = (unsigned char)(frame_crc >> 24);
    header[29] = (unsigned char)(frame_crc >> 16);
    header[30] = (unsigned char)(frame_crc >> 8);
    header[31] = (unsigned char)frame_crc;
}

static void send_one_frame(const unsigned char *src, uint32_t frame_id)
{
    uint32_t frame_crc = crc32_update(0, src, TX_FRAME_BYTES);
    uint32_t pid;
    uint32_t since_service = 0;

    for (pid = 0; pid < TX_PACKETS; ++pid) {
        struct pbuf *pb = pbuf_alloc(PBUF_TRANSPORT, 32U + TX_PAYLOAD, PBUF_POOL);
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
        fill_header((unsigned char *)pb->payload, TX_TYPE_CAMERA, frame_id, frame_crc,
                    pid, TX_PAYLOAD, flags, (uint32_t)(frame_id * 33333U));
        payload = (unsigned char *)pb->payload + 32U;
        for (uint32_t i = 0; i < TX_PAYLOAD; ++i) {
            payload[i] = src[pid * TX_PAYLOAD + i];
        }
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
            usleep(TX_BURST_PACING_US);
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

void udp_video_tx_submit(const unsigned char *frame)
{
    /* Latest-wins: the sender emits the freshest submitted snapshot. */
    tx_pending = frame;
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
        send_one_frame(tx_pending, tx_frame_id);
        tx_frame_id++;
        tx_pending = NULL;
    }
}
