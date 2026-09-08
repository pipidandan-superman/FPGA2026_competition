/************************************************************************
 * File Name       : udp_echo.h
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : udp_echo
 * Description     : UDP loopback echo service (lwIP RAW API). The board
 *                   binds UDP port 5000 and returns every received
 *                   datagram unchanged to its sender, which proves the
 *                   full RX path (PHY/RGMII/GEM/lwIP) and TX path.
 * Dependencies    : lwip220 RAW API (NO_SYS=1)
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release.
 ************************************************************************/

#ifndef __UDP_ECHO_H_
#define __UDP_ECHO_H_

#include "lwip/udp.h"

void start_udp_echo(u16_t port);

/* Print one heartbeat line: rx packets/bytes, tx packets/bytes, errors. */
void udp_echo_report(void);

#endif
