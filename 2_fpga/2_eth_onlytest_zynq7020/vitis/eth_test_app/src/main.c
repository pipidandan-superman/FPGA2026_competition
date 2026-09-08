/************************************************************************
 * File Name       : main.c
 * Developer       : LSL
 * Date            : 2026-09-08
 * Project Name    : AMD embodied sorting / EES-331 XC7Z020
 * Module Name     : eth_test_app
 * Description     : PS-only Ethernet bring-up on EES-331 ENET0 (88E1518).
 *                   Stage 0 : UART banner and heartbeat check (UART1, MIO48/49).
 *                   Stage 1 : lwIP RAW init, static IP 192.168.240.10/24.
 *                   Stage 2 : ICMP echo reply (ping) comes free with lwIP.
 *                   Stage 3 : UDP loopback echo service on port 5000.
 *                   PC peer  : 192.168.240.2/24 (Realtek USB/RJ45 NIC).
 * Dependencies    : lwip220(RAW_API), xiltimer, standalone, emacps, scugic,
 *                   scutimer, platform.c/platform_zynq.c from AMD template.
 * Revision History:
 *   - V1.0 (2026-09-08) by LSL : Initial release, staged bring-up version.
 ************************************************************************/

#include <stdio.h>

#include "xparameters.h"

#include "netif/xadapter.h"

#include "platform.h"
#include "platform_config.h"
#include "xil_printf.h"

#include "lwip/init.h"
#include "lwip/tcp.h"
#include "xil_cache.h"

#include "udp_echo.h"

#if LWIP_IPV6 == 1
#include "lwip/ip.h"
#else
#if LWIP_DHCP == 1
#include "lwip/dhcp.h"
#endif
#endif

/* Provided by platform.c; counts DHCP negotiation retries. */
volatile int dhcp_timoutcntr = 0;
extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;

/* lwIP periodic timers, driven from the main loop in RAW mode. */
void tcp_fasttmr(void);
void tcp_slowtmr(void);

/* Shared with platform.c/platform_zynq.c link-detect path. */
struct netif server_netif;
struct netif *echo_netif;

static void print_ip(char *msg, ip_addr_t *ip)
{
    print(msg);
    xil_printf("%d.%d.%d.%d\r\n", ip4_addr1(ip), ip4_addr2(ip),
               ip4_addr3(ip), ip4_addr4(ip));
}

static void print_ip_settings(ip_addr_t *ip, ip_addr_t *mask, ip_addr_t *gw)
{
    print_ip("Board IP  : ", ip);
    print_ip("Netmask   : ", mask);
    print_ip("Gateway   : ", gw);
}

int main(void)
{
    ip_addr_t ipaddr;
    ip_addr_t netmask;
    ip_addr_t gw;
    unsigned char mac_ethernet_address[] =
        { 0x00, 0x0A, 0x35, 0x00, 0x01, 0x02 };
    u32_t slow_tmr_ticks = 0;

    echo_netif = &server_netif;

    /* Stage 0: if this banner shows, UART1/DDR/app execution path is alive. */
    xil_printf("\r\n");
    xil_printf("==================================================\r\n");
    xil_printf(" EES-331 eth_test_app V1.0 (2026-09-08)\r\n");
    xil_printf(" STAGE0_UART_OK : UART1 MIO48/49 115200-8-N1\r\n");
    xil_printf("==================================================\r\n");

    init_platform();
    xil_printf("STAGE0_PLATFORM_OK : timer and interrupts ready\r\n");

    /* Stage 1: static addressing, no DHCP server exists on a direct link. */
    IP4_ADDR(&ipaddr, 192, 168, 240, 10);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gw, 192, 168, 240, 2);

    lwip_init();

    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gw, mac_ethernet_address,
                   PLATFORM_EMAC_BASEADDR)) {
        xil_printf("STAGE1_FAIL : xemac_add rejected GEM0 interface\r\n");
        return -1;
    }
    netif_set_default(echo_netif);

#ifndef SDT
    platform_enable_interrupts();
#endif

    netif_set_up(echo_netif);

    print_ip_settings(&ipaddr, &netmask, &gw);
    xil_printf("STAGE1_LWIP_OK : netif up, MAC 00:0A:35:00:01:02\r\n");

    /* Stage 2: ICMP echo reply is handled by lwIP automatically.
     * Acceptance probe: from PC run  ping 192.168.240.10            */

    /* Stage 3: UDP loopback echo on port 5000.
     * Acceptance probe: PC sends any UDP payload to 192.168.240.10:5000
     * and must receive the identical payload back.                   */
    start_udp_echo(5000);
    xil_printf("STAGE3_UDP_ECHO_OK : listening on UDP port 5000\r\n");
    xil_printf("LOOPBACK_TEST_READY\r\n");

    while (1) {
        if (TcpFastTmrFlag) {
            tcp_fasttmr();
            TcpFastTmrFlag = 0;
        }
        if (TcpSlowTmrFlag) {
            tcp_slowtmr();
            TcpSlowTmrFlag = 0;
            slow_tmr_ticks++;
            if ((slow_tmr_ticks % 20U) == 0U) {
                udp_echo_report();
            }
        }
        xemacif_input(echo_netif);
    }

    /* Never reached. */
    cleanup_platform();
    return 0;
}
