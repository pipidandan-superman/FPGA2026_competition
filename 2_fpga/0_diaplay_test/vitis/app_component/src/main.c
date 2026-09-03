#include <stdint.h>

#define UART1_STATUS (*(volatile uint32_t *)0xE000102CUL)
#define UART1_TX_FIFO (*(volatile uint32_t *)0xE0001030UL)
#define UART1_STATUS_TX_FULL (1UL << 4)

static void uart_putc(char byte)
{
    while ((UART1_STATUS & UART1_STATUS_TX_FULL) != 0UL) {
    }
    UART1_TX_FIFO = (uint32_t)(uint8_t)byte;
}

static void uart_puts(const char *text)
{
    while (*text != '\0') {
        uart_putc(*text);
        ++text;
    }
}

int main(void)
{
    volatile uint32_t delay;

    for (;;) {
        uart_puts("UART OK\r\n");
        for (delay = 0UL; delay < 10000000UL; ++delay) {
        }
    }

    return 0;
}
