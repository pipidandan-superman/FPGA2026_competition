#include "xil_printf.h"

int main(void)
{
    unsigned int index = 0U;

    for (;;) {
        xil_printf("UART OK %u\r\n", index);
        ++index;
        if (index >= 5U) {
            break;
        }
        for (volatile unsigned int delay = 0U; delay < 10000000U; ++delay) {
        }
    }
    for (;;) {
    }
}
