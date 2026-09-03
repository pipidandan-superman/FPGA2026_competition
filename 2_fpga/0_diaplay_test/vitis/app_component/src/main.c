#include <stdint.h>
#include "xparameters.h"
extern void usleep(unsigned long useconds);
extern void xil_printf(const char *format, ...);
extern char inbyte(void);
extern void outbyte(char byte);

#define UART_SELF_TEST_HEARTBEATS 3U
#define UART_SELF_TEST_DELAY_US 1000000UL

static void print_uart_self_test_header(void)
{
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf(" EES-331 HDMI UART SELF TEST\r\n");
    xil_printf("========================================\r\n");
    xil_printf("UART instance : ps7_uart_1\r\n");
    xil_printf("UART base     : 0x%08lx\r\n", (unsigned long)XPAR_XUARTPS_0_BASEADDR);
    xil_printf("Expected fmt  : 115200-8-N1\r\n");
    xil_printf("Test          : TX heartbeat + RX echo\r\n");
}

static void run_tx_heartbeat(void)
{
    uint32_t heartbeat;

    for (heartbeat = 1U; heartbeat <= UART_SELF_TEST_HEARTBEATS; ++heartbeat) {
        xil_printf("[UART TX] heartbeat %lu/3\r\n", (unsigned long)heartbeat);
        usleep(UART_SELF_TEST_DELAY_US);
    }
}

static void run_rx_echo(void)
{
    char received;

    xil_printf("[UART RX] Type any character; each byte will be echoed.\r\n");
    xil_printf("[UART RX] Press Enter to emit a new line.\r\n");

    for (;;) {
        received = inbyte();
        outbyte(received);

        if (received == '\r') {
            outbyte('\n');
            xil_printf("[UART RX] echoed CR\r\n");
        } else if (received == '\n') {
            xil_printf("[UART RX] echoed LF\r\n");
        }
    }
}

int main(void)
{
    print_uart_self_test_header();
    run_tx_heartbeat();
    run_rx_echo();

    return 0;
}
