/************************************************************************
 * File Name       : udp_video_tx.h
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : udp_video_tx
 * Description     : Board-to-PC UDP video sender (lwIP RAW API), stage B1.
 *                   Emits 640x480 RGB888 frames as 640 datagrams/frame
 *                   (32 B header + 1440 B pixels) to the PC peer at
 *                   192.168.240.2:5000, per the data-format design doc.
 *                   Stage C1 will replace the pattern source with a real
 *                   VDMA frame snapshot; the API stays unchanged.
 * Dependencies    : lwip220 RAW API (NO_SYS=1)
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release, synthetic pattern source.
 ************************************************************************/

#ifndef __UDP_VIDEO_TX_H_
#define __UDP_VIDEO_TX_H_

#include "lwip/init.h"

/* Frame source (stage C1): the caller copies the latest COMPLETED camera
 * frame into a private stable buffer and hands it over via
 * udp_video_tx_submit(). Latest-wins: the sender emits the freshest
 * submitted snapshot once per UDP_TX_FRAME_INTERVAL_MS. */

/* Send one submitted frame every UDP_TX_FRAME_INTERVAL_MS milliseconds
 * (66 ms ≈ 15 fps). */
#define UDP_TX_FRAME_INTERVAL_MS 66U

void udp_video_tx_init(void);
void udp_video_tx_submit(const unsigned char *frame, uint32_t frame_crc);
/* 1 while a submitted frame is still awaiting its send slot. */
uint32_t udp_video_tx_pending(void);
/* Call periodically from eth_service(); the caller passes a monotonically
 * increasing millisecond counter. Sends a burst when the next frame
 * interval expires; the burst keeps the stack serviced between chunks. */
void udp_video_tx_poll(uint32_t now_ms);

#endif
