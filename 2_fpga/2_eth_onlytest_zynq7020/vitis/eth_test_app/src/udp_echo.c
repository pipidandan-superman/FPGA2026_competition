/************************************************************************
 * File Name       : udp_echo.c
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : udp_echo
 * Description     : UDP loopback echo service (lwIP RAW API). Binds
 *                   UDP 5000, echoes every datagram back to its sender
 *                   and keeps packet/byte counters for UART reporting.
 * Dependencies    : lwip220 RAW API (NO_SYS=1)
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release.
 ************************************************************************/

#include "xil_printf.h"
#include "lwip/udp.h"
#include "udp_echo.h"

#define UDP_ECHO_PRINT_GATE 50U

static volatile u32_t echo_rx_packets = 0;
static volatile u32_t echo_rx_bytes = 0;
static volatile u32_t echo_tx_packets = 0;
static volatile u32_t echo_tx_bytes = 0;
static volatile u32_t echo_tx_errors = 0;

static void udp_echo_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                          const ip_addr_t *addr, u16_t port)
{
    err_t err;

    (void)arg;

    if (p == NULL) {
        return;
    }

    echo_rx_packets++;
    echo_rx_bytes += p->tot_len;

    if ((echo_rx_packets <= 3U) || ((echo_rx_packets % UDP_ECHO_PRINT_GATE) == 0U)) {
        xil_printf("UDP_ECHO rx #%u %u bytes from %s:%u\r\n",
                   (unsigned)echo_rx_packets, (unsigned)p->tot_len,
                   ipaddr_ntoa(addr), (unsigned)port);
    }

    err = udp_sendto(pcb, p, addr, port);
    if (err == ERR_OK) {
        echo_tx_packets++;
        echo_tx_bytes += p->tot_len;
    } else {
        echo_tx_errors++;
        xil_printf("UDP_ECHO tx error %d\r\n", (int)err);
    }

    pbuf_free(p);
}

void start_udp_echo(u16_t port)
{
    struct udp_pcb *pcb;
    err_t err;

    pcb = udp_new_ip_type(IPADDR_TYPE_ANY);
    if (pcb == NULL) {
        xil_printf("UDP_ECHO pcb_alloc_fail\r\n");
        return;
    }

    err = udp_bind(pcb, IP_ANY_TYPE, port);
    if (err != ERR_OK) {
        xil_printf("UDP_ECHO bind_fail port %u err %d\r\n", (unsigned)port,
                   (int)err);
        return;
    }

    udp_recv(pcb, udp_echo_recv, NULL);
}

void udp_echo_report(void)
{
    xil_printf("HEARTBEAT rx=%u/%uB tx=%u/%uB err=%u\r\n",
               (unsigned)echo_rx_packets, (unsigned)echo_rx_bytes,
               (unsigned)echo_tx_packets, (unsigned)echo_tx_bytes,
               (unsigned)echo_tx_errors);
}
